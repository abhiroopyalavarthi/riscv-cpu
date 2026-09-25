// Single-cycle RV32I core. Every instruction fetches, decodes, executes,
// accesses memory and writes back in one clock. CPI = 1 by definition,
// which makes this the reference model for the pipeline later.
module core_single
    import riscv_pkg::*;
(
    input  logic        clk,
    input  logic        rst,

    // instruction port
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,
    input  logic        imem_ready,   // always 1 here (no caches on this core)

    // data port
    output logic [31:0] dmem_addr,
    output logic        dmem_re,
    output logic        dmem_we,
    output logic [3:0]  dmem_be,
    output logic [31:0] dmem_wdata,
    input  logic [31:0] dmem_rdata,
    input  logic        dmem_ready,
    output logic        ifence,       // FENCE.I (only the pipeline uses it)

    output logic        illegal,      // decoder hit something it doesn't know
    output logic        misaligned,   // load/store address not aligned to its size
    output logic [31:0] fault_addr,   // ...and the address it tried to use
    output logic [31:0] pc_out,

    // performance counter events
    output logic        retire,       // an instruction completed this cycle
    output logic        ctrl_exec,    // it was a branch or jump
    output logic        ctrl_redirect // ...and it changed the PC (taken)
);

    // ---------------- fetch ----------------
    logic [31:0] pc, next_pc;
    logic [31:0] instr;

    always_ff @(posedge clk) begin
        if (rst) pc <= 32'h0;
        else     pc <= next_pc;
    end

    assign imem_addr = pc;
    assign instr     = imem_rdata;
    assign pc_out    = pc;

    // ---------------- decode ----------------
    logic [4:0] rs1, rs2, rd;
    logic [2:0] funct3;
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];

    ctrl_t c;
    decoder u_dec (
        .opcode (instr[6:0]),
        .funct3 (funct3),
        .funct7 (instr[31:25]),
        .c      (c)
    );

    logic [31:0] imm;
    immgen u_imm (
        .instr    (instr[31:7]),
        .imm_type (c.imm_type),
        .imm      (imm)
    );

    logic [31:0] rs1_val, rs2_val, wb_data;
    regfile #(.BYPASS(1'b0)) u_rf (   // no bypass - see regfile.sv
        .clk    (clk),
        .we     (c.reg_we && !rst && !misaligned),
        .waddr  (rd),
        .wdata  (wb_data),
        .raddr1 (rs1),
        .raddr2 (rs2),
        .rdata1 (rs1_val),
        .rdata2 (rs2_val)
    );

    // ---------------- execute ----------------
    logic [31:0] alu_a, alu_b, alu_y;
    assign alu_a = c.alu_a_pc  ? pc  : rs1_val;
    assign alu_b = c.alu_b_imm ? imm : rs2_val;

    alu u_alu (
        .op (c.alu_op),
        .a  (alu_a),
        .b  (alu_b),
        .y  (alu_y)
    );

    // branches and JAL use their own adder so the ALU stays free for the compare
    logic [31:0] pc_plus4, pc_target;
    logic        taken;
    assign pc_plus4  = pc + 32'd4;
    assign pc_target = pc + imm;
    assign taken     = c.branch && branch_taken(rs1_val, rs2_val, funct3);

    always_comb begin
        if (c.jalr)
            next_pc = {alu_y[31:1], 1'b0};     // spec: clear bit 0
        else if (c.jal || taken)
            next_pc = pc_target;
        else
            next_pc = pc_plus4;
    end

    // ---------------- memory ----------------
    assign dmem_addr  = alu_y;
    assign dmem_re    = c.mem_re;
    // a misaligned access is a fault: the store doesn't happen, the load
    // doesn't write rd, and the SoC stops the simulation
    assign misaligned = !rst && (c.mem_re || c.mem_we) && addr_misaligned(alu_y[1:0], funct3[1:0]);
    assign fault_addr = alu_y;

    assign dmem_we    = c.mem_we && !rst && !misaligned;
    assign dmem_be    = store_be(alu_y[1:0], funct3[1:0]);
    assign dmem_wdata = store_data(rs2_val, funct3[1:0]);

    logic [31:0] load_val;
    assign load_val = load_extract(dmem_rdata, alu_y[1:0], funct3);

    // ---------------- writeback ----------------
    always_comb begin
        unique case (c.wb_sel)
            WB_MEM:  wb_data = load_val;
            WB_PC4:  wb_data = pc_plus4;
            default: wb_data = alu_y;
        endcase
    end

    assign illegal = c.illegal && !rst;
    assign ifence  = 1'b0;

    assign retire        = !rst;
    assign ctrl_exec     = !rst && (c.branch || c.jal || c.jalr);
    assign ctrl_redirect = !rst && (next_pc != pc_plus4);

    // Ports/fields that only the pipelined core needs. Same interface for
    // both cores keeps soc.sv simple.
    /* verilator lint_off UNUSEDSIGNAL */
    logic unused;
    assign unused = &{1'b0, imem_ready, dmem_ready, c.use_rs1, c.use_rs2, c.fence_i};
    /* verilator lint_on UNUSEDSIGNAL */

`ifndef SYNTHESIS
    // ---------------- instruction trace ----------------
    // One line per retired instruction: PC, raw instruction, register
    // write, store. The pipeline prints the same format at WB, so the two
    // traces can be diffed directly.
    // Tracing stops after the store that ends the test, so traces from
    // both cores line up exactly (the pipeline keeps running a few cycles).
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
        else if (trace_fd != 0 && !trace_stop) begin
            $fwrite(trace_fd, "%08x %08x", pc, instr);
            if (c.reg_we && !misaligned && rd != 5'd0)
                $fwrite(trace_fd, " x%0d=%08x", rd, wb_data);
            if (dmem_we)
                $fwrite(trace_fd, " mem[%08x]=%08x be=%b", dmem_addr, dmem_wdata, dmem_be);
            $fwrite(trace_fd, "\n");
            if ((dmem_we && {dmem_addr[31:2], 2'b00} == MMIO_STATUS) || illegal || misaligned)
                trace_stop <= 1'b1;
        end
    end

    final if (trace_fd != 0) $fclose(trace_fd);
`endif

endmodule
