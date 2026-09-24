// 32 x 32-bit register file.
// 2 combinational read ports, 1 synchronous write port.
// x0 always reads 0, writes to it are dropped.
//
// Write-through bypass: if WB writes a register in the same cycle ID reads
// it, the read returns the new value. The single-cycle core doesn't care,
// but the pipeline needs it (otherwise WB->ID is a 3rd forwarding path).
module regfile (
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
        else if (we && waddr == ra)
            return wdata;               // bypass
        else
            return regs[ra];
    endfunction

    assign rdata1 = read_port(raddr1);
    assign rdata2 = read_port(raddr2);

endmodule
