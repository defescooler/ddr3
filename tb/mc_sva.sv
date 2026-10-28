// tRCD, tRP, tRAS assertions on the DFI command pins, bound into mc_top
// limits from the datasheet, not mc_pkg
module mc_sva (
    input logic clk,
    input logic rst_n,
    input logic cs_n,
    input logic ras_n,
    input logic cas_n,
    input logic we_n,
    input logic [2:0] bank,
    input logic addr10
);
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // datasheet limits at tCK = 1.5 ns
    localparam int TCK_PS = 1500;
    localparam int TRCD = (13500 + TCK_PS - 1) / TCK_PS; // 9
    localparam int TRP = (13500 + TCK_PS - 1) / TCK_PS; // 9
    localparam int TRAS = (36000 + TCK_PS - 1) / TCK_PS; // 24

    // command decode, {CS_n, RAS_n, CAS_n, WE_n}
    wire [3:0] cmd = {cs_n, ras_n, cas_n, we_n};
    wire act = (cmd == 4'b0011);
    wire col = (cmd == 4'b0101) || (cmd == 4'b0100);
    wire pre = (cmd == 4'b0010);

    for (genvar b = 0; b < 8; b++) begin : g_bank
        wire act_b = act && (bank == 3'(b));
        wire col_b = col && (bank == 3'(b));
        wire pre_b = pre && (addr10 || bank == 3'(b));

        // tRCD: no RD/WR to bank b for TRCD-1 cycles after its ACT
        a_trcd: assert property (@(posedge clk) disable iff (!rst_n) act_b |=> !col_b [*TRCD-1])
            else `uvm_error("SVA", $sformatf("tRCD violated on bank %0d", b))

        // tRP: no ACT to bank b for TRP-1 cycles after PRE to b or PREA
        a_trp: assert property (@(posedge clk) disable iff (!rst_n) pre_b |=> !act_b [*TRP-1])
            else `uvm_error("SVA", $sformatf("tRP violated on bank %0d", b))

        // tRAS: no PRE to bank b or PREA for TRAS-1 cycles after ACT to b
        a_tras: assert property (@(posedge clk) disable iff (!rst_n) act_b |=> !pre_b [*TRAS-1])
            else `uvm_error("SVA", $sformatf("tRAS violated on bank %0d", b))

        // gap exactly at the minimum: no vacuous pass, no slack
        c_trcd_min: cover property (@(posedge clk) disable iff (!rst_n) act_b ##TRCD col_b);
        c_trp_min: cover property (@(posedge clk) disable iff (!rst_n) pre_b ##TRP act_b);
        c_tras_min: cover property (@(posedge clk) disable iff (!rst_n) act_b ##TRAS pre_b);
    end

endmodule : mc_sva
