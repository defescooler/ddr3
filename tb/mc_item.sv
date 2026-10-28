// one host request: a BL8 read or write
class mc_item extends uvm_sequence_item;
    `uvm_object_utils(mc_item)

    rand bit wr;
    rand bit [BANK_W-1:0] bank;
    rand bit [ROW_W-1:0] row;
    rand bit [COL_W-4:0] blk; // col[9:3], col[2:0] = 0
    rand bit [BURST_LEN*DQ_W-1:0] wdata;
    rand bit [BURST_LEN-1:0] wmask; // 1 = byte masked
    rand int unsigned idle; // idle cycles before the request
    bit [BURST_LEN*DQ_W-1:0] rdata; // read data, set by the monitor

    constraint c_mask { wmask dist { 0 := 80, [1:255] :/ 20 }; }
    constraint c_idle { idle dist { 0 := 70, [1:10] :/ 25, [11:40] :/ 5 }; }

    // small working set for hits, misses and read-after-write, plus address extremes
    // class constraint: Verilator ignores dist inside randomize() with
    constraint c_pool {
        row dist { [0:3] :/ 90, 16383 := 5, [4:16382] :/ 5 };
        blk dist { [0:3] :/ 80, 127 := 10, [4:126] :/ 10 };
    }

    function new(string name = "mc_item");
        super.new(name);
    endfunction

    function dram_addr_t addr();
        return '{row: row, bank: bank, col: {blk, 3'b000}};
    endfunction

    // ref_mem key, {bank, row, col[9:3]}
    function int unsigned key();
        return {bank, row, blk};
    endfunction

    function string convert2string();
        return $sformatf("%s b%0d r%0d c%0d", wr ? "WR" : "RD", bank, row, {blk, 3'b000});
    endfunction
endclass
