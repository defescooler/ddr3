// host monitor: accepted requests on req_ap, read data on rsp_ap
class mc_monitor extends uvm_monitor;
    `uvm_component_utils(mc_monitor)

    virtual host_if vif;
    uvm_analysis_port #(mc_item) req_ap;
    uvm_analysis_port #(mc_item) rsp_ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        req_ap = new("req_ap", this);
        rsp_ap = new("rsp_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual host_if)::get(this, "", "host_vif", vif))
            `uvm_fatal("NOVIF", "host_vif not set")
    endfunction

    task run_phase(uvm_phase phase);
        mc_item t;
        dram_addr_t a;
        forever begin
            @(vif.mon_cb);
            if (!vif.rst_n) continue;
            // accepted on app_req && app_rdy
            if (vif.mon_cb.app_req && vif.mon_cb.app_rdy) begin
                t = mc_item::type_id::create("req");
                a = vif.mon_cb.app_addr;
                t.wr = (vif.mon_cb.app_cmd == REQ_WRITE);
                t.bank = a.bank;
                t.row = a.row;
                t.blk = a.col[COL_W-1:3];
                t.wdata = vif.mon_cb.app_wdata;
                t.wmask = vif.mon_cb.app_wmask;
                if (a.col[2:0] != 0) `uvm_error("MON", "app_addr.col[2:0] != 0")
                req_ap.write(t);
            end
            // read data, valid only with app_rvalid
            if (vif.mon_cb.app_rvalid) begin
                t = mc_item::type_id::create("rsp");
                t.rdata = vif.mon_cb.app_rdata;
                rsp_ap.write(t);
            end
        end
    endtask
endclass
