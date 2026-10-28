// scoreboard: predicts each read from ref_mem when accepted (the DUT completes in order),
// checks read data in order
class mc_scoreboard extends uvm_component;
    `uvm_component_utils(mc_scoreboard)

    uvm_analysis_imp_req #(mc_item, mc_scoreboard) req_imp;
    uvm_analysis_imp_rsp #(mc_item, mc_scoreboard) rsp_imp;

    mc_item pend [$];
    bit [BURST_LEN*DQ_W-1:0] expd [$];
    bit written [int unsigned];
    int unsigned n_req;
    int unsigned n_wr;
    int unsigned n_rd;
    int unsigned n_raw; // reads of an address written earlier
    int unsigned n_bad;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        req_imp = new("req_imp", this);
        rsp_imp = new("rsp_imp", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ref_mem_reset();
    endfunction

    // accepted request: writes update the model, reads queue a prediction
    function void write_req(mc_item t);
        n_req++;
        if (t.wr) begin
            ref_mem_write(t.key(), t.wdata, t.wmask);
            written[t.key()] = 1'b1;
            n_wr++;
        end else begin
            expd.push_back(ref_mem_read(t.key()));
            pend.push_back(t);
            if (written.exists(t.key())) n_raw++;
        end
    endfunction

    // read return: compare with the oldest prediction
    function void write_rsp(mc_item r);
        mc_item t;
        bit [BURST_LEN*DQ_W-1:0] e;
        if (pend.size() == 0) begin
            `uvm_error("SB", "read data with no read outstanding")
            return;
        end
        t = pend.pop_front();
        e = expd.pop_front();
        n_rd++;
        if (r.rdata !== e) begin
            n_bad++;
            `uvm_error("SB", $sformatf("%s: got %h exp %h", t.convert2string(), r.rdata, e))
        end
    endfunction

    function int unsigned outstanding();
        return pend.size();
    endfunction

    // reads of unwritten data return 0 and prove nothing
    function void check_phase(uvm_phase phase);
        if (pend.size() != 0) `uvm_error("SB", $sformatf("%0d reads never returned", pend.size()))
        if (n_raw == 0) `uvm_error("SB", "no read of written data, data check vacuous")
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SB", $sformatf("writes %0d, reads checked %0d (%0d of written data), mismatches %0d", n_wr, n_rd, n_raw, n_bad), UVM_NONE)
    endfunction
endclass
