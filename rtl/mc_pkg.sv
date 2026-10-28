// DDR3-1333 (-15E, x8) geometry, commands, timing and mode registers
package mc_pkg;

    // clock
    localparam int TCK_PS = 1500;

    function automatic int div_ceil(input int val, input int div);
        return (val + div - 1) / div;
    endfunction

    // geometry
    localparam int BANK_W = 3;
    localparam int NUM_BANKS = 1 << BANK_W;
    localparam int ROW_W = 14;
    localparam int COL_W = 10;
    localparam int DQ_W = 8;
    localparam int BURST_LEN = 8;
    localparam int BURST_CYCLES = BURST_LEN / 2;

    // host request
    typedef enum logic [1:0] {
        REQ_READ = 2'b00,
        REQ_WRITE = 2'b01
    } req_type_t;

    // host address
    typedef struct packed {
        logic [ROW_W-1:0] row;
        logic [BANK_W-1:0] bank;
        logic [COL_W-1:0] col;
    } dram_addr_t;

    // {CS_n, RAS_n, CAS_n, WE_n}
    typedef enum logic [3:0] {
        CMD_MRS = 4'b0000, // mode register set
        CMD_REF = 4'b0001, // refresh
        CMD_PRE = 4'b0010, // precharge, A10 = all banks
        CMD_ACT = 4'b0011, // activate
        CMD_WR = 4'b0100, // write
        CMD_RD = 4'b0101, // read
        CMD_ZQCL = 4'b0110, // ZQ calibration long
        CMD_NOP = 4'b0111, // no operation
        CMD_DES = 4'b1111 // deselect
    } ddr3_cmd_t;

    // datasheet timing, ps
    localparam int TRCD_PS = 13500;
    localparam int TRP_PS = 13500;
    localparam int TRAS_PS = 36000;
    localparam int TWR_PS = 15000;
    localparam int TRTP_PS = 7500;
    localparam int TWTR_PS = 7500;
    localparam int TRFC_PS = 110000;
    localparam int TREFI_PS = 7800000;
    localparam int TMOD_PS = 15000;

    // timing, clk
    localparam int TRCD_CYCLES = div_ceil(TRCD_PS, TCK_PS);
    localparam int TRP_CYCLES = div_ceil(TRP_PS, TCK_PS);
    localparam int TRAS_CYCLES = div_ceil(TRAS_PS, TCK_PS);
    localparam int TWR_CYCLES = div_ceil(TWR_PS, TCK_PS);
    localparam int TRFC_CYCLES = div_ceil(TRFC_PS, TCK_PS);
    localparam int TREFI_CYCLES = TREFI_PS / TCK_PS;
    localparam int TCCD_CYCLES = 4;
    localparam int TRTP_CYCLES = (4 > div_ceil(TRTP_PS, TCK_PS)) ? 4 : div_ceil(TRTP_PS, TCK_PS);
    localparam int TWTR_CYCLES = (4 > div_ceil(TWTR_PS, TCK_PS)) ? 4 : div_ceil(TWTR_PS, TCK_PS);
    localparam int TMOD_CYCLES = (12 > div_ceil(TMOD_PS, TCK_PS)) ? 12 : div_ceil(TMOD_PS, TCK_PS);
    localparam int TMRD_CYCLES = 4;
    localparam int TDLLK_CYCLES = 512;
    localparam int TZQINIT_CYCLES = 512;
    localparam int TXPR_CYCLES = (5 > div_ceil(TRFC_PS + 10000, TCK_PS)) ? 5 : div_ceil(TRFC_PS + 10000, TCK_PS);

    // power-up waits
    localparam int TRESET_US = 200;
    localparam int TCKE_LOW_US = 500;
    localparam int TRESET_CYCLES = div_ceil(TRESET_US * 1_000_000, TCK_PS);
    localparam int TCKE_LOW_CYCLES = div_ceil(TCKE_LOW_US * 1_000_000, TCK_PS);

    // latencies, must match MR0 and MR2
    localparam int CL_CYCLES = 9;
    localparam int CWL_CYCLES = 7;
    localparam int AL_CYCLES = 0;

    // command to command
    localparam int TWR_TOTAL_CYCLES = AL_CYCLES + CWL_CYCLES + BURST_CYCLES + TWR_CYCLES; // WR to PRE
    localparam int TRTP_TOTAL_CYCLES = AL_CYCLES + TRTP_CYCLES; // RD to PRE
    localparam int TRD2WR_CYCLES = CL_CYCLES + TCCD_CYCLES + 2 - CWL_CYCLES; // RD to WR
    localparam int TWR2RD_CYCLES = AL_CYCLES + CWL_CYCLES + BURST_CYCLES + TWTR_CYCLES; // WR to RD

    // mode registers
    localparam logic [15:0] MR0_INIT = 16'b0001_1011_0101_0000; // BL8, CL 9, DLL reset, WR 10
    localparam logic [15:0] MR1_INIT = 16'b0000_0000_0000_0010; // DLL on, RZQ/7, AL 0
    localparam logic [15:0] MR2_INIT = 16'b0000_0000_0001_0000; // CWL 7
    localparam logic [15:0] MR3_INIT = 16'b0000_0000_0000_0000; // normal reads

endpackage : mc_pkg
