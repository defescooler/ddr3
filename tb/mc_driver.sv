// host driver: holds each request until app_req && app_rdy
class mc_driver extends uvm_driver #(mc_item);
    `uvm_component_utils(mc_driver)

    virtual host_if vif;
    int unsigned n_sent; // requests the DUT accepted

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual host_if)::get(this, "", "host_vif", vif))
            `uvm_fatal("NOVIF", "host_vif not set")
    endfunction

    task run_phase(uvm_phase phase);
        mc_item t;
        vif.drv_cb.app_req <= 1'b0;
        forever begin
            seq_item_port.get_next_item(t);
            repeat (t.idle) @(vif.drv_cb);
            // drive right after an edge
            @(vif.drv_cb);
            vif.drv_cb.app_req <= 1'b1;
            vif.drv_cb.app_cmd <= t.wr ? REQ_WRITE : REQ_READ;
            vif.drv_cb.app_addr <= t.addr();
            vif.drv_cb.app_wdata <= t.wdata;
            vif.drv_cb.app_wmask <= t.wmask;
            // hold until accepted
            do @(vif.drv_cb); while (!(vif.drv_cb.app_req && vif.drv_cb.app_rdy));
            vif.drv_cb.app_req <= 1'b0;
            `uvm_info("DRV", {"accepted ", t.convert2string()}, UVM_HIGH)
            n_sent++;
            seq_item_port.item_done();
        end
    endtask
endclass
