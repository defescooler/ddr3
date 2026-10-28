// datapath: write bursts out WL after WR, read bursts in RL after RD
module mc_datapath
    import mc_pkg::*;
#(
    parameter int WR_LAT = AL_CYCLES + CWL_CYCLES, // WL
    parameter int RD_LAT = AL_CYCLES + CL_CYCLES // RL
) (
    input logic clk,
    input logic rst_n,

    // host
    input logic app_req,
    input req_type_t app_cmd,
    input logic app_rdy, // from mc_ctrl
    input logic [BURST_LEN*DQ_W-1:0] app_wdata,
    input logic [BURST_LEN-1:0] app_wmask, // 1 = byte masked
    output logic [BURST_LEN*DQ_W-1:0] app_rdata,
    output logic app_rvalid,

    // command bus
    input ddr3_cmd_t cmd,

    // DFI data
    output logic phy_wrdata_en,
    output logic [2*DQ_W-1:0] phy_wrdata, // {fall, rise}
    output logic [1:0] phy_wrdata_mask, // DM per beat
    output logic phy_rddata_en,
    input logic [2*DQ_W-1:0] phy_rddata, // {fall, rise}
    input logic phy_rddata_valid
);

    // data widths
    localparam int BURST_W = BURST_LEN * DQ_W;
    localparam int PHY_W = 2 * DQ_W;
    localparam int BEAT_W = $clog2(BURST_CYCLES);

    // write queue, at most 3 bursts pending
    localparam int WQ_DEPTH = 4;
    localparam int WQ_W = $clog2(WQ_DEPTH);

    logic [BURST_W-1:0] wq_data [WQ_DEPTH];
    logic [BURST_LEN-1:0] wq_mask [WQ_DEPTH];
    logic [WQ_W-1:0] wq_wr;
    logic [WQ_W-1:0] wq_rd;

    wire wq_push = app_req && app_rdy && (app_cmd == REQ_WRITE);

    // write queue storage
    always_ff @(posedge clk) begin
        if (wq_push) begin
            wq_data[wq_wr] <= app_wdata;
            wq_mask[wq_wr] <= app_wmask;
        end
    end

    // WR/RD delay lines
    logic [WR_LAT-2:0] wr_pipe;
    logic [RD_LAT-2:0] rd_pipe;

    wire wr_start = wr_pipe[WR_LAT-2];
    wire rd_start = rd_pipe[RD_LAT-2];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_pipe <= '0;
            rd_pipe <= '0;
        end else begin
            wr_pipe <= {wr_pipe[WR_LAT-3:0], cmd == CMD_WR};
            rd_pipe <= {rd_pipe[RD_LAT-3:0], cmd == CMD_RD};
        end
    end

    // write burst sequencer
    logic [BURST_W-1:0] wr_data;
    logic [BURST_LEN-1:0] wr_mask;
    logic [BEAT_W-1:0] wr_left;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wq_wr <= '0;
            wq_rd <= '0;
            wr_data <= '0;
            wr_mask <= '0;
            wr_left <= '0;
            phy_wrdata_en <= 1'b0;
            phy_wrdata <= '0;
            phy_wrdata_mask <= '0;
        end else begin
            // defaults
            phy_wrdata_en <= 1'b0;
            if (wq_push) wq_wr <= wq_wr + WQ_W'(1);

            if (wr_start) begin
                // first beat pair from the queue head
                phy_wrdata_en <= 1'b1;
                phy_wrdata <= wq_data[wq_rd][PHY_W-1:0];
                phy_wrdata_mask <= wq_mask[wq_rd][1:0];
                wr_data <= wq_data[wq_rd] >> PHY_W;
                wr_mask <= wq_mask[wq_rd] >> 2;
                wr_left <= BEAT_W'(BURST_CYCLES - 1);
                wq_rd <= wq_rd + WQ_W'(1);
            end else if (wr_left != '0) begin
                // remaining beat pairs
                phy_wrdata_en <= 1'b1;
                phy_wrdata <= wr_data[PHY_W-1:0];
                phy_wrdata_mask <= wr_mask[1:0];
                wr_data <= wr_data >> PHY_W;
                wr_mask <= wr_mask >> 2;
                wr_left <= wr_left - BEAT_W'(1);
            end
        end
    end

    // read enable sequencer
    logic [BEAT_W-1:0] rd_left;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_left <= '0;
            phy_rddata_en <= 1'b0;
        end else begin
            // defaults
            phy_rddata_en <= 1'b0;

            if (rd_start) begin
                // open the read window
                phy_rddata_en <= 1'b1;
                rd_left <= BEAT_W'(BURST_CYCLES - 1);
            end else if (rd_left != '0) begin
                // hold it for the remaining beat pairs
                phy_rddata_en <= 1'b1;
                rd_left <= rd_left - BEAT_W'(1);
            end
        end
    end

    // read burst assembly
    logic [BURST_W-1:0] rd_data;
    logic [BEAT_W-1:0] rd_cnt;

    assign app_rdata = rd_data;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_data <= '0;
            rd_cnt <= '0;
            app_rvalid <= 1'b0;
        end else begin
            // defaults
            app_rvalid <= 1'b0;

            if (phy_rddata_valid) begin
                // shift in a beat pair, flag the burst after the last one
                rd_data <= {phy_rddata, rd_data[BURST_W-1:PHY_W]};
                rd_cnt <= rd_cnt + BEAT_W'(1);
                app_rvalid <= (rd_cnt == BEAT_W'(BURST_CYCLES - 1));
            end
        end
    end

endmodule : mc_datapath
