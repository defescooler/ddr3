// host interface, TB access through clocking blocks
interface host_if (input logic clk, input logic rst_n);
    import mc_pkg::*;

    logic app_req;
    req_type_t app_cmd;
    dram_addr_t app_addr;
    logic app_rdy;
    logic [BURST_LEN*DQ_W-1:0] app_wdata;
    logic [BURST_LEN-1:0] app_wmask;
    logic [BURST_LEN*DQ_W-1:0] app_rdata;
    logic app_rvalid;
    logic init_done;

    clocking drv_cb @(posedge clk);
        default input #1step output #100ps;
        output app_cmd, app_addr, app_wdata, app_wmask;
        inout app_req;
        input app_rdy;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step;
        input app_req, app_cmd, app_addr, app_rdy, app_wdata, app_wmask;
        input app_rdata, app_rvalid, init_done;
    endclocking

endinterface
