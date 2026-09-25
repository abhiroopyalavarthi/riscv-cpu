// 32 x 32-bit register file.
// 2 combinational read ports, 1 synchronous write port.
// x0 always reads 0, writes to it are dropped.
//
// Write-through bypass (BYPASS=1): if WB writes a register in the same cycle
// ID reads it, the read returns the new value. The pipeline needs this
// (otherwise WB->ID is a 3rd forwarding path).
//
// The single-cycle core must use BYPASS=0. There the reader and the writer
// are the SAME instruction (addi a0, a0, 1), so the bypass would feed the
// result back into its own input: a combinational loop.
module regfile #(
    parameter bit BYPASS = 1'b1
) (
    input  logic        clk,
    input  logic        we,
    input  logic [4:0]  waddr,
    input  logic [31:0] wdata,
    input  logic [4:0]  raddr1,
    input  logic [4:0]  raddr2,
    output logic [31:0] rdata1,
    output logic [31:0] rdata2
);

    logic [31:0] regs [1:31];   // no storage for x0

    always_ff @(posedge clk) begin
        if (we && waddr != 5'd0)
            regs[waddr] <= wdata;
    end

    function automatic logic [31:0] read_port(input logic [4:0] ra);
        if (ra == 5'd0)
            return 32'b0;
        else if (BYPASS && we && waddr == ra)
            return wdata;               // bypass
        else
            return regs[ra];
    endfunction

    assign rdata1 = read_port(raddr1);
    assign rdata2 = read_port(raddr2);

endmodule
