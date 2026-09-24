// Shared types for the whole core. Everything else imports this.
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

endpackage
