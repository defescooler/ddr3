// DPI-C JEDEC checker for the DFI command stream: rule table of minimum gaps, plus tFAW, tDLLK,
// tRAS max, refresh gap, bank state for REF/MRS/ZQCL and MRS values
// limits from the -15E x8 datasheet at tCK 1.5 ns, CL 9, CWL 7, AL 0, BL8, never from mc_pkg
// -DJEDEC_MAIN builds the offline trace checker

#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <deque>
#include <string>

// Verilator DPI prototypes: a signature mismatch with the SV imports fails to compile
#if __has_include("Vtb_top__Dpi.h")
#include "Vtb_top__Dpi.h"
#endif

// command codes, same as the `K_* defines in mc_tb_pkg.sv
enum { MRS, REF, PRE, PREA, ACT, WR, RD, ZQCL, N_KIND };
static const char* const kind_name[N_KIND] = {"MRS", "REF", "PRE", "PREA", "ACT", "WR", "RD", "ZQCL"};

// device and mode
static const int TCK_PS = 1500;
static const int RL = 9; // AL 0 + CL 9
static const int WL = 7; // AL 0 + CWL 7
static const int BURST = 4; // BL8 on the bus, clk

// datasheet minimum in clk: ps rounded up, at least lo clk
static constexpr int ck(int ps, int lo = 0) {
    return (ps + TCK_PS - 1) / TCK_PS > lo ? (ps + TCK_PS - 1) / TCK_PS : lo;
}

static constexpr int bit(int k) {
    return 1 << k;
}

static const int ALL = bit(N_KIND) - 1;
static const int RANK = bit(PREA) | bit(REF) | bit(MRS) | bit(ZQCL); // address every bank

// a command in next must come at least min clk after the latest command in prev
// SAME: same bank, OTHER: another bank, ANY: any bank; a RANK command counts for every bank
enum scope_t { SAME, OTHER, ANY };

struct rule {
    const char* name;
    int prev;
    int next;
    scope_t scope;
    int min;
};

static const rule rules[] = {
    {"tRCD", bit(ACT), bit(RD) | bit(WR), SAME, ck(13500)},
    {"tRP", bit(PRE) | bit(PREA), bit(ACT) | bit(REF) | bit(MRS) | bit(ZQCL), SAME, ck(13500)},
    {"tRAS", bit(ACT), bit(PRE) | bit(PREA), SAME, ck(36000)},
    {"tRC", bit(ACT), bit(ACT), SAME, ck(49500)},
    {"tRRD", bit(ACT), bit(ACT), OTHER, ck(6000, 4)},
    {"tRTP", bit(RD), bit(PRE) | bit(PREA), SAME, ck(7500, 4)},
    {"tWR", bit(WR), bit(PRE) | bit(PREA), SAME, WL + BURST + ck(15000)}, // from the last write data
    {"tCCD", bit(RD) | bit(WR), bit(RD) | bit(WR), ANY, 4},
    {"tWTR", bit(WR), bit(RD), ANY, WL + BURST + ck(7500, 4)}, // from the last write data
    {"RD to WR", bit(RD), bit(WR), ANY, RL + 4 + 2 - WL}, // RL + tCCD + 2tCK - WL
    {"tRFC", bit(REF), ALL, SAME, ck(110000)},
    {"tMRD", bit(MRS), bit(MRS), ANY, 4},
    {"tMOD", bit(MRS), ALL & ~bit(MRS), ANY, ck(15000, 12)},
    {"tZQinit", bit(ZQCL), ALL, ANY, 512},
};

static const int N_RULE = sizeof rules / sizeof rules[0];
static const int TFAW = ck(30000); // at most 4 ACT in any tFAW window, exact bit N_RULE
static const int TDLLK = 512; // DLL reset (MR0 A8) to RD
static const long long REFI9 = 9LL * (7800000 / TCK_PS); // longest REF gap (8 postponed) and tRAS max
static const long long NEVER = -(1LL << 60);

// checker state
static long long last[N_KIND][8]; // cycle of the latest command of each kind, per bank
static bool bank_open[8];
static bool ras_late[8]; // tRAS max already reported for the open row
static std::deque<long long> acts; // cycles of the latest 4 ACT
static long long ref_from; // start of the current refresh interval, NEVER until init ends
static bool ref_late;
static long long dll_reset; // cycle of the latest MR0 with DLL reset
static int exact; // bit i: rules[i] met exactly at its minimum by the last command
static std::string err;

static void fail(const char* fmt, ...) {
    char buf[160];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    if (!err.empty()) err += "; ";
    err += buf;
}

// MRS values must set the latencies the rules assume and leave the device in normal mode
static void check_mrs(int mr, int a) {
    if (mr == 0) {
        if (a & 3) fail("MR0: burst length not fixed BL8");
        if (((a >> 4) & 7) != 5 || ((a >> 2) & 1)) fail("MR0: CL not 9");
        if ((a >> 7) & 1) fail("MR0: test mode");
        if (((a >> 9) & 7) != 5) fail("MR0: WR not 10");
    } else if (mr == 1) {
        if (a & 1) fail("MR1: DLL disabled");
        if ((a >> 3) & 3) fail("MR1: AL not 0");
        if ((a >> 7) & 1) fail("MR1: write leveling on");
        if ((a >> 12) & 1) fail("MR1: output buffers off (Qoff)");
    } else if (mr == 2) {
        if (((a >> 3) & 7) != 2) fail("MR2: CWL not 7");
    } else if (mr == 3) {
        if ((a >> 2) & 1) fail("MR3: MPR enabled");
    }
}

