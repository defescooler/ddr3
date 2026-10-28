// power-up sequence: RESET#, CKE, MR2, MR3, MR1, MR0, ZQCL; owns the command bus until init_done
module mc_init
    import mc_pkg::*;
#(
    parameter int RESET_CYCLES = TRESET_CYCLES,
    parameter int CKE_LOW_CYCLES = TCKE_LOW_CYCLES
) (
    input logic clk,
    input logic rst_n,

    // DRAM
    output logic reset_n,
    output logic cke,
    output logic odt,
    output ddr3_cmd_t cmd,
    output logic [BANK_W-1:0] ba,
    output logic [ROW_W-1:0] addr,

    output logic init_done
);

    function automatic int max2(input int a, input int b);
        return (a > b) ? a : b;
    endfunction

    // counter widths
    localparam int CNT_MAX = max2(max2(RESET_CYCLES, CKE_LOW_CYCLES), max2(TXPR_CYCLES, TZQINIT_CYCLES));
    localparam int CNT_W = $clog2(CNT_MAX + 1);
    localparam int DLL_W = $clog2(TDLLK_CYCLES + 1);

    typedef enum logic [3:0] {
        S_RESET, // RESET# low
        S_CKE_LOW, // CKE low, clock stable
        S_TXPR, // CKE high, tXPR
        S_MR2, // MR2 issued, tMRD
        S_MR3, // MR3 issued, tMRD
        S_MR1, // MR1 issued, tMRD
        S_MR0, // MR0 issued, tMOD
        S_ZQCL, // ZQCL issued, tZQinit and tDLLK
        S_DONE
    } state_t;

    state_t state;
    logic [CNT_W-1:0] wait_cnt;
    logic [DLL_W-1:0] dll_cnt;

    wire timer_done = (wait_cnt == '0);
    wire dll_done = (dll_cnt == '0);

    // RTT off
    assign odt = 1'b0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_RESET;
            wait_cnt <= CNT_W'(RESET_CYCLES - 1);
            dll_cnt <= '0;
            reset_n <= 1'b0;
            cke <= 1'b0;
            cmd <= CMD_NOP;
            ba <= '0;
            addr <= '0;
            init_done <= 1'b0;
        end else begin
            // defaults
            cmd <= CMD_NOP;
            ba <= '0;
            addr <= '0;
            if (!timer_done) wait_cnt <= wait_cnt - CNT_W'(1);
            if (!dll_done) dll_cnt <= dll_cnt - DLL_W'(1);

            case (state)
                S_RESET: if (timer_done) begin
                    reset_n <= 1'b1;
                    wait_cnt <= CNT_W'(CKE_LOW_CYCLES - 1);
                    state <= S_CKE_LOW;
                end

                S_CKE_LOW: if (timer_done) begin
                    cke <= 1'b1;
                    wait_cnt <= CNT_W'(TXPR_CYCLES - 1);
                    state <= S_TXPR;
                end

                // CWL
                S_TXPR: if (timer_done) begin
                    cmd <= CMD_MRS;
                    ba <= BANK_W'(2);
                    addr <= MR2_INIT[ROW_W-1:0];
                    wait_cnt <= CNT_W'(TMRD_CYCLES - 1);
                    state <= S_MR2;
                end

                // MPR off
                S_MR2: if (timer_done) begin
                    cmd <= CMD_MRS;
                    ba <= BANK_W'(3);
                    addr <= MR3_INIT[ROW_W-1:0];
                    wait_cnt <= CNT_W'(TMRD_CYCLES - 1);
                    state <= S_MR3;
                end

                // DLL on
                S_MR3: if (timer_done) begin
                    cmd <= CMD_MRS;
                    ba <= BANK_W'(1);
                    addr <= MR1_INIT[ROW_W-1:0];
                    wait_cnt <= CNT_W'(TMRD_CYCLES - 1);
                    state <= S_MR1;
                end

                // CL, BL, DLL reset
                S_MR1: if (timer_done) begin
                    cmd <= CMD_MRS;
                    ba <= BANK_W'(0);
                    addr <= MR0_INIT[ROW_W-1:0];
                    wait_cnt <= CNT_W'(TMOD_CYCLES - 1);
                    dll_cnt <= DLL_W'(TDLLK_CYCLES - 1);
                    state <= S_MR0;
                end

                S_MR0: if (timer_done) begin
                    cmd <= CMD_ZQCL;
                    addr[10] <= 1'b1;
                    wait_cnt <= CNT_W'(TZQINIT_CYCLES - 1);
                    state <= S_ZQCL;
                end

                S_ZQCL: if (timer_done && dll_done) begin
                    init_done <= 1'b1;
                    state <= S_DONE;
                end

                S_DONE: ;

                default: ;
            endcase
        end
    end

endmodule : mc_init
