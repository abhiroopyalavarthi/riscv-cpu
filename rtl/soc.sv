// Top level: core + optional caches + 64 KB RAM + memory-mapped I/O.
//
// Parameters pick the configuration (set with verilator -G...):
//   PIPELINE      0 = single-cycle core, 1 = 5-stage pipeline
//   BP            branch predictor on the pipeline
//   ICACHE_BYTES  0 = no I-cache, else direct-mapped of this size
//   DCACHE_BYTES  same for data
//   MISS_PENALTY  cycles a cache miss waits before the line arrives
//
// Memory map
//   0x0000_0000 - 0x0000_FFFF  RAM (code at 0, stack grows down from 0x1_0000)
//   0x1000_0000                UART TX: store a byte, the simulator prints it
//   0x1000_0004                cycle counter                    (read only)
//   0x1000_0008                test status: 1 = pass, (n<<1)|1 = test n failed.
//                              Any write ends the simulation.
//   0x1000_000C                instructions retired             (read only)
//   0x1000_0010                branches + jumps executed
//   0x1000_0014                control redirects (mispredicts; with no
//                              predictor = taken branches and jumps)
//   0x1000_0018 / 001C         I-cache accesses / misses
//   0x1000_0020 / 0024         D-cache reads / misses
module soc
    import riscv_pkg::*;
