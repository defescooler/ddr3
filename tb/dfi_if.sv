// DFI interface between mc_top and the DRAM model
interface dfi_if (input logic clk, input logic rst_n);
    import mc_pkg::*;

    // control
    logic cs_n;
    logic ras_n;
    logic cas_n;
    logic we_n;
    logic [BANK_W-1:0] bank;
    logic [ROW_W-1:0] address;
    logic cke;
    logic reset_n;
    logic odt;

    // write data
    logic wrdata_en;
    logic [2*DQ_W-1:0] wrdata;
    logic [1:0] wrdata_mask;

    // read data
    logic rddata_en;
    logic [2*DQ_W-1:0] rddata;
    logic rddata_valid;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input cs_n, ras_n, cas_n, we_n, bank, address, cke, reset_n;
    endclocking

endinterface
