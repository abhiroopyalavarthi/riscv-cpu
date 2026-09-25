// 5-stage pipelined RV32I core: IF -> ID -> EX -> MEM -> WB
//
// Hazards
//   data:      forward EX/MEM and MEM/WB results into EX. WB -> ID goes
//              through the register file's write-through bypass.
//   load-use:  a load followed by an instruction that needs its result
//              stalls IF and ID for one cycle and puts a bubble into EX.
//   control:   branches and jumps resolve in EX. If the next PC is not what
//              IF assumed, IF/ID and ID/EX are flushed (2-cycle penalty) and
//              fetch restarts at the right PC.
//   hold:      if a cache isn't ready (miss), the whole pipeline freezes.
//
// Branch prediction (BP = 1): a BTB with 2-bit counters is looked up in IF
// and trained in EX. With BP = 0, IF always predicts PC + 4.
module core_pipe
    import riscv_pkg::*;
#(
    parameter int BP          = 0,
    parameter int BTB_ENTRIES = 64
) (
    input  logic        clk,
    input  logic        rst,

    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,
    input  logic        imem_ready,

    output logic [31:0] dmem_addr,
    output logic        dmem_re,
    output logic        dmem_we,
    output logic [3:0]  dmem_be,
    output logic [31:0] dmem_wdata,
    input  logic [31:0] dmem_rdata,
    input  logic        dmem_ready,
    output logic        ifence,

    output logic        illegal,
    output logic [31:0] pc_out,

    output logic        retire,
    output logic        ctrl_exec,
    output logic        ctrl_redirect
);

    // ------------------------------------------------------------------
    // pipeline registers
    // ------------------------------------------------------------------
    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] instr;
        logic [31:0] pred_next;   // the PC IF fetched after this one
    } ifid_t;

    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] instr;
        ctrl_t       c;
        logic [4:0]  rs1, rs2, rd;
        logic [31:0] rs1_val, rs2_val;
        logic [31:0] imm;
        logic [31:0] pred_next;
    } idex_t;

    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] instr;
        ctrl_t       c;
        logic [4:0]  rd;
        logic [31:0] alu_y;       // ALU result / memory address
        logic [31:0] store_val;   // rs2 after forwarding
    } exmem_t;

    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] instr;
        logic        reg_we;
        logic        illegal;
        logic [4:0]  rd;
        logic [31:0] wb_data;
        // only for the trace: the store this instruction did
        logic        st_we;
        logic [31:0] st_addr;
        logic [31:0] st_data;
        logic [3:0]  st_be;
    } memwb_t;

    ifid_t  ifid;
    idex_t  idex;
    exmem_t exmem;
    memwb_t memwb;

    // a cache miss freezes everything
    logic hold, advance;
    assign hold    = !(imem_ready && dmem_ready);
    assign advance = !hold;

    // ==================================================================
    // IF
    // ==================================================================
    logic [31:0] pc_f, pc_plus4_f, pred_next_f;
    logic        pred_taken_f;
    logic [31:0] pred_target_f;

    assign imem_addr  = pc_f;
    assign pc_plus4_f = pc_f + 32'd4;
    assign pred_next_f = pred_taken_f ? pred_target_f : pc_plus4_f;

    // predictor training, driven from EX (declared here, assigned below)
    logic        bp_upd;
    logic        bp_upd_taken;
    logic [31:0] bp_upd_pc, bp_upd_target;

    generate
        if (BP != 0) begin : g_bp
            localparam int IW = $clog2(BTB_ENTRIES);
            localparam int TW = 30 - IW;          // pc[31:IW+2]

            logic [BTB_ENTRIES-1:0] btb_valid;
            logic [TW-1:0]          btb_tag    [BTB_ENTRIES];
            logic [31:0]            btb_target [BTB_ENTRIES];
            logic [1:0]             btb_ctr    [BTB_ENTRIES];   // 2-bit saturating counter

            // lookup
            logic [IW-1:0] fi;
            logic          f_hit;
            assign fi            = pc_f[IW+1:2];
            assign f_hit         = btb_valid[fi] && btb_tag[fi] == pc_f[31:IW+2];
            assign pred_taken_f  = f_hit && btb_ctr[fi][1];   // 10, 11 = predict taken
            assign pred_target_f = btb_target[fi];

            // update
            logic [IW-1:0] ui;
            logic          u_hit;
            assign ui    = bp_upd_pc[IW+1:2];
            assign u_hit = btb_valid[ui] && btb_tag[ui] == bp_upd_pc[31:IW+2];

            always_ff @(posedge clk) begin
                if (rst) begin
                    btb_valid <= '0;
                end else if (bp_upd) begin
                    if (u_hit) begin
                        // train the counter, refresh the target
                        if (bp_upd_taken && btb_ctr[ui] != 2'b11)
                            btb_ctr[ui] <= btb_ctr[ui] + 2'b01;
                        else if (!bp_upd_taken && btb_ctr[ui] != 2'b00)
                            btb_ctr[ui] <= btb_ctr[ui] - 2'b01;
                        if (bp_upd_taken)
                            btb_target[ui] <= bp_upd_target;
                    end else if (bp_upd_taken) begin
                        // only allocate on taken - a never-taken branch
                        // predicts fine without an entry (PC + 4)
                        btb_valid[ui]  <= 1'b1;
                        btb_tag[ui]    <= bp_upd_pc[31:IW+2];
                        btb_target[ui] <= bp_upd_target;
                        btb_ctr[ui]    <= 2'b10;   // weakly taken
                    end
                end
            end

            /* verilator lint_off UNUSEDSIGNAL */
            logic unused_bp;
            assign unused_bp = &{1'b0, pc_f[1:0], bp_upd_pc[1:0]};
            /* verilator lint_on UNUSEDSIGNAL */
        end else begin : g_nobp
            assign pred_taken_f  = 1'b0;
            assign pred_target_f = 32'b0;
            /* verilator lint_off UNUSEDSIGNAL */
            logic unused_bp;
            assign unused_bp = &{1'b0, bp_upd, bp_upd_taken, bp_upd_pc, bp_upd_target};
            /* verilator lint_on UNUSEDSIGNAL */
        end
    endgenerate

    // ==================================================================
    // ID
    // ==================================================================
    logic [4:0] rs1_d, rs2_d, rd_d;
    assign rd_d  = ifid.instr[11:7];
    assign rs1_d = ifid.instr[19:15];
    assign rs2_d = ifid.instr[24:20];

    ctrl_t c_d;
    decoder u_dec (
        .opcode (ifid.instr[6:0]),
        .funct3 (ifid.instr[14:12]),
        .funct7 (ifid.instr[31:25]),
        .c      (c_d)
    );

    logic [31:0] imm_d;
    immgen u_imm (
        .instr    (ifid.instr[31:7]),
        .imm_type (c_d.imm_type),
        .imm      (imm_d)
    );

    logic [31:0] rs1_val_d, rs2_val_d;
    regfile #(.BYPASS(1'b1)) u_rf (   // WB -> ID bypass on
        .clk    (clk),
        .we     (memwb.valid && memwb.reg_we && advance),
        .waddr  (memwb.rd),
        .wdata  (memwb.wb_data),
        .raddr1 (rs1_d),
        .raddr2 (rs2_d),
        .rdata1 (rs1_val_d),
        .rdata2 (rs2_val_d)
    );

    // load-use hazard: the load in EX won't have its data until the end of
    // MEM, one cycle too late to forward into this instruction's EX
    logic load_use;
    assign load_use = ifid.valid && idex.valid && idex.c.mem_re && idex.rd != 5'd0 &&
                      ((c_d.use_rs1 && idex.rd == rs1_d) ||
                       (c_d.use_rs2 && idex.rd == rs2_d));

    // ==================================================================
    // EX
    // ==================================================================
    // value the EX/MEM instruction will write back (not valid for loads,
    // but the load-use stall guarantees nobody needs that)
    logic [31:0] exmem_fwd;
    assign exmem_fwd = (exmem.c.wb_sel == WB_PC4) ? exmem.pc + 32'd4 : exmem.alu_y;

    function automatic logic [31:0] forward(input logic [4:0] r, input logic [31:0] reg_val);
        if (r != 5'd0 && exmem.valid && exmem.c.reg_we && exmem.rd == r)
            return exmem_fwd;                  // newest value wins
        else if (r != 5'd0 && memwb.valid && memwb.reg_we && memwb.rd == r)
            return memwb.wb_data;
        else
            return reg_val;
    endfunction

    logic [31:0] rs1_x, rs2_x;
    assign rs1_x = forward(idex.rs1, idex.rs1_val);
    assign rs2_x = forward(idex.rs2, idex.rs2_val);

    logic [31:0] alu_a, alu_b, alu_y;
    assign alu_a = idex.c.alu_a_pc  ? idex.pc  : rs1_x;
    assign alu_b = idex.c.alu_b_imm ? idex.imm : rs2_x;

    alu u_alu (
        .op (idex.c.alu_op),
        .a  (alu_a),
        .b  (alu_b),
        .y  (alu_y)
    );

    logic [31:0] pc_plus4_x, target_x, actual_next;
    logic        taken_x, jump_taken;
    assign pc_plus4_x = idex.pc + 32'd4;
    assign target_x   = idex.c.jalr ? {alu_y[31:1], 1'b0} : idex.pc + idex.imm;
    assign taken_x    = idex.c.branch && branch_taken(rs1_x, rs2_x, idex.instr[14:12]);
    assign jump_taken = taken_x || idex.c.jal || idex.c.jalr;
    assign actual_next = jump_taken ? target_x : pc_plus4_x;

    // redirect when IF guessed wrong. FENCE.I always redirects (to PC+4) so
    // everything fetched after it is thrown away and fetched again.
    logic redirect;
    assign redirect = idex.valid && (actual_next != idex.pred_next || idex.c.fence_i);

    logic is_ctrl_x;
    assign is_ctrl_x = idex.valid && (idex.c.branch || idex.c.jal || idex.c.jalr);

    assign bp_upd        = is_ctrl_x && advance;
    assign bp_upd_pc     = idex.pc;
    assign bp_upd_taken  = jump_taken;
    assign bp_upd_target = target_x;

    assign ifence        = idex.valid && idex.c.fence_i && advance;
    assign ctrl_exec     = is_ctrl_x && advance;
    assign ctrl_redirect = is_ctrl_x && advance && redirect;

    // ==================================================================
    // MEM
    // ==================================================================
    logic [2:0] funct3_m;
    assign funct3_m = exmem.instr[14:12];

    assign dmem_addr  = exmem.alu_y;
    assign dmem_re    = exmem.valid && exmem.c.mem_re;
    assign dmem_we    = exmem.valid && exmem.c.mem_we && advance;
    assign dmem_be    = store_be(exmem.alu_y[1:0], funct3_m[1:0]);
    assign dmem_wdata = store_data(exmem.store_val, funct3_m[1:0]);

    logic [31:0] wb_data_m;
    always_comb begin
        unique case (exmem.c.wb_sel)
            WB_MEM:  wb_data_m = load_extract(dmem_rdata, exmem.alu_y[1:0], funct3_m);
            WB_PC4:  wb_data_m = exmem.pc + 32'd4;
            default: wb_data_m = exmem.alu_y;
        endcase
    end

    // ==================================================================
    // WB
    // ==================================================================
    assign retire  = memwb.valid && advance;
    assign illegal = memwb.valid && memwb.illegal;
    assign pc_out  = memwb.pc;

    // ==================================================================
    // pipeline register updates
    // ==================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            pc_f        <= 32'h0;
            ifid.valid  <= 1'b0;
            idex.valid  <= 1'b0;
            exmem.valid <= 1'b0;
            memwb.valid <= 1'b0;
        end else if (advance) begin
            // ---- PC ----
            if (redirect)
                pc_f <= actual_next;
            else if (!load_use)
                pc_f <= pred_next_f;

            // ---- IF/ID ----
            if (redirect)
                ifid.valid <= 1'b0;                       // flush
            else if (!load_use)
                ifid <= '{valid: 1'b1, pc: pc_f, instr: imem_rdata, pred_next: pred_next_f};

            // ---- ID/EX ----
            if (redirect || load_use) begin
                idex.valid <= 1'b0;                       // flush / bubble
            end else begin
                idex.valid     <= ifid.valid;
                idex.pc        <= ifid.pc;
                idex.instr     <= ifid.instr;
                idex.c         <= c_d;
                idex.rs1       <= rs1_d;
                idex.rs2       <= rs2_d;
                idex.rd        <= rd_d;
                idex.rs1_val   <= rs1_val_d;
                idex.rs2_val   <= rs2_val_d;
                idex.imm       <= imm_d;
                idex.pred_next <= ifid.pred_next;
            end

            // ---- EX/MEM ----
            exmem.valid     <= idex.valid;
            exmem.pc        <= idex.pc;
            exmem.instr     <= idex.instr;
            exmem.c         <= idex.c;
            exmem.rd        <= idex.rd;
            exmem.alu_y     <= alu_y;
            exmem.store_val <= rs2_x;

            // ---- MEM/WB ----
            memwb.valid   <= exmem.valid;
            memwb.pc      <= exmem.pc;
            memwb.instr   <= exmem.instr;
            memwb.reg_we  <= exmem.c.reg_we;
            memwb.illegal <= exmem.c.illegal;
            memwb.rd      <= exmem.rd;
            memwb.wb_data <= wb_data_m;
            memwb.st_we   <= exmem.valid && exmem.c.mem_we;
            memwb.st_addr <= dmem_addr;
            memwb.st_data <= dmem_wdata;
            memwb.st_be   <= dmem_be;
        end
    end

`ifndef SYNTHESIS
    // ---------------- instruction trace (at WB, same format as core_single) ----------------
    int    trace_fd;
    bit    trace_stop;
    string trace_file;
    initial begin
        trace_fd = 0;
        if ($value$plusargs("trace=%s", trace_file))
            trace_fd = $fopen(trace_file, "w");
    end

    always_ff @(posedge clk) begin
        if (rst)
            trace_stop <= 1'b0;
        else if (trace_fd != 0 && !trace_stop && memwb.valid && advance) begin
            $fwrite(trace_fd, "%08x %08x", memwb.pc, memwb.instr);
            if (memwb.reg_we && memwb.rd != 5'd0)
                $fwrite(trace_fd, " x%0d=%08x", memwb.rd, memwb.wb_data);
            if (memwb.st_we)
                $fwrite(trace_fd, " mem[%08x]=%08x be=%b", memwb.st_addr, memwb.st_data, memwb.st_be);
            $fwrite(trace_fd, "\n");
            if ((memwb.st_we && {memwb.st_addr[31:2], 2'b00} == MMIO_STATUS) || memwb.illegal)
                trace_stop <= 1'b1;
        end
    end

    final if (trace_fd != 0) $fclose(trace_fd);

    // ---------------- pipeline view (+pipeview=<file>) ----------------
    // One line per cycle: the PC in each stage ("--------" = bubble) and
    // what the hazard logic did that cycle.
    int    pv_fd;
    int    pv_cycle;
    string pv_file;
    initial begin
        pv_fd = 0;
        if ($value$plusargs("pipeview=%s", pv_file)) begin
            pv_fd = $fopen(pv_file, "w");
            $fwrite(pv_fd, "cycle  IF        ID        EX        MEM       WB        events\n");
        end
    end

    function automatic string stage(input logic v, input logic [31:0] pc);
        return v ? $sformatf("%08x", pc) : "--------";
    endfunction

    function automatic string fwd_src(input logic [4:0] r, input logic uses);
        if (!uses || r == 5'd0) return "";
        if (exmem.valid && exmem.c.reg_we && exmem.rd == r) return "EX/MEM";
        if (memwb.valid && memwb.reg_we && memwb.rd == r)   return "MEM/WB";
        return "";
    endfunction

    always_ff @(posedge clk) begin
        if (!rst && pv_fd != 0 && !trace_stop) begin
            string ev, f1, f2;
            ev = "";
            f1 = fwd_src(idex.rs1, idex.valid && idex.c.use_rs1);
            f2 = fwd_src(idex.rs2, idex.valid && idex.c.use_rs2);
            if (f1 != "")  ev = {ev, $sformatf("fwd x%0d<-%s ", idex.rs1, f1)};
            if (f2 != "")  ev = {ev, $sformatf("fwd x%0d<-%s ", idex.rs2, f2)};
            if (hold)      ev = {ev, "HOLD(cache miss) "};
            if (load_use && !redirect) ev = {ev, "STALL(load-use) "};
            if (redirect)  ev = {ev, $sformatf("FLUSH->%08x ", actual_next)};
            $fwrite(pv_fd, "%5d  %s  %s  %s  %s  %s  %s\n", pv_cycle,
                    stage(1'b1, pc_f), stage(ifid.valid, ifid.pc), stage(idex.valid, idex.pc),
                    stage(exmem.valid, exmem.pc), stage(memwb.valid, memwb.pc), ev);
        end
        pv_cycle <= rst ? 0 : pv_cycle + 1;
    end
    final if (pv_fd != 0) $fclose(pv_fd);
`endif

endmodule
