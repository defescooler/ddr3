// arbiter: open-page policy, one request at a time
// priority: urgent refresh, host request, opportunistic refresh
module mc_ctrl
    import mc_pkg::*;
(
    input logic clk,
    input logic rst_n,
    input logic init_done,

    // host
    input logic app_req,
    input req_type_t app_cmd,
    input dram_addr_t app_addr,
    output logic app_rdy,

    // mc_refresh
    input logic ref_req, // refresh owed
    input logic ref_urgent, // postpone limit reached
    output logic ref_gnt, // bus granted

    // mc_timing
    input logic [NUM_BANKS-1:0] act_ready, // tRP met
    input logic [NUM_BANKS-1:0] col_ready, // tRCD met
    input logic [NUM_BANKS-1:0] pre_ready, // tRAS, tRTP, tWR met
    input logic rd_ready, // tCCD, WR to RD met
    input logic wr_ready, // tCCD, RD to WR met

    // command bus
    output ddr3_cmd_t cmd,
    output logic [BANK_W-1:0] ba,
    output logic [ROW_W-1:0] addr // row on ACT, column on RD/WR
);

    typedef enum logic [2:0] {
        S_IDLE, // arbitrate refresh and host requests
        S_PRE, // page miss, close the open row
        S_ACT, // open the requested row
        S_COL, // issue RD or WR
        S_REF // bus granted to mc_refresh
    } state_t;

    state_t state;

    // accepted request
    req_type_t req_cmd;
    dram_addr_t req_addr;

    // open row table
    logic [NUM_BANKS-1:0] bank_open;
    logic [ROW_W-1:0] open_row [NUM_BANKS];

    // page outcome of the incoming request, miss otherwise
    wire page_hit = bank_open[app_addr.bank] && (open_row[app_addr.bank] == app_addr.row);
    wire page_empty = !bank_open[app_addr.bank];

    // RD/WR allowed: tRCD in the bank, turnaround on the data bus
    wire col_ok = col_ready[req_addr.bank] && ((req_cmd == REQ_WRITE) ? wr_ready : rd_ready);

    // accept only when idle and no urgent refresh is pending
    assign app_rdy = init_done && (state == S_IDLE) && !ref_urgent;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            req_cmd <= REQ_READ;
            req_addr <= '0;
            bank_open <= '0;
            for (int b = 0; b < NUM_BANKS; b++) open_row[b] <= '0;
            ref_gnt <= 1'b0;
            cmd <= CMD_NOP;
            ba <= '0;
            addr <= '0;
        end else begin
            // defaults
            cmd <= CMD_NOP;
            ba <= '0;
            addr <= '0;

            case (state)
                // urgent refresh, then host request, then opportunistic refresh
                S_IDLE: begin
                    if (ref_urgent) begin
                        state <= S_REF;
                    end else if (app_req && app_rdy) begin
                        req_cmd <= app_cmd;
                        req_addr <= app_addr;
                        if (page_hit) state <= S_COL;
                        else if (page_empty) state <= S_ACT;
                        else state <= S_PRE;
                    end else if (ref_req) begin
                        state <= S_REF;
                    end
                end

                // page miss: close the open row
                S_PRE: if (pre_ready[req_addr.bank]) begin
                    cmd <= CMD_PRE;
                    ba <= req_addr.bank;
                    bank_open[req_addr.bank] <= 1'b0;
                    state <= S_ACT;
                end

                // page empty: open the requested row
                S_ACT: if (act_ready[req_addr.bank]) begin
                    cmd <= CMD_ACT;
                    ba <= req_addr.bank;
                    addr <= req_addr.row;
                    bank_open[req_addr.bank] <= 1'b1;
                    open_row[req_addr.bank] <= req_addr.row;
                    state <= S_COL;
                end

                // page hit: RD or WR, A10 = 0 (no auto precharge)
                S_COL: if (col_ok) begin
                    cmd <= (req_cmd == REQ_WRITE) ? CMD_WR : CMD_RD;
                    ba <= req_addr.bank;
                    addr <= ROW_W'(req_addr.col);
                    state <= S_IDLE;
                end

                // grant once every bank can be precharged, hold until mc_refresh releases the bus
                S_REF: begin
                    if (!ref_gnt) begin
                        if (ref_req && &pre_ready) ref_gnt <= 1'b1;
                    end else if (!ref_req) begin
                        ref_gnt <= 1'b0;
                        bank_open <= '0;
                        state <= S_IDLE;
                    end
                end

                default: ;
            endcase
        end
    end

endmodule : mc_ctrl
