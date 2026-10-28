// literal codes for covergroup bins (Verilator crashes on enum names in bins)

// DFI command kinds
`define K_MRS 4'd0
`define K_REF 4'd1
`define K_PRE 4'd2
`define K_PREA 4'd3
`define K_ACT 4'd4
`define K_WR 4'd5
`define K_RD 4'd6
`define K_ZQCL 4'd7

// page outcome of a column command
`define PG_HIT 2'd0
`define PG_EMPTY 2'd1
`define PG_MISS 2'd2

// bank switch between consecutive column commands
`define SW_BANK 2'd0
`define SW_GROUP 2'd1
`define SW_OTHER 2'd2

package mc_tb_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import mc_pkg::*;

    // DPI-C reference memory, ref_mem.cpp
    import "DPI-C" function void ref_mem_reset();
    import "DPI-C" function void ref_mem_write(input int unsigned key, input longint unsigned data, input byte unsigned mask);
    import "DPI-C" function longint unsigned ref_mem_read(input int unsigned key);

    // DPI-C JEDEC checker, jedec_check.cpp
    import "DPI-C" function void jedec_reset();
    import "DPI-C" function string jedec_cmd(input int kind, input int bank, input int addr, input longint cyc);
    import "DPI-C" function int jedec_exact();
    import "DPI-C" function string jedec_name(input int kind);

    `uvm_analysis_imp_decl(_req)
    `uvm_analysis_imp_decl(_rsp)

    `include "mc_item.sv"
    `include "mc_driver.sv"
    `include "mc_monitor.sv"
    `include "mc_agent.sv"
    `include "dfi_monitor.sv"
    `include "dfi_checker.sv"
    `include "mc_scoreboard.sv"
    `include "mc_coverage.sv"
    `include "mc_env.sv"
    `include "mc_seqs.sv"
    `include "mc_tests.sv"
endpackage : mc_tb_pkg
