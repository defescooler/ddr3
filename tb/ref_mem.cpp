// DPI-C reference memory for mc_scoreboard: one 64-bit burst per {bank, row, col[9:3]}, unwritten reads 0

#include <unordered_map>

static std::unordered_map<unsigned int, unsigned long long> mem;

extern "C" void ref_mem_reset() {
    mem.clear();
}

// mask bit b = 1 keeps byte b
extern "C" void ref_mem_write(unsigned int key, unsigned long long data, unsigned char mask) {
    unsigned long long keep = 0;
    for (int b = 0; b < 8; b++)
        if ((mask >> b) & 1) keep |= 0xffULL << (8 * b);
    auto it = mem.find(key);
    unsigned long long old = (it == mem.end()) ? 0 : it->second;
    mem[key] = (old & keep) | (data & ~keep);
}

extern "C" unsigned long long ref_mem_read(unsigned int key) {
    auto it = mem.find(key);
    return (it == mem.end()) ? 0 : it->second;
}
