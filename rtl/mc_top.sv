// controller top: init, refresh and arbiter share one command bus, driven to the DFI
module mc_top
    import mc_pkg::*;
#(
    parameter int RESET_CYCLES = TRESET_CYCLES, // shortened in simulation
    parameter int CKE_LOW_CYCLES = TCKE_LOW_CYCLES
) (
    input logic clk,
    input logic rst_n,

    // host
    input logic app_req,
    input req_type_t app_cmd,
    input dram_addr_t app_addr, // col[2:0] = 0
    output logic app_rdy, // request accepted on app_req && app_rdy
    input logic [BURST_LEN*DQ_W-1:0] app_wdata, // sampled with the request
    input logic [BURST_LEN-1:0] app_wmask, // 1 = byte masked
    output logic [BURST_LEN*DQ_W-1:0] app_rdata, // valid with app_rvalid
    output logic app_rvalid,
    output logic init_done,

    // DFI control
    output logic dfi_cs_n,
    output logic dfi_ras_n,
    output logic dfi_cas_n,
    output logic dfi_we_n,
    output logic [BANK_W-1:0] dfi_bank,
    output logic [ROW_W-1:0] dfi_address,
    output logic dfi_cke,
    output logic dfi_reset_n,
    output logic dfi_odt,

    // DFI write data
    output logic dfi_wrdata_en,
    output logic [2*DQ_W-1:0] dfi_wrdata, // {fall, rise}
    output logic [1:0] dfi_wrdata_mask,

    // DFI read data
    output logic dfi_rddata_en,
    input logic [2*DQ_W-1:0] dfi_rddata, // {fall, rise}
    input logic dfi_rddata_valid
);

    // init
    ddr3_cmd_t init_cmd;
    logic [BANK_W-1:0] init_ba;
    logic [ROW_W-1:0] init_addr;

    // refresh
    logic ref_req;
    logic ref_urgent;
    logic ref_gnt;
    ddr3_cmd_t ref_cmd;
    logic [BANK_W-1:0] ref_ba;
    logic [ROW_W-1:0] ref_addr;

    // arbiter
    ddr3_cmd_t ctrl_cmd;
    logic [BANK_W-1:0] ctrl_ba;
    logic [ROW_W-1:0] ctrl_addr;

    // timing
    logic [NUM_BANKS-1:0] act_ready;
    logic [NUM_BANKS-1:0] col_ready;
    logic [NUM_BANKS-1:0] pre_ready;
    logic rd_ready;
    logic wr_ready;

    // command bus
    ddr3_cmd_t cmd;
    logic [BANK_W-1:0] ba;
    logic [ROW_W-1:0] addr;

    // owner: init until init_done, then refresh while granted, else arbiter; idle sources drive NOP
    // combinational: mc_timing and mc_datapath count from the cycle the command is on the bus
    assign cmd = !init_done ? init_cmd : ref_gnt ? ref_cmd : ctrl_cmd;
    assign ba = !init_done ? init_ba : ref_gnt ? ref_ba : ctrl_ba;
    assign addr = !init_done ? init_addr : ref_gnt ? ref_addr : ctrl_addr;

    assign {dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n} = cmd;
    assign dfi_bank = ba;
    assign dfi_address = addr;

    mc_init #(
        .RESET_CYCLES(RESET_CYCLES),
        .CKE_LOW_CYCLES(CKE_LOW_CYCLES)
    ) u_init (
        .clk(clk),
        .rst_n(rst_n),
        .reset_n(dfi_reset_n),
        .cke(dfi_cke),
        .odt(dfi_odt),
        .cmd(init_cmd),
        .ba(init_ba),
        .addr(init_addr),
        .init_done(init_done)
    );

    mc_refresh u_refresh (
        .clk(clk),
        .rst_n(rst_n),
        .init_done(init_done),
        .ref_req(ref_req),
        .ref_urgent(ref_urgent),
        .ref_gnt(ref_gnt),
        .cmd(ref_cmd),
        .ba(ref_ba),
        .addr(ref_addr)
    );

    mc_ctrl u_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .init_done(init_done),
        .app_req(app_req),
        .app_cmd(app_cmd),
        .app_addr(app_addr),
        .app_rdy(app_rdy),
        .ref_req(ref_req),
        .ref_urgent(ref_urgent),
        .ref_gnt(ref_gnt),
        .act_ready(act_ready),
        .col_ready(col_ready),
        .pre_ready(pre_ready),
        .rd_ready(rd_ready),
        .wr_ready(wr_ready),
        .cmd(ctrl_cmd),
        .ba(ctrl_ba),
        .addr(ctrl_addr)
    );

    // watches the final bus, so a refresh PREA reloads tRP in every bank
    mc_timing u_timing (
        .clk(clk),
        .rst_n(rst_n),
        .cmd(cmd),
        .ba(ba),
        .addr10(addr[10]),
        .act_ready(act_ready),
        .col_ready(col_ready),
        .pre_ready(pre_ready),
        .rd_ready(rd_ready),
        .wr_ready(wr_ready)
    );

    mc_datapath u_datapath (
        .clk(clk),
        .rst_n(rst_n),
        .app_req(app_req),
        .app_cmd(app_cmd),
        .app_rdy(app_rdy),
        .app_wdata(app_wdata),
        .app_wmask(app_wmask),
        .app_rdata(app_rdata),
        .app_rvalid(app_rvalid),
        .cmd(cmd),
        .phy_wrdata_en(dfi_wrdata_en),
        .phy_wrdata(dfi_wrdata),
        .phy_wrdata_mask(dfi_wrdata_mask),
        .phy_rddata_en(dfi_rddata_en),
        .phy_rddata(dfi_rddata),
        .phy_rddata_valid(dfi_rddata_valid)
    );

endmodule : mc_top
