// one decoded DFI command, NOP and DES dropped
class dfi_item extends uvm_sequence_item;
    `uvm_object_utils(dfi_item)

    bit [3:0] kind; // `K_* code
    bit [BANK_W-1:0] bank;
    bit [ROW_W-1:0] addr;
    longint unsigned cyc;

    function new(string name = "dfi_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("kind %0d b%0d a%h @%0d", kind, bank, addr, cyc);
    endfunction
endclass

// DFI monitor: decodes the command pins
class dfi_monitor extends uvm_monitor;
    `uvm_component_utils(dfi_monitor)

    virtual dfi_if vif;
    uvm_analysis_port #(dfi_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual dfi_if)::get(this, "", "dfi_vif", vif))
            `uvm_fatal("NOVIF", "dfi_vif not set")
    endfunction

    task run_phase(uvm_phase phase);
        dfi_item t;
        longint unsigned cyc;
        bit [3:0] kind;
        forever begin
            @(vif.mon_cb);
            cyc++;
            if (!(vif.mon_cb.reset_n && vif.mon_cb.cke && !vif.mon_cb.cs_n)) continue;
            // {RAS_n, CAS_n, WE_n}
            case ({vif.mon_cb.ras_n, vif.mon_cb.cas_n, vif.mon_cb.we_n})
                3'b000: kind = `K_MRS;
                3'b001: kind = `K_REF;
                3'b010: kind = vif.mon_cb.address[10] ? `K_PREA : `K_PRE;
                3'b011: kind = `K_ACT;
                3'b100: kind = `K_WR;
                3'b101: kind = `K_RD;
                3'b110: kind = `K_ZQCL;
                default: continue;
            endcase
            t = dfi_item::type_id::create("cmd");
            t.kind = kind;
            t.bank = vif.mon_cb.bank;
            t.addr = vif.mon_cb.address;
            t.cyc = cyc;
            ap.write(t);
        end
    endtask
endclass
