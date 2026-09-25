// Shared types for the whole core. Everything else imports this.
// Not every module uses every constant here (the ALU unit test only
// needs alu_op_e), so unused-parameter warnings are off for the package.
/* verilator lint_off UNUSEDPARAM */
package riscv_pkg;

    // ALU operations. The encoding here is my own, it doesn't have to
    // match funct3/funct7 - the decoder translates.
    typedef enum logic [3:0] {
        ALU_ADD  = 4'd0,
        ALU_SUB  = 4'd1,
        ALU_SLL  = 4'd2,
        ALU_SLT  = 4'd3,
        ALU_SLTU = 4'd4,
        ALU_XOR  = 4'd5,
        ALU_SRL  = 4'd6,
        ALU_SRA  = 4'd7,
        ALU_OR   = 4'd8,
        ALU_AND  = 4'd9,
        ALU_PASS_B = 4'd10   // used for LUI (result = imm)
    } alu_op_e;

    // ---------------- opcodes (instr[6:0]) ----------------
    localparam logic [6:0] OP_LUI    = 7'b0110111;
    localparam logic [6:0] OP_AUIPC  = 7'b0010111;
    localparam logic [6:0] OP_JAL    = 7'b1101111;
    localparam logic [6:0] OP_JALR   = 7'b1100111;
    localparam logic [6:0] OP_BRANCH = 7'b1100011;
    localparam logic [6:0] OP_LOAD   = 7'b0000011;
    localparam logic [6:0] OP_STORE  = 7'b0100011;
    localparam logic [6:0] OP_IMM    = 7'b0010011;
    localparam logic [6:0] OP_OP     = 7'b0110011;
    localparam logic [6:0] OP_FENCE  = 7'b0001111;
    localparam logic [6:0] OP_SYSTEM = 7'b1110011;

    typedef enum logic [2:0] {
        IMM_I = 3'd0,
        IMM_S = 3'd1,
        IMM_B = 3'd2,
        IMM_U = 3'd3,
        IMM_J = 3'd4
    } imm_type_e;

    // what gets written back to rd
    typedef enum logic [1:0] {
        WB_ALU = 2'd0,
        WB_MEM = 2'd1,
        WB_PC4 = 2'd2    // JAL / JALR link address
    } wb_sel_e;

    // everything the decoder tells the datapath
    typedef struct packed {
        logic      reg_we;
        logic      mem_re;
        logic      mem_we;
        logic      branch;
        logic      jal;
        logic      jalr;
        logic      alu_a_pc;   // ALU A = PC instead of rs1 (AUIPC)
        logic      alu_b_imm;  // ALU B = imm instead of rs2
        alu_op_e   alu_op;
        wb_sel_e   wb_sel;
        imm_type_e imm_type;
        logic      use_rs1;    // instruction reads rs1 / rs2 (for the
        logic      use_rs2;    //   pipeline's load-use hazard check)
        logic      fence_i;    // FENCE.I: flush fetch + I-cache
        logic      illegal;
    } ctrl_t;

    // MMIO status register - both cores stop their trace after the store
    // that ends the test, so traces from different cores line up exactly
    localparam logic [31:0] MMIO_STATUS = 32'h1000_0008;

    // ---------------- branch compare (funct3) ----------------
    function automatic logic branch_taken(input logic [31:0] a, input logic [31:0] b,
                                          input logic [2:0] f3);
        case (f3)
            3'b000:  return a == b;                    // BEQ
            3'b001:  return a != b;                    // BNE
            3'b100:  return $signed(a) <  $signed(b);  // BLT
            3'b101:  return $signed(a) >= $signed(b);  // BGE
            3'b110:  return a <  b;                    // BLTU
            3'b111:  return a >= b;                    // BGEU
            default: return 1'b0;
        endcase
    endfunction

    // ---------------- load/store helpers ----------------
    // Memory is word-wide. Stores replicate the byte/half across the word
    // and the byte enables pick which lanes actually get written, so no
    // shifter is needed on the store side.
    function automatic logic [3:0] store_be(input logic [1:0] off, input logic [1:0] size);
        case (size)
            2'b00:   return 4'b0001 << off;             // SB
            2'b01:   return off[1] ? 4'b1100 : 4'b0011; // SH
            default: return 4'b1111;                    // SW
        endcase
    endfunction

    function automatic logic [31:0] store_data(input logic [31:0] v, input logic [1:0] size);
        case (size)
            2'b00:   return {4{v[7:0]}};
            2'b01:   return {2{v[15:0]}};
            default: return v;
        endcase
    endfunction

    // pick the right byte/half out of the loaded word and extend it
    function automatic logic [31:0] load_extract(input logic [31:0] w, input logic [1:0] off,
                                                 input logic [2:0] f3);
        logic [7:0]  b;
        logic [15:0] h;
        b = w[8*off +: 8];
        h = off[1] ? w[31:16] : w[15:0];
        case (f3)
            3'b000:  return {{24{b[7]}}, b};    // LB
            3'b001:  return {{16{h[15]}}, h};   // LH
            3'b100:  return {24'b0, b};         // LBU
            3'b101:  return {16'b0, h};         // LHU
            default: return w;                  // LW
        endcase
    endfunction

endpackage
/* verilator lint_on UNUSEDPARAM */
