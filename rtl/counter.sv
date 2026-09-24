// Milestone 0: simple enable-able counter, used to check the Verilator flow.
module counter #(
    parameter int WIDTH = 8
) (
    input  logic             clk,
    input  logic             rst,   // synchronous, active high
    input  logic             en,
    output logic [WIDTH-1:0] count
);

    always_ff @(posedge clk) begin
        if (rst)
            count <= '0;
        else if (en)
            count <= count + 1'b1;   // wraps naturally at 2^WIDTH
    end

endmodule
