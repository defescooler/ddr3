// env: host agent, DFI monitor, scoreboard, coverage, JEDEC checker
class mc_env extends uvm_env;
    `uvm_component_utils(mc_env)

    mc_agent agent;
    dfi_monitor dfi_mon;
    mc_scoreboard sb;
    mc_coverage cov;
    dfi_checker chk;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = mc_agent::type_id::create("agent", this);
        dfi_mon = dfi_monitor::type_id::create("dfi_mon", this);
        sb = mc_scoreboard::type_id::create("sb", this);
        cov = mc_coverage::type_id::create("cov", this);
        chk = dfi_checker::type_id::create("chk", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        agent.mon.req_ap.connect(sb.req_imp);
        agent.mon.rsp_ap.connect(sb.rsp_imp);
        dfi_mon.ap.connect(cov.analysis_export);
        dfi_mon.ap.connect(chk.analysis_export);
    endfunction
endclass
