// DFI DRAM model: stores write bursts, returns read bursts, CL/CWL from MR0/MR2
// flags bank state, column alignment and data enables off WL/RL
module dram_model
    import mc_pkg::*;
#(
    parameter int PHY_RDLAT = 2 // rddata_en to rddata_valid
) (
    dfi_if dif
);
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    typedef struct {
        int unsigned key;
        longint unsigned due;
        logic [63:0] data;
    } burst_t;

    // memory and bank state
    logic [63:0] mem [int unsigned];
    logic [NUM_BANKS-1:0] bank_open;
    logic [ROW_W-1:0] open_row [NUM_BANKS];
    int unsigned cl;
    int unsigned cwl;
    longint unsigned cyc;

    // pending bursts, oldest first
    burst_t wr_q [$];
    burst_t en_q [$];
    burst_t rd_q [$];

    // bursts in progress
    burst_t wr_cur;
    burst_t rd_cur;
    int wr_left;
    int en_left;
    int rd_left;

    wire [3:0] cmd = {dif.cs_n, dif.ras_n, dif.cas_n, dif.we_n};
    wire live = dif.reset_n && dif.cke;

    function automatic int unsigned key(logic [BANK_W-1:0] b, logic [ROW_W-1:0] r, logic [ROW_W-1:0] a);
        return {b, r, a[COL_W-1:3]};
    endfunction

    function automatic logic [63:0] load(int unsigned k);
        if (mem.exists(k)) return mem[k];
        return '0;
    endfunction

    // MR0[6:4] CAS latency
    function automatic int unsigned mr0_cl(logic [ROW_W-1:0] a);
        return (a[6:4] == 3'd0) ? 0 : 4 + a[6:4];
    endfunction

    always @(posedge dif.clk) begin
        if (!dif.rst_n) begin
            cyc = 0;
            cl = 0;
            cwl = 0;
            bank_open = '0;
            wr_q.delete();
            en_q.delete();
            rd_q.delete();
            wr_left = 0;
            en_left = 0;
            rd_left = 0;
            dif.rddata_valid <= 1'b0;
            dif.rddata <= '0;
        end else begin
            cyc++;

            // command of the cycle that just ended
            if (live && !dif.cs_n) begin
                case (cmd)
                    CMD_MRS: begin
                        if (dif.bank == 0) cl = mr0_cl(dif.address);
                        if (dif.bank == 2) cwl = 5 + dif.address[5:3];
                    end
                    CMD_ACT: begin
                        if (bank_open[dif.bank]) `uvm_error("DRAM", $sformatf("ACT to open bank %0d", dif.bank))
                        bank_open[dif.bank] = 1'b1;
                        open_row[dif.bank] = dif.address;
                    end
                    CMD_PRE: begin
                        if (dif.address[10]) bank_open = '0;
                        else bank_open[dif.bank] = 1'b0;
                    end
                    CMD_WR, CMD_RD: begin
                        burst_t b;
                        if (!bank_open[dif.bank]) `uvm_error("DRAM", $sformatf("%s to closed bank %0d", cmd == CMD_WR ? "WR" : "RD", dif.bank))
                        if (dif.address[2:0] != 0) `uvm_error("DRAM", "column not BL8 aligned")
                        b.key = key(dif.bank, open_row[dif.bank], dif.address);
                        if (cmd == CMD_WR) begin
                            b.due = cyc + cwl;
                            wr_q.push_back(b);
                        end else begin
                            b.due = cyc + cl;
                            b.data = load(b.key);
                            en_q.push_back(b);
                            b.due = cyc + cl + PHY_RDLAT;
                            rd_q.push_back(b);
                        end
                    end
                    default: ;
                endcase
            end

            // write data: 4 beat pairs starting WL after each WR
            if (wr_left == 0 && wr_q.size() != 0 && wr_q[0].due == cyc) begin
                wr_cur = wr_q.pop_front();
                wr_cur.data = load(wr_cur.key);
                wr_left = 4;
            end
            if (wr_left != 0) begin
                if (!dif.wrdata_en) begin
                    `uvm_error("DRAM", "dfi_wrdata_en low at WL after WR")
                end else begin
                    for (int i = 0; i < 2; i++)
                        if (!dif.wrdata_mask[i]) wr_cur.data[(2*(4-wr_left)+i)*8 +: 8] = dif.wrdata[i*8 +: 8];
                end
                wr_left--;
                if (wr_left == 0) mem[wr_cur.key] = wr_cur.data;
            end else if (dif.wrdata_en) begin
                `uvm_error("DRAM", "dfi_wrdata_en high with no WR at WL before it")
            end

            // read enable: 4 cycles starting RL after each RD
            if (en_left == 0 && en_q.size() != 0 && en_q[0].due == cyc) begin
                void'(en_q.pop_front());
                en_left = 4;
            end
            if (en_left != 0) begin
                if (!dif.rddata_en) `uvm_error("DRAM", "dfi_rddata_en low at RL after RD")
                en_left--;
            end else if (dif.rddata_en) begin
                `uvm_error("DRAM", "dfi_rddata_en high with no RD at RL before it")
            end

            // read data: 4 beat pairs, PHY_RDLAT after the read window
            dif.rddata_valid <= 1'b0;
            if (rd_left == 0 && rd_q.size() != 0 && rd_q[0].due == cyc) begin
                rd_cur = rd_q.pop_front();
                rd_left = 4;
            end
            if (rd_left != 0) begin
                dif.rddata_valid <= 1'b1;
                dif.rddata <= rd_cur.data[(4-rd_left)*16 +: 16];
                rd_left--;
            end
        end
    end

endmodule : dram_model
