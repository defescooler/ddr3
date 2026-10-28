typedef uvm_sequencer #(mc_item) mc_sequencer;

// host agent: sequencer, driver, monitor
class mc_agent extends uvm_agent;
    `uvm_component_utils(mc_agent)

    mc_sequencer sqr;
    mc_driver drv;
    mc_monitor mon;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = mc_monitor::type_id::create("mon", this);
        if (get_is_active() == UVM_ACTIVE) begin
            sqr = mc_sequencer::type_id::create("sqr", this);
            drv = mc_driver::type_id::create("drv", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        if (get_is_active() == UVM_ACTIVE) drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass
