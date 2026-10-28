// JEDEC checker on the DFI command stream, rules in jedec_check.cpp (DPI-C)
// +dfi_trace=<file> dumps the stream as CSV for make trace-check
class dfi_checker extends uvm_subscriber #(dfi_item);
    `uvm_component_utils(dfi_checker)

    int fd;
    int unsigned n_cmd;
    int unsigned n_bad;
    int rule; // index into rules[] of a gap exactly at its minimum

    // gap exactly at the minimum, per rule
    // no bin, unreachable by design: tRRD 4, tZQinit 13, tFAW 14
    covergroup cg_jedec;
        cp_rule: coverpoint rule {
            bins trcd = {0}; bins trp = {1}; bins tras = {2}; bins trc = {3};
            bins trtp = {5}; bins twr = {6}; bins tccd = {7}; bins twtr = {8};
            bins rd_wr = {9}; bins trfc = {10}; bins tmrd = {11}; bins tmod = {12};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_jedec = new();
    endfunction

    function void build_phase(uvm_phase phase);
        string path;
        super.build_phase(phase);
        jedec_reset();
        if ($value$plusargs("dfi_trace=%s", path)) begin
            fd = $fopen(path, "w");
            if (fd == 0) `uvm_fatal("JEDEC", {"cannot open ", path})
            $fdisplay(fd, "cyc,cmd,bank,addr");
        end
    endfunction

    // one DFI command from dfi_monitor
    function void write(dfi_item t);
        string err = jedec_cmd(int'(t.kind), int'(t.bank), int'(t.addr), longint'(t.cyc));
        int exact = jedec_exact();
        n_cmd++;
        if (err != "") begin
            n_bad++;
            `uvm_error("JEDEC", $sformatf("@%0d %s", t.cyc, err))
        end
        for (int i = 0; i < 32; i++)
            if (exact[i]) begin
                rule = i;
                cg_jedec.sample();
            end
        if (fd != 0) $fdisplay(fd, "%0d,%s,%0d,%h", t.cyc, jedec_name(int'(t.kind)), t.bank, t.addr);
    endfunction

    function void final_phase(uvm_phase phase);
        if (fd != 0) $fclose(fd);
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("JEDEC", $sformatf("commands checked %0d, with violations %0d", n_cmd, n_bad), UVM_NONE)
    endfunction
endclass
