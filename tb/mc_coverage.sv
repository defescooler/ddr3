// functional coverage: commands, mode registers, banks, page outcome, FSM arcs
// bank group = coverage grouping (DDR3 has none): BG0 banks 0-3, BG1 banks 4-7
// FSM bins are state_t values of mc_ctrl, mc_refresh, mc_init
class mc_coverage extends uvm_subscriber #(dfi_item);
    `uvm_component_utils(mc_coverage)

    virtual fsm_if vif;

    // sampled values
    bit [3:0] kind;
    bit [BANK_W-1:0] bank;
    bit [1:0] page;
    bit [1:0] sw;
    bit dir_wr;
    bit [2:0] ctrl_st;
    bit [1:0] ref_st;
    bit [3:0] init_st;
    bit urgent;

    // page classification state, per bank
    bit pre_miss [NUM_BANKS];
    bit act_new [NUM_BANKS];
    bit [1:0] act_page [NUM_BANKS];
    bit [BANK_W-1:0] last_col_bank;
    bit seen_col;

    // commands and command pairs
    covergroup cg_cmd;
        cp_cmd: coverpoint kind {
            bins mrs = {`K_MRS}; bins ref_ = {`K_REF}; bins pre = {`K_PRE}; bins prea = {`K_PREA};
            bins act = {`K_ACT}; bins wr = {`K_WR}; bins rd = {`K_RD}; bins zqcl = {`K_ZQCL};
        }
        cp_seq: coverpoint kind {
            bins act_rd = (`K_ACT => `K_RD);
            bins act_wr = (`K_ACT => `K_WR);
            bins rd_rd = (`K_RD => `K_RD);
            bins rd_wr = (`K_RD => `K_WR);
            bins wr_rd = (`K_WR => `K_RD);
            bins wr_wr = (`K_WR => `K_WR);
            bins rd_pre = (`K_RD => `K_PRE);
            bins wr_pre = (`K_WR => `K_PRE);
            bins pre_act = (`K_PRE => `K_ACT);
            bins prea_ref = (`K_PREA => `K_REF);
            bins ref_ref = (`K_REF => `K_REF);
            bins ref_act = (`K_REF => `K_ACT);
        }
    endgroup

    // MRS to each mode register
    covergroup cg_mr;
        cp_mr: coverpoint bank { bins mr0 = {0}; bins mr1 = {1}; bins mr2 = {2}; bins mr3 = {3}; }
    endgroup

    // banks, bank groups, command x bank
    covergroup cg_bank;
        cp_bank: coverpoint bank { bins b[] = {[0:7]}; }
        cp_group: coverpoint bank { bins bg0 = {[0:3]}; bins bg1 = {[4:7]}; }
        cp_bank_cmd: coverpoint kind { bins act = {`K_ACT}; bins rd = {`K_RD}; bins wr = {`K_WR}; bins pre = {`K_PRE}; }
        x_cmd_bank: cross cp_bank_cmd, cp_bank;
        x_cmd_group: cross cp_bank_cmd, cp_group;
    endgroup

    // bank switch between consecutive column commands
    covergroup cg_switch;
        cp_switch: coverpoint sw { bins same_bank = {`SW_BANK}; bins same_group = {`SW_GROUP}; bins other_group = {`SW_OTHER}; }
    endgroup

    // page hit, empty, miss x read, write
    covergroup cg_page;
        cp_page: coverpoint page { bins hit = {`PG_HIT}; bins empty = {`PG_EMPTY}; bins miss = {`PG_MISS}; }
        cp_dir: coverpoint dir_wr { bins rd = {0}; bins wr = {1}; }
        x_page_dir: cross cp_page, cp_dir;
    endgroup

    // mc_ctrl arcs: S_IDLE 0, S_PRE 1, S_ACT 2, S_COL 3, S_REF 4
    covergroup cg_ctrl;
        cp_arc: coverpoint ctrl_st {
            bins idle_col = (0 => 3);
            bins idle_act = (0 => 2);
            bins idle_pre = (0 => 1);
            bins pre_act = (1 => 2);
            bins act_col = (2 => 3);
            bins col_idle = (3 => 0);
            bins idle_ref = (0 => 4);
            bins ref_idle = (4 => 0);
        }
    endgroup

    // why mc_ctrl entered S_REF
    covergroup cg_ref_cause;
        cp_cause: coverpoint urgent { bins opportunistic = {0}; bins urgent = {1}; }
    endgroup

    // mc_refresh arcs: S_IDLE 0, S_REQ 1, S_PREA 2, S_REF 3
    covergroup cg_refresh;
        cp_arc: coverpoint ref_st {
            bins idle_req = (0 => 1);
            bins req_prea = (1 => 2);
            bins prea_ref = (2 => 3);
            bins ref_idle = (3 => 0);
        }
    endgroup

    // mc_init arcs: S_RESET 0 to S_DONE 8
    covergroup cg_init;
        cp_arc: coverpoint init_st {
            bins reset_cke = (0 => 1);
            bins cke_txpr = (1 => 2);
            bins txpr_mr2 = (2 => 3);
            bins mr2_mr3 = (3 => 4);
            bins mr3_mr1 = (4 => 5);
            bins mr1_mr0 = (5 => 6);
            bins mr0_zqcl = (6 => 7);
            bins zqcl_done = (7 => 8);
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_cmd = new();
        cg_mr = new();
        cg_bank = new();
        cg_switch = new();
        cg_page = new();
        cg_ctrl = new();
        cg_ref_cause = new();
        cg_refresh = new();
        cg_init = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual fsm_if)::get(this, "", "fsm_vif", vif))
            `uvm_fatal("NOVIF", "fsm_vif not set")
    endfunction

    // one DFI command from dfi_monitor
    function void write(dfi_item t);
        kind = t.kind;
        bank = t.bank;
        cg_cmd.sample();
        case (kind)
            `K_MRS: cg_mr.sample();
            `K_PRE: begin
                pre_miss[bank] = 1'b1;
                cg_bank.sample();
            end
            `K_PREA: begin
                foreach (pre_miss[b]) pre_miss[b] = 1'b0;
            end
            `K_ACT: begin
                act_page[bank] = pre_miss[bank] ? `PG_MISS : `PG_EMPTY;
                act_new[bank] = 1'b1;
                pre_miss[bank] = 1'b0;
                cg_bank.sample();
            end
            `K_RD, `K_WR: begin
                page = act_new[bank] ? act_page[bank] : `PG_HIT;
                act_new[bank] = 1'b0;
                dir_wr = (kind == `K_WR);
                cg_page.sample();
                cg_bank.sample();
                if (seen_col) begin
                    if (bank == last_col_bank) sw = `SW_BANK;
                    else if (bank[2] == last_col_bank[2]) sw = `SW_GROUP;
                    else sw = `SW_OTHER;
                    cg_switch.sample();
                end
                last_col_bank = bank;
                seen_col = 1'b1;
            end
            default: ;
        endcase
    endfunction

    // FSM covergroups sampled on state change, so transition bins see consecutive states
    task run_phase(uvm_phase phase);
        bit urgent_q;
        ctrl_st = vif.ctrl_state;
        ref_st = vif.ref_state;
        init_st = vif.init_state;
        cg_ctrl.sample();
        cg_refresh.sample();
        cg_init.sample();
        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.ctrl_state != ctrl_st) begin
                if (ctrl_st == 0 && vif.mon_cb.ctrl_state == 4) begin
                    urgent = urgent_q;
                    cg_ref_cause.sample();
                end
                ctrl_st = vif.mon_cb.ctrl_state;
                cg_ctrl.sample();
            end
            if (vif.mon_cb.ref_state != ref_st) begin
                ref_st = vif.mon_cb.ref_state;
                cg_refresh.sample();
            end
            if (vif.mon_cb.init_state != init_st) begin
                init_st = vif.mon_cb.init_state;
                cg_init.sample();
            end
            urgent_q = vif.mon_cb.ref_urgent;
        end
    endtask
endclass
