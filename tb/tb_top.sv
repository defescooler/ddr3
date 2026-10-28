// testbench top: DUT, interfaces, DRAM model, bound SVA
module tb_top;
    import uvm_pkg::*;
    import mc_pkg::*;
    import mc_tb_pkg::*;

    logic clk = 1'b0;
    logic rst_n = 1'b0;

    // tCK 1.5 ns
    always #0.75 clk = ~clk;

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
    end

    host_if hif (.clk, .rst_n);
    dfi_if dif (.clk, .rst_n);
    fsm_if fif (
        .clk,
        .ctrl_state(dut.u_ctrl.state),
        .ref_state(dut.u_refresh.state),
        .init_state(dut.u_init.state),
        .ref_urgent(dut.ref_urgent)
    );

    // power-up waits shortened in simulation
    mc_top #(
        .RESET_CYCLES(100),
        .CKE_LOW_CYCLES(250)
    ) dut (
        .clk,
        .rst_n,
        .app_req(hif.app_req),
        .app_cmd(hif.app_cmd),
        .app_addr(hif.app_addr),
        .app_rdy(hif.app_rdy),
        .app_wdata(hif.app_wdata),
        .app_wmask(hif.app_wmask),
        .app_rdata(hif.app_rdata),
        .app_rvalid(hif.app_rvalid),
        .init_done(hif.init_done),
        .dfi_cs_n(dif.cs_n),
        .dfi_ras_n(dif.ras_n),
        .dfi_cas_n(dif.cas_n),
        .dfi_we_n(dif.we_n),
        .dfi_bank(dif.bank),
        .dfi_address(dif.address),
        .dfi_cke(dif.cke),
        .dfi_reset_n(dif.reset_n),
        .dfi_odt(dif.odt),
        .dfi_wrdata_en(dif.wrdata_en),
        .dfi_wrdata(dif.wrdata),
        .dfi_wrdata_mask(dif.wrdata_mask),
        .dfi_rddata_en(dif.rddata_en),
        .dfi_rddata(dif.rddata),
        .dfi_rddata_valid(dif.rddata_valid)
    );

    dram_model u_dram (.dif(dif));

    bind mc_top mc_sva u_sva (
        .clk(clk),
        .rst_n(rst_n),
        .cs_n(dfi_cs_n),
        .ras_n(dfi_ras_n),
        .cas_n(dfi_cas_n),
        .we_n(dfi_we_n),
        .bank(dfi_bank),
        .addr10(dfi_address[10])
    );

    initial begin
        uvm_config_db#(virtual host_if)::set(null, "uvm_test_top*", "host_vif", hif);
        uvm_config_db#(virtual dfi_if)::set(null, "uvm_test_top*", "dfi_vif", dif);
        uvm_config_db#(virtual fsm_if)::set(null, "uvm_test_top*", "fsm_vif", fif);
        run_test("mc_smoke_test");
    end

endmodule : tb_top
