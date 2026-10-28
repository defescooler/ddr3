// base: one request at a fixed address, random data and mask
class mc_base_seq extends uvm_sequence #(mc_item);
    `uvm_object_utils(mc_base_seq)

    function new(string name = "mc_base_seq");
        super.new(name);
    endfunction

    task send(bit wr, int bank, int row, int blk, int unsigned idle = 0);
        mc_item t = mc_item::type_id::create("t");
        start_item(t);
        if (!t.randomize()) `uvm_fatal("RAND", "mc_item randomize failed")
        t.wr = wr;
        t.bank = bank;
        t.row = row;
        t.blk = blk;
        t.idle = idle;
        finish_item(t);
    endtask
endclass

// one write and one read per bank
class mc_smoke_seq extends mc_base_seq;
    `uvm_object_utils(mc_smoke_seq)

    function new(string name = "mc_smoke_seq");
        super.new(name);
    endfunction

    task body();
        for (int b = 0; b < NUM_BANKS; b++) begin
            send(1, b, 3, b);
            send(0, b, 3, b);
        end
    endtask
endclass

// per bank: empty, hit, miss, back to back; reaches the exact tRCD, tRP, tRAS gaps and every turnaround
class mc_page_seq extends mc_base_seq;
    `uvm_object_utils(mc_page_seq)

    function new(string name = "mc_page_seq");
        super.new(name);
    endfunction

    task body();
        for (int b = 0; b < NUM_BANKS; b++) begin
            send(1, b, 1, 0); // empty: ACT, WR exactly tRCD later
            send(0, b, 1, 1); // hit, WR -> RD
            send(0, b, 1, 2); // hit, RD -> RD
            send(1, b, 1, 3); // hit, RD -> WR
            send(1, b, 1, 4); // hit, WR -> WR
            send(0, b, 2, 0); // miss after WR: PRE held by tWR, ACT exactly tRP later
            send(0, b, 3, 0); // miss right after ACT + RD: PRE held by tRAS
            send(0, b, 1, 0); // miss, reads back the first write
        end
    endtask
endclass

// random traffic over the mc_item working set (c_pool)
class mc_rand_seq extends mc_base_seq;
    `uvm_object_utils(mc_rand_seq)

    int unsigned n = 2000;
    bit stream; // idle = 0 until stop
    bit stop;

    function new(string name = "mc_rand_seq");
        super.new(name);
    endfunction

    task body();
        mc_item t;
        int unsigned i;
        while (stream ? !stop : i < n) begin
            t = mc_item::type_id::create("t");
            start_item(t);
            if (!t.randomize()) `uvm_fatal("RAND", "mc_item randomize failed")
            if (stream) t.idle = 0;
            finish_item(t);
            i++;
        end
    endtask
endclass
