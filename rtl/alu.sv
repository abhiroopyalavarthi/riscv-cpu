// RV32I ALU - purely combinational.
module alu
    import riscv_pkg::*;
(
    input  alu_op_e     op,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] y
);

    // RV32I only uses the low 5 bits of the shift amount
    logic [4:0] shamt;
    assign shamt = b[4:0];

    always_comb begin
        unique case (op)
            ALU_ADD:    y = a + b;
            ALU_SUB:    y = a - b;
            ALU_SLL:    y = a << shamt;
            ALU_SLT:    y = {31'b0, $signed(a) < $signed(b)};
            ALU_SLTU:   y = {31'b0, a < b};
            ALU_XOR:    y = a ^ b;
            ALU_SRL:    y = a >> shamt;
            ALU_SRA:    y = $unsigned($signed(a) >>> shamt);
            ALU_OR:     y = a | b;
            ALU_AND:    y = a & b;
            ALU_PASS_B: y = b;
            default:    y = 32'b0;
        endcase
    end

endmodule
