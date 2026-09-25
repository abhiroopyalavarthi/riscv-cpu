// Direct-mapped cache with 16-byte lines, used for both the I-cache and the
// D-cache.
//
//   read hit:   data comes back the same cycle (ready = 1)
//   read miss:  ready = 0 for MISS_PENALTY cycles, then the whole line is
//               filled from RAM and the next cycle hits. The RAM underneath
//               is still single-cycle; MISS_PENALTY models a slow memory.
//   write:      write-through, no write-allocate. The store always goes to
//               RAM (the SoC does that); if the line is cached it's updated
//               here too. Stores never stall.
//   flush:      invalidates everything (FENCE.I on the I-cache).
module cache #(
    parameter int SIZE_BYTES   = 1024,
    parameter int MISS_PENALTY = 10
) (
    input  logic         clk,
    input  logic         rst,

    input  logic         req,        // read request
    input  logic [31:0]  addr,
    input  logic         we,         // write (write-through update on hit)
    input  logic [3:0]   be,
    input  logic [31:0]  wdata,
    input  logic         flush,
    input  logic         count_en,   // pipeline is advancing: count this access

    output logic         ready,
    output logic [31:0]  rdata,

    // line fill from RAM
    output logic [31:0]  line_addr,
    input  logic [127:0] line_data,

    output logic [31:0]  n_access,   // completed reads
    output logic [31:0]  n_miss      // line fills
);

    localparam int LINES = SIZE_BYTES / 16;
    localparam int IW    = $clog2(LINES);
    localparam int TW    = 32 - IW - 4;

    logic [LINES-1:0] valid;
    logic [TW-1:0]    tags  [LINES];
    logic [127:0]     lines [LINES];

    logic [IW-1:0] idx;
    logic [TW-1:0] tag;
    logic [1:0]    word;
    assign idx  = addr[IW+3:4];
    assign tag  = addr[31:IW+4];
    assign word = addr[3:2];

    logic hit;
    assign hit   = valid[idx] && tags[idx] == tag;
    assign ready = !req || hit;
    assign rdata = lines[idx][32*word +: 32];

    assign line_addr = {addr[31:4], 4'b0};

    int unsigned wait_cnt;

    always_ff @(posedge clk) begin
        if (rst) begin
            valid    <= '0;
            wait_cnt <= 0;
            n_access <= 32'b0;
            n_miss   <= 32'b0;
        end else if (flush) begin
            valid    <= '0;
            wait_cnt <= 0;
        end else begin
            // ---- read miss: wait, then fill ----
            if (req && !hit) begin
                if (wait_cnt == MISS_PENALTY - 1) begin
                    valid[idx] <= 1'b1;
                    tags[idx]  <= tag;
                    lines[idx] <= line_data;
                    wait_cnt   <= 0;
                    n_miss     <= n_miss + 1;
                end else begin
                    wait_cnt <= wait_cnt + 1;
                end
            end

            // ---- write-through: update the cached copy on a hit ----
            if (we && hit) begin
                for (int b = 0; b < 4; b++)
                    if (be[b]) lines[idx][32*word + 8*b +: 8] <= wdata[8*b +: 8];
            end

            if (req && hit && count_en)
                n_access <= n_access + 1;
        end
    end

    /* verilator lint_off UNUSEDSIGNAL */
    logic unused;
    assign unused = &{1'b0, addr[1:0]};
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
