// Top level: core + 64 KB RAM + memory-mapped I/O.
//
// Memory map
//   0x0000_0000 - 0x0000_FFFF  RAM (code at 0, stack grows down from 0x1_0000)
//   0x1000_0000                UART TX: store a byte, the simulator prints it
//   0x1000_0004                cycle counter (read only)
//   0x1000_0008                test status: 1 = pass, (n<<1)|1 = test n failed.
//                              Any write ends the simulation.
module soc
    import riscv_pkg::*;
(
    input  logic        clk,
    input  logic        rst,
    output logic        done,
    output logic [31:0] exit_code,
    output logic [31:0] fault_pc     // PC of an illegal instruction, if that's why we stopped
);

    localparam logic [31:0] UART_TX = 32'h1000_0000;
    localparam logic [31:0] CYCLES  = 32'h1000_0004;
    localparam logic [31:0] STATUS  = 32'h1000_0008;

    // exit code the testbench reads as "illegal instruction"
    localparam logic [31:0] EXIT_ILLEGAL = 32'hFFFF_FFFF;

    logic [31:0] imem_addr, imem_rdata;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic        dmem_re, dmem_we;
    logic [3:0]  dmem_be;
    logic        illegal;
    logic [31:0] pc;

    core_single u_core (
        .clk        (clk),
        .rst        (rst),
        .imem_addr  (imem_addr),
        .imem_rdata (imem_rdata),
        .dmem_addr  (dmem_addr),
        .dmem_re    (dmem_re),
        .dmem_we    (dmem_we),
        .dmem_be    (dmem_be),
        .dmem_wdata (dmem_wdata),
        .dmem_rdata (dmem_rdata),
        .illegal    (illegal),
        .pc_out     (pc)
    );

    // ---------------- address decode ----------------
    logic is_io;
    assign is_io = (dmem_addr[31:28] == 4'h1);

    logic [31:0] ram_rdata;
    ram u_ram (
        .clk     (clk),
        .i_addr  (imem_addr),
        .i_rdata (imem_rdata),
        .d_addr  (dmem_addr),
        .d_we    (dmem_we && !is_io),
        .d_be    (dmem_be),
        .d_wdata (dmem_wdata),
        .d_rdata (ram_rdata)
    );

    // ---------------- I/O ----------------
    logic [31:0] cycle_count;
    always_ff @(posedge clk) begin
        if (rst) cycle_count <= 32'b0;
        else     cycle_count <= cycle_count + 1;
    end

    logic [31:0] io_rdata;
    always_comb begin
        case ({dmem_addr[31:2], 2'b00})
            CYCLES:  io_rdata = cycle_count;
            default: io_rdata = 32'b0;
        endcase
    end

    assign dmem_rdata = is_io ? io_rdata : ram_rdata;

    always_ff @(posedge clk) begin
        if (rst) begin
            done      <= 1'b0;
            exit_code <= 32'b0;
            fault_pc  <= 32'b0;
        end else if (!done) begin
            if (illegal) begin
                done      <= 1'b1;
                exit_code <= EXIT_ILLEGAL;
                fault_pc  <= pc;
            end else if (dmem_we && is_io) begin
                if ({dmem_addr[31:2], 2'b00} == UART_TX) begin
                    $write("%c", dmem_wdata[7:0]);
                    $fflush;
                end else if ({dmem_addr[31:2], 2'b00} == STATUS) begin
                    done      <= 1'b1;
                    exit_code <= dmem_wdata;
                end
            end
        end
    end

    // dmem_re isn't needed yet (loads have no side effects) - the caches use it later
    /* verilator lint_off UNUSEDSIGNAL */
    logic unused;
    assign unused = &{1'b0, dmem_re};
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
