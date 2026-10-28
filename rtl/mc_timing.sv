// timing counters: tRCD, tRP, tRAS, tRTP, tWR per bank; tCCD and RD/WR turnaround per device
module mc_timing
    import mc_pkg::*;
(
    input logic clk,
    input logic rst_n,

    // command bus
    input ddr3_cmd_t cmd,
    input logic [BANK_W-1:0] ba,
    input logic addr10, // 1 = PREA

    output logic [NUM_BANKS-1:0] act_ready, // tRP met
    output logic [NUM_BANKS-1:0] col_ready, // tRCD met
    output logic [NUM_BANKS-1:0] pre_ready, // tRAS, tRTP, tWR met
    output logic rd_ready, // tCCD, WR to RD met
    output logic wr_ready // tCCD, RD to WR met
);

    // counter widths
    localparam int RCD_W = $clog2(TRCD_CYCLES + 1);
    localparam int RP_W = $clog2(TRP_CYCLES + 1);
    localparam int RAS_W = $clog2(TRAS_CYCLES + 1);
    localparam int RTP_W = $clog2(TRTP_TOTAL_CYCLES + 1);
    localparam int WR_W = $clog2(TWR_TOTAL_CYCLES + 1);

    logic [RCD_W-1:0] rcd_cnt [NUM_BANKS];
    logic [RP_W-1:0] rp_cnt [NUM_BANKS];
    logic [RAS_W-1:0] ras_cnt [NUM_BANKS];
    logic [RTP_W-1:0] rtp_cnt [NUM_BANKS];
    logic [WR_W-1:0] wr_cnt [NUM_BANKS];

    // per-bank command decode
    logic [NUM_BANKS-1:0] act_hit;
    logic [NUM_BANKS-1:0] rd_hit;
    logic [NUM_BANKS-1:0] wr_hit;
    logic [NUM_BANKS-1:0] pre_hit;

    // decode and ready flags, masked while the command is still on the bus
    always_comb begin
        for (int b = 0; b < NUM_BANKS; b++) begin
            act_hit[b] = (cmd == CMD_ACT) && (ba == BANK_W'(b));
            rd_hit[b] = (cmd == CMD_RD) && (ba == BANK_W'(b));
            wr_hit[b] = (cmd == CMD_WR) && (ba == BANK_W'(b));
            pre_hit[b] = (cmd == CMD_PRE) && (addr10 || ba == BANK_W'(b));

            act_ready[b] = (rp_cnt[b] == '0) && !pre_hit[b];
            col_ready[b] = (rcd_cnt[b] == '0) && !act_hit[b];
            pre_ready[b] = (ras_cnt[b] == '0) && (rtp_cnt[b] == '0) && (wr_cnt[b] == '0)
                           && !(act_hit[b] || rd_hit[b] || wr_hit[b]);
        end
    end

    // counters load N-2: one cycle already passed while the command was on the bus
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int b = 0; b < NUM_BANKS; b++) begin
                rcd_cnt[b] <= '0;
                rp_cnt[b] <= '0;
                ras_cnt[b] <= '0;
                rtp_cnt[b] <= '0;
                wr_cnt[b] <= '0;
            end
        end else begin
            for (int b = 0; b < NUM_BANKS; b++) begin
                // tRCD timer
                if (act_hit[b]) begin
                    rcd_cnt[b] <= RCD_W'(TRCD_CYCLES - 2);
                end else if (rcd_cnt[b] != '0) begin
                    rcd_cnt[b] <= rcd_cnt[b] - RCD_W'(1);
                end

                // tRP timer
                if (pre_hit[b]) begin
                    rp_cnt[b] <= RP_W'(TRP_CYCLES - 2);
                end else if (rp_cnt[b] != '0) begin
                    rp_cnt[b] <= rp_cnt[b] - RP_W'(1);
                end

                // tRAS timer
                if (act_hit[b]) begin
                    ras_cnt[b] <= RAS_W'(TRAS_CYCLES - 2);
                end else if (ras_cnt[b] != '0) begin
                    ras_cnt[b] <= ras_cnt[b] - RAS_W'(1);
                end

                // AL + tRTP timer
                if (rd_hit[b]) begin
                    rtp_cnt[b] <= RTP_W'(TRTP_TOTAL_CYCLES - 2);
                end else if (rtp_cnt[b] != '0) begin
                    rtp_cnt[b] <= rtp_cnt[b] - RTP_W'(1);
                end

                // WL + BL/2 + tWR timer
                if (wr_hit[b]) begin
                    wr_cnt[b] <= WR_W'(TWR_TOTAL_CYCLES - 2);
                end else if (wr_cnt[b] != '0) begin
                    wr_cnt[b] <= wr_cnt[b] - WR_W'(1);
                end
            end
        end
    end

    // device column timers
    localparam int TURN_W = $clog2(TWR2RD_CYCLES + 1);

    logic [TURN_W-1:0] rd_wait;
    logic [TURN_W-1:0] wr_wait;

    wire col_hit = (cmd == CMD_RD) || (cmd == CMD_WR);

    assign rd_ready = (rd_wait == '0) && !col_hit;
    assign wr_ready = (wr_wait == '0) && !col_hit;

    // RD/WR turnaround, loaded N-2 like the bank timers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_wait <= '0;
            wr_wait <= '0;
        end else if (cmd == CMD_RD) begin
            rd_wait <= TURN_W'(TCCD_CYCLES - 2);
            wr_wait <= TURN_W'(TRD2WR_CYCLES - 2);
        end else if (cmd == CMD_WR) begin
            rd_wait <= TURN_W'(TWR2RD_CYCLES - 2);
            wr_wait <= TURN_W'(TCCD_CYCLES - 2);
        end else begin
            if (rd_wait != '0) rd_wait <= rd_wait - TURN_W'(1);
            if (wr_wait != '0) wr_wait <= wr_wait - TURN_W'(1);
        end
    end

endmodule : mc_timing
