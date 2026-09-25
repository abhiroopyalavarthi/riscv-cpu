// Main decoder / control unit. Only looks at opcode, funct3 and funct7 -
// register numbers and immediates are pulled out in the datapath.
module decoder
    import riscv_pkg::*;
(
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    output ctrl_t      c
);

    // funct3 -> ALU op for OP and OP-IMM.
    // alt = funct7[5] (instr[30]): picks SUB over ADD (register form only)
    // and SRA over SRL (both forms).
    function automatic alu_op_e alu_from_f3(input logic [2:0] f3, input logic alt,
                                            input logic is_imm);
        case (f3)
            3'b000:  return (alt && !is_imm) ? ALU_SUB : ALU_ADD;
            3'b001:  return ALU_SLL;
            3'b010:  return ALU_SLT;
            3'b011:  return ALU_SLTU;
            3'b100:  return ALU_XOR;
            3'b101:  return alt ? ALU_SRA : ALU_SRL;
            3'b110:  return ALU_OR;
            default: return ALU_AND;
        endcase
    endfunction

    logic alt;
    assign alt = funct7[5];

    always_comb begin
        // defaults = a NOP
        c           = '0;
        c.alu_op    = ALU_ADD;
        c.wb_sel    = WB_ALU;
        c.imm_type  = IMM_I;

        unique case (opcode)
            OP_LUI: begin
                c.reg_we    = 1'b1;
                c.alu_b_imm = 1'b1;
                c.alu_op    = ALU_PASS_B;
                c.imm_type  = IMM_U;
            end
            OP_AUIPC: begin
                c.reg_we    = 1'b1;
                c.alu_a_pc  = 1'b1;
                c.alu_b_imm = 1'b1;
                c.imm_type  = IMM_U;
            end
            OP_JAL: begin
                c.reg_we   = 1'b1;
                c.jal      = 1'b1;
                c.wb_sel   = WB_PC4;
                c.imm_type = IMM_J;
            end
            OP_JALR: begin
                c.reg_we    = 1'b1;
                c.jalr      = 1'b1;
                c.alu_b_imm = 1'b1;          // target = rs1 + imm
                c.wb_sel    = WB_PC4;
                c.illegal   = (funct3 != 3'b000);
            end
            OP_BRANCH: begin
                c.branch   = 1'b1;
                c.imm_type = IMM_B;
                c.illegal  = (funct3[2:1] == 2'b01);   // 010, 011 unused
            end
            OP_LOAD: begin
                c.reg_we    = 1'b1;
                c.mem_re    = 1'b1;
                c.alu_b_imm = 1'b1;          // address = rs1 + imm
                c.wb_sel    = WB_MEM;
                c.illegal   = (funct3 == 3'b011) || (funct3[2:1] == 2'b11);
            end
            OP_STORE: begin
                c.mem_we    = 1'b1;
                c.alu_b_imm = 1'b1;
                c.imm_type  = IMM_S;
                c.illegal   = (funct3 > 3'b010);
            end
            OP_IMM: begin
                c.reg_we    = 1'b1;
                c.alu_b_imm = 1'b1;
                c.alu_op    = alu_from_f3(funct3, alt, 1'b1);
                // shift-immediates: upper bits must be 0000000 (or 0100000 for SRAI)
                if (funct3 == 3'b001)
                    c.illegal = (funct7 != 7'b0000000);
                else if (funct3 == 3'b101)
                    c.illegal = (funct7 != 7'b0000000) && (funct7 != 7'b0100000);
            end
            OP_OP: begin
                c.reg_we = 1'b1;
                c.alu_op = alu_from_f3(funct3, alt, 1'b0);
                // only ADD/SUB and SRL/SRA have a second encoding
                if (funct7 == 7'b0100000)
                    c.illegal = (funct3 != 3'b000) && (funct3 != 3'b101);
                else
                    c.illegal = (funct7 != 7'b0000000);
            end
            OP_FENCE, OP_SYSTEM: begin
                // single hart, no caches yet, no CSRs: treat as NOP
            end
            default: c.illegal = 1'b1;
        endcase

        // an illegal instruction must not change state
        if (c.illegal) begin
            c.reg_we = 1'b0;
            c.mem_we = 1'b0;
            c.mem_re = 1'b0;
        end
    end

endmodule
