// base: build env, wait for init_done, run traffic, drain, report
class mc_base_test extends uvm_test;
    `uvm_component_utils(mc_base_test)

    mc_env env;
    virtual host_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = mc_env::type_id::create("env", this);
        if (!uvm_config_db#(virtual host_if)::get(this, "", "host_vif", vif))
            `uvm_fatal("NOVIF", "host_vif not set")
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        do @(vif.mon_cb); while (!vif.mon_cb.init_done);
        `uvm_info("INIT", "init_done", UVM_LOW)
        run_traffic();
        drain();
        phase.drop_objection(this);
    endtask

    virtual task run_traffic();
    endtask

    // all reads returned, controller idle, last write burst out
    task drain();
        int unsigned n;
        do begin
            @(vif.mon_cb);
            n++;
        end while ((env.sb.outstanding() != 0 || !vif.mon_cb.app_rdy) && n < 20_000);
        if (n >= 20_000) `uvm_error("DRAIN", "DUT did not go idle")
        repeat (32) @(vif.mon_cb);
    endtask

    // driver and monitor request counts must match
    function void check_phase(uvm_phase phase);
        if (env.agent.drv.n_sent != env.sb.n_req)
            `uvm_error("COUNT", $sformatf("driver sent %0d requests, monitor saw %0d", env.agent.drv.n_sent, env.sb.n_req))
    endfunction

    function void report_phase(uvm_phase phase);
        uvm_report_server rs = uvm_report_server::get_server();
        if (rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL) == 0)
            `uvm_info("RESULT", "TEST PASSED", UVM_NONE)
        else
            `uvm_info("RESULT", "TEST FAILED", UVM_NONE)
    endfunction
endclass

// one write and one read per bank
class mc_smoke_test extends mc_base_test;
    `uvm_component_utils(mc_smoke_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_traffic();
        mc_smoke_seq s = mc_smoke_seq::type_id::create("s");
        s.start(env.agent.sqr);
    endtask
endclass

// page hit, empty, miss on every bank at the exact timing gaps
class mc_page_test extends mc_base_test;
    `uvm_component_utils(mc_page_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_traffic();
        mc_page_seq s = mc_page_seq::type_id::create("s");
        s.start(env.agent.sqr);
    endtask
endclass

// idle 2 tREFI (opportunistic refresh), then saturate 9 tREFI (urgent refresh)
class mc_refresh_test extends mc_base_test;
    `uvm_component_utils(mc_refresh_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_traffic();
        mc_rand_seq s = mc_rand_seq::type_id::create("s");
        repeat (2 * TREFI_CYCLES + 200) @(vif.mon_cb);
        s.stream = 1'b1;
        fork
            s.start(env.agent.sqr);
            begin
                repeat (9 * TREFI_CYCLES) @(vif.mon_cb);
                s.stop = 1'b1;
            end
        join
    endtask
endclass

// constrained random, +n=<requests>
class mc_rand_test extends mc_base_test;
    `uvm_component_utils(mc_rand_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_traffic();
        mc_rand_seq s = mc_rand_seq::type_id::create("s");
        void'($value$plusargs("n=%d", s.n));
        s.start(env.agent.sqr);
    endtask
endclass
