// refresh scheduler: tREFI timer, owed count, PREA then one REF per owed refresh
module mc_refresh
    import mc_pkg::*;
#(
    parameter int MAX_POSTPONE = 8
) (
    input logic clk,
    input logic rst_n,
    input logic init_done,

    // arbiter handshake
    output logic ref_req, // refresh owed
    output logic ref_urgent, // postpone limit reached
    input logic ref_gnt, // bus granted, banks can be precharged

    // command bus
    output ddr3_cmd_t cmd,
    output logic [BANK_W-1:0] ba,
    output logic [ROW_W-1:0] addr
);

    // counter widths
    localparam int REFI_W = $clog2(TREFI_CYCLES + 1);
    localparam int OWED_W = $clog2(MAX_POSTPONE + 2);
    localparam int CNT_W = $clog2(TRFC_CYCLES + 1);

    typedef enum logic [1:0] {
        S_IDLE, // nothing owed
        S_REQ, // bus requested, waiting for grant
        S_PREA, // PREA issued, tRP
        S_REF // REF issued, tRFC
    } state_t;

    state_t state;
    logic [REFI_W-1:0] refi_cnt;
    logic [OWED_W-1:0] owed;
    logic [CNT_W-1:0] wait_cnt;

    wire tick = (refi_cnt == '0);
    wire timer_done = (wait_cnt == '0);

    assign ref_req = (state != S_IDLE);
    assign ref_urgent = (owed >= OWED_W'(MAX_POSTPONE));

    // tREFI timer
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) refi_cnt <= REFI_W'(TREFI_CYCLES - 1);
        else if (!init_done || tick) refi_cnt <= REFI_W'(TREFI_CYCLES - 1);
        else refi_cnt <= refi_cnt - REFI_W'(1);
    end

    // owed: +1 per tick, -1 per REF on the bus
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) owed <= '0;
        else if (tick && cmd != CMD_REF) owed <= owed + OWED_W'(1);
        else if (!tick && cmd == CMD_REF) owed <= owed - OWED_W'(1);
    end

    // sequencer
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            wait_cnt <= '0;
            cmd <= CMD_NOP;
            ba <= '0;
            addr <= '0;
        end else begin
            // defaults
            cmd <= CMD_NOP;
            ba <= '0;
            addr <= '0;
            if (!timer_done) wait_cnt <= wait_cnt - CNT_W'(1);

            case (state)
                // request the bus once a refresh is owed
                S_IDLE: if (owed != '0 && !ref_gnt) state <= S_REQ;

                // close all banks once granted
                S_REQ: if (ref_gnt) begin
                    cmd <= CMD_PRE;
                    addr[10] <= 1'b1;
                    wait_cnt <= CNT_W'(TRP_CYCLES - 1);
                    state <= S_PREA;
                end

                // first REF
                S_PREA: if (timer_done) begin
                    cmd <= CMD_REF;
                    wait_cnt <= CNT_W'(TRFC_CYCLES - 1);
                    state <= S_REF;
                end

                // next REF while owed, then release the bus
                S_REF: if (timer_done) begin
                    if (owed != '0) begin
                        cmd <= CMD_REF;
                        wait_cnt <= CNT_W'(TRFC_CYCLES - 1);
                    end else begin
                        state <= S_IDLE;
                    end
                end

                default: ;
            endcase
        end
    end

endmodule : mc_refresh