#(
    parameter int PIPELINE     = 0,
    parameter int BP           = 0,
    parameter int ICACHE_BYTES = 0,
    parameter int DCACHE_BYTES = 0,
    parameter int MISS_PENALTY = 10
) (
    input  logic        clk,
    input  logic        rst,
    output logic        done,
    output logic [31:0] exit_code,
    output logic [31:0] fault_pc,    // PC of the faulting instruction, if a fault is why we stopped
    output logic [31:0] fault_addr_q // address of a misaligned access
);

    localparam logic [31:0] UART_TX = 32'h1000_0000;

    // exit codes the testbench reads as faults (a program's own codes are
    // 1 or (n<<1)|1, so an even code can't be a program result)
    localparam logic [31:0] EXIT_ILLEGAL    = 32'hFFFF_FFFF;
    localparam logic [31:0] EXIT_MISALIGNED = 32'hFFFF_FFFE;

    logic [31:0] imem_addr, imem_rdata;
    logic        imem_ready;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic        dmem_re, dmem_we, dmem_ready;
    logic [3:0]  dmem_be;
    logic        ifence, illegal, misaligned;
    logic [31:0] fault_addr;
    logic [31:0] pc_out;
    logic        retire, ctrl_exec, ctrl_redirect;

    // ---------------- core ----------------
    generate
        if (PIPELINE != 0) begin : g_pipe
            core_pipe #(.BP(BP)) u_core (.*);
        end else begin : g_single
            core_single u_core (.*);
        end
    endgenerate

    // ---------------- address decode ----------------
    logic is_io;
    assign is_io = (dmem_addr[31:28] == 4'h1);

    logic [31:0]  ram_irdata, ram_drdata;
    logic [31:0]  ic_line_addr, dc_line_addr;
    logic [127:0] ic_line, dc_line;

    ram u_ram (
        .clk         (clk),
        .i_addr      (imem_addr),
        .i_rdata     (ram_irdata),
        .d_addr      (dmem_addr),
        .d_we        (dmem_we && !is_io),     // write-through: stores always reach RAM
        .d_be        (dmem_be),
        .d_wdata     (dmem_wdata),
        .d_rdata     (ram_drdata),
        .i_line_addr (ic_line_addr),
        .i_line      (ic_line),
        .d_line_addr (dc_line_addr),
        .d_line      (dc_line)
    );

    // stats only count while the pipeline moves and the test is running
    logic count_en;
    assign count_en = imem_ready && dmem_ready && !done;

    // ---------------- I-cache ----------------
    logic [31:0] ic_acc, ic_miss;
    generate
        if (ICACHE_BYTES > 0) begin : g_ic
            cache #(.SIZE_BYTES(ICACHE_BYTES), .MISS_PENALTY(MISS_PENALTY)) u_icache (
                .clk       (clk),
                .rst       (rst),
                .req       (!rst),
                .addr      (imem_addr),
                .we        (1'b0),
                .be        (4'b0),
                .wdata     (32'b0),
                .flush     (ifence),
                .count_en  (count_en),
                .ready     (imem_ready),
                .rdata     (imem_rdata),
                .line_addr (ic_line_addr),
                .line_data (ic_line),
                .n_access  (ic_acc),
                .n_miss    (ic_miss)
            );
            /* verilator lint_off UNUSEDSIGNAL */
            logic unused_ic;
            assign unused_ic = &{1'b0, ram_irdata};
            /* verilator lint_on UNUSEDSIGNAL */
        end else begin : g_noic
            assign imem_rdata   = ram_irdata;
            assign imem_ready   = 1'b1;
            assign ic_line_addr = 32'b0;
            assign ic_acc       = 32'b0;
            assign ic_miss      = 32'b0;
            /* verilator lint_off UNUSEDSIGNAL */
            logic unused_ic;
            assign unused_ic = &{1'b0, ic_line, ifence};
            /* verilator lint_on UNUSEDSIGNAL */
        end
    endgenerate

    // ---------------- D-cache ----------------
    logic [31:0] mem_rdata, dc_acc, dc_miss;
    generate
        if (DCACHE_BYTES > 0) begin : g_dc
            logic dc_ready;
            cache #(.SIZE_BYTES(DCACHE_BYTES), .MISS_PENALTY(MISS_PENALTY)) u_dcache (
                .clk       (clk),
                .rst       (rst),
                .req       (dmem_re && !is_io),       // I/O is never cached
                .addr      (dmem_addr),
                .we        (dmem_we && !is_io),
                .be        (dmem_be),
                .wdata     (dmem_wdata),
                .flush     (1'b0),
                .count_en  (count_en),
                .ready     (dc_ready),
                .rdata     (mem_rdata),
                .line_addr (dc_line_addr),
                .line_data (dc_line),
                .n_access  (dc_acc),
                .n_miss    (dc_miss)
            );
            assign dmem_ready = dc_ready;
            /* verilator lint_off UNUSEDSIGNAL */
            logic unused_dc;
            assign unused_dc = &{1'b0, ram_drdata};
            /* verilator lint_on UNUSEDSIGNAL */
        end else begin : g_nodc
            assign mem_rdata    = ram_drdata;
            assign dmem_ready   = 1'b1;
            assign dc_line_addr = 32'b0;
            assign dc_acc       = 32'b0;
            assign dc_miss      = 32'b0;
            /* verilator lint_off UNUSEDSIGNAL */
            logic unused_dc;
            assign unused_dc = &{1'b0, dc_line, dmem_re};
            /* verilator lint_on UNUSEDSIGNAL */
        end
    endgenerate

    // ---------------- performance counters ----------------
    logic [31:0] cycle_count, instret, n_ctrl, n_redirect;
    always_ff @(posedge clk) begin
        if (rst) begin
            cycle_count <= 32'b0;
            instret     <= 32'b0;
            n_ctrl      <= 32'b0;
            n_redirect  <= 32'b0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (retire)        instret    <= instret + 1;
            if (ctrl_exec)     n_ctrl     <= n_ctrl + 1;
            if (ctrl_redirect) n_redirect <= n_redirect + 1;
        end
    end

    // ---------------- I/O reads ----------------
    // +det-counters: every counter read returns how many counter reads came
    // before it, instead of the real count. Cycle counts differ between
    // cores, so programs that read them would take different paths; with
    // this switch every core sees the same values and the instruction traces
    // can be compared line by line (scripts/compare_traces.py).
    bit          det_counters;
    logic [31:0] io_reads;
`ifndef SYNTHESIS
    initial det_counters = $test$plusargs("det-counters");
`else
    assign det_counters = 1'b0;
`endif
    always_ff @(posedge clk) begin
        if (rst)                              io_reads <= 32'b0;
        else if (dmem_re && is_io && count_en) io_reads <= io_reads + 1;
    end

    logic [31:0] io_rdata;
    always_comb begin
        if (det_counters && dmem_addr[5:2] != 4'd0 && dmem_addr[5:2] <= 4'd9)
            io_rdata = io_reads;
        else case (dmem_addr[5:2])
            4'd1:    io_rdata = cycle_count;   // 0x04
            4'd3:    io_rdata = instret;       // 0x0C
            4'd4:    io_rdata = n_ctrl;        // 0x10
            4'd5:    io_rdata = n_redirect;    // 0x14
            4'd6:    io_rdata = ic_acc;        // 0x18
            4'd7:    io_rdata = ic_miss;       // 0x1C
            4'd8:    io_rdata = dc_acc;        // 0x20
            4'd9:    io_rdata = dc_miss;       // 0x24
            default: io_rdata = 32'b0;
        endcase
    end

    assign dmem_rdata = is_io ? io_rdata : mem_rdata;

    // ---------------- I/O writes, end of test ----------------
    always_ff @(posedge clk) begin
        if (rst) begin
            done      <= 1'b0;
            exit_code <= 32'b0;
            fault_pc  <= 32'b0;
            fault_addr_q <= 32'b0;
        end else if (!done) begin
            if (illegal) begin
                done      <= 1'b1;
                exit_code <= EXIT_ILLEGAL;
                fault_pc  <= pc_out;
            end else if (misaligned) begin
                done         <= 1'b1;
                exit_code    <= EXIT_MISALIGNED;
                fault_pc     <= pc_out;
                fault_addr_q <= fault_addr;
            end else if (dmem_we && is_io) begin
                if ({dmem_addr[31:2], 2'b00} == UART_TX) begin
                    $write("%c", dmem_wdata[7:0]);
                    $fflush;
                end else if ({dmem_addr[31:2], 2'b00} == MMIO_STATUS) begin
                    done      <= 1'b1;
                    exit_code <= dmem_wdata;
                end
            end
        end
    end

    /* verilator lint_off UNUSEDSIGNAL */
    logic unused;
    assign unused = &{1'b0, dmem_addr[27:6], dmem_addr[1:0], count_en};   // count_en: only the caches use it
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
