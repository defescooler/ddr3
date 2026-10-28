// white-box FSM taps, coverage only
interface fsm_if (
    input logic clk,
    input logic [2:0] ctrl_state, // mc_ctrl state_t
    input logic [1:0] ref_state, // mc_refresh state_t
    input logic [3:0] init_state, // mc_init state_t
    input logic ref_urgent
);

    clocking mon_cb @(posedge clk);
        default input #1step;
        input ctrl_state, ref_state, init_state, ref_urgent;
    endclocking

endinterface