extern "C" void jedec_reset() {
    for (auto& k : last)
        for (long long& c : k) c = NEVER;
    for (bool& o : bank_open) o = false;
    for (bool& l : ras_late) l = false;
    acts.clear();
    ref_from = NEVER;
    ref_late = false;
    dll_reset = NEVER;
    exact = 0;
}

extern "C" const char* jedec_name(int kind) {
    return (kind >= 0 && kind < N_KIND) ? kind_name[kind] : "?";
}

// one command; returns "" or the violations, valid until the next call
extern "C" const char* jedec_cmd(int kind, int bank, int addr, long long cyc) {
    if (kind == PRE && (addr >> 10 & 1)) kind = PREA;
    bool rank = bit(kind) & RANK;
    err.clear();
    exact = 0;

    // minimum gaps, measured from the latest earlier command each rule applies to
    for (int i = 0; i < N_RULE; i++) {
        const rule& r = rules[i];
        if (!(r.next & bit(kind))) continue;
        long long t = NEVER;
        int tk = 0;
        int tb = 0;
        for (int k = 0; k < N_KIND; k++) {
            if (!(r.prev & bit(k))) continue;
            for (int b = 0; b < 8; b++) {
                bool in = r.scope == ANY || rank || (r.scope == SAME) == (b == bank);
                if (in && last[k][b] > t) {
                    t = last[k][b];
                    tk = k;
                    tb = b;
                }
            }
        }
        if (t == NEVER) continue;
        if (cyc - t < r.min)
            fail("%s: %s b%d @%lld to %s, %lld < %d clk", r.name, kind_name[tk], tb, t, kind_name[kind], cyc - t, r.min);
        else if (cyc - t == r.min)
            exact |= bit(i);
    }

    // four-activate window
    if (kind == ACT) {
        if (acts.size() == 4) {
            long long w = cyc - acts.front();
            if (w < TFAW) fail("tFAW: 5 ACT within %lld < %d clk", w, TFAW);
            else if (w == TFAW) exact |= bit(N_RULE);
            acts.pop_front();
        }
        acts.push_back(cyc);
    }

    // tRAS max: no row open longer than 9 tREFI
    for (int b = 0; b < 8; b++)
        if (bank_open[b] && !ras_late[b] && cyc - last[ACT][b] > REFI9) {
            fail("tRAS max: bank %d open for %lld clk, max %lld", b, cyc - last[ACT][b], REFI9);
            ras_late[b] = true;
        }

    // DLL lock: no RD within tDLLK of a DLL reset
    if (kind == RD && cyc - dll_reset < TDLLK) fail("tDLLK: RD %lld clk after DLL reset, %d min", cyc - dll_reset, TDLLK);

    // refresh: no gap over 9 tREFI, the first one counted from ZQCL (end of init)
    if (ref_from != NEVER && !ref_late && cyc - ref_from > REFI9) {
        fail("refresh: no REF for %lld clk after @%lld, max %lld", cyc - ref_from, ref_from, REFI9);
        ref_late = true;
    }
    if (kind == REF || (kind == ZQCL && ref_from == NEVER)) {
        ref_from = cyc;
        ref_late = false;
    }

    // REF, MRS and ZQCL need every bank precharged
    if (kind == REF || kind == MRS || kind == ZQCL)
        for (int b = 0; b < 8; b++)
            if (bank_open[b]) fail("%s with bank %d open", kind_name[kind], b);
    if (kind == ACT) {
        bank_open[bank] = true;
        ras_late[bank] = false;
    }
    if (kind == PRE) bank_open[bank] = false;
    if (kind == PREA)
        for (bool& o : bank_open) o = false;

    if (kind == MRS) {
        check_mrs(bank, addr);
        if (bank == 0 && (addr >> 8 & 1)) dll_reset = cyc;
    }

    for (int b = 0; b < 8; b++)
        if (rank || b == bank) last[kind][b] = cyc;
    return err.c_str();
}

extern "C" int jedec_exact() {
    return exact;
}

#ifdef JEDEC_MAIN
// offline: trace CSV from +dfi_trace, cyc,cmd,bank,addr (hex); exit 1 on any violation
int main(int argc, char** argv) {
    FILE* f = argc > 1 ? fopen(argv[1], "r") : stdin;
    if (!f) {
        perror(argv[1]);
        return 2;
    }
    char line[128];
    char name[8];
    long long cyc;
    int bank;
    unsigned addr;
    int n = 0;
    int bad = 0;
    int hits[N_RULE + 1] = {};
    jedec_reset();
    while (fgets(line, sizeof line, f)) {
        if (sscanf(line, "%lld,%7[^,],%d,%x", &cyc, name, &bank, &addr) != 4) continue; // header
        int kind = 0;
        while (kind < N_KIND && strcmp(name, kind_name[kind])) kind++;
        if (kind == N_KIND) {
            fprintf(stderr, "unknown command %s\n", name);
            return 2;
        }
        const char* e = jedec_cmd(kind, bank, (int)addr, cyc);
        n++;
        if (*e) {
            printf("@%lld %s\n", cyc, e);
            bad++;
        }
        for (int i = 0; i <= N_RULE; i++)
            if (exact & bit(i)) hits[i]++;
    }
    printf("exact minimum reached:");
    for (int i = 0; i <= N_RULE; i++) printf(" %s %d", i < N_RULE ? rules[i].name : "tFAW", hits[i]);
    printf("\n%d commands, %d with violations\n", n, bad);
    return bad != 0;
}
#endif
