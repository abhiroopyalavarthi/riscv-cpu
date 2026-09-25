// 64 KB RAM, two ports:
//   port I: instruction fetch, read only
//   port D: loads/stores, byte-enable writes
// Reads are combinational (fine for simulation and for the single-cycle
// core). Loaded from a hex file given with +hex=<file>.
module ram #(
    parameter int WORDS = 16384          // 16K words = 64 KB
) (
    input  logic        clk,

    input  logic [31:0] i_addr,
    output logic [31:0] i_rdata,

    input  logic [31:0] d_addr,
    input  logic        d_we,
    input  logic [3:0]  d_be,
    input  logic [31:0] d_wdata,
    output logic [31:0] d_rdata,

    // whole 16-byte lines, for cache fills
    input  logic [31:0]  i_line_addr,
    output logic [127:0] i_line,
    input  logic [31:0]  d_line_addr,
    output logic [127:0] d_line
);

    localparam int AW = $clog2(WORDS);

    logic [31:0] mem [0:WORDS-1];

    logic [AW-1:0] i_idx, d_idx;
    assign i_idx = i_addr[AW+1:2];
    assign d_idx = d_addr[AW+1:2];

    assign i_rdata = mem[i_idx];
    assign d_rdata = mem[d_idx];

    logic [AW-3:0] il_idx, dl_idx;      // line index = word index / 4
    assign il_idx = i_line_addr[AW+1:4];
    assign dl_idx = d_line_addr[AW+1:4];
    assign i_line = {mem[{il_idx, 2'd3}], mem[{il_idx, 2'd2}], mem[{il_idx, 2'd1}], mem[{il_idx, 2'd0}]};
    assign d_line = {mem[{dl_idx, 2'd3}], mem[{dl_idx, 2'd2}], mem[{dl_idx, 2'd1}], mem[{dl_idx, 2'd0}]};

    always_ff @(posedge clk) begin
        if (d_we) begin
            for (int b = 0; b < 4; b++)
                if (d_be[b]) mem[d_idx][8*b +: 8] <= d_wdata[8*b +: 8];
        end
    end

    // The upper address bits are decoded by the SoC, and the low 2 bits
    // are handled by the byte enables, so the RAM ignores them.
    /* verilator lint_off UNUSEDSIGNAL */
    logic unused;
    assign unused = &{1'b0, i_addr[31:AW+2], i_addr[1:0], d_addr[31:AW+2], d_addr[1:0],
                      i_line_addr[31:AW+2], i_line_addr[3:0], d_line_addr[31:AW+2], d_line_addr[3:0]};
    /* verilator lint_on UNUSEDSIGNAL */

`ifndef SYNTHESIS
    string hexfile;
    initial begin
        for (int k = 0; k < WORDS; k++) mem[k] = 32'b0;
        if ($value$plusargs("hex=%s", hexfile))
            $readmemh(hexfile, mem);
        else
            $display("ram: no +hex=<file> given, memory is all zeros");
    end
`endif

endmodule
