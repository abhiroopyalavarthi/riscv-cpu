// tb/tb_regfile.cpp - random reads/writes against a shadow array.
// Also checks x0 and the same-cycle write->read bypass.
#include <cstdio>
#include <cstdint>
#include <random>
#include "verilated.h"
#include "verilated_fst_c.h"
#include "Vregfile.h"

static Vregfile* dut;
static VerilatedContext* ctx;
static VerilatedFstC* tfp;
static uint32_t shadow[32] = {0};
static int errors = 0, checks = 0;

static void expect(const char* what, uint32_t got, uint32_t exp) {
    checks++;
    if (got != exp) {
        if (errors < 20) printf("FAIL %s: got=%08x exp=%08x\n", what, got, exp);
        errors++;
    }
}

// drive inputs, check combinational reads (before the edge), then clock
static void cycle(bool we, int wa, uint32_t wd, int ra1, int ra2) {
    dut->we = we; dut->waddr = wa; dut->wdata = wd;
    dut->raddr1 = ra1; dut->raddr2 = ra2;
    dut->clk = 0;
    dut->eval();
    tfp->dump(ctx->time()); ctx->timeInc(1);

    // expected read value this cycle, including bypass
    auto rd = [&](int ra) -> uint32_t {
        if (ra == 0) return 0;
        if (we && wa == ra) return wd;
        return shadow[ra];
    };
    expect("rdata1", dut->rdata1, rd(ra1));
    expect("rdata2", dut->rdata2, rd(ra2));

    dut->clk = 1;
    dut->eval();
    tfp->dump(ctx->time()); ctx->timeInc(1);

    if (we && wa != 0) shadow[wa] = wd;
}

int main(int argc, char** argv) {
    ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);
    ctx->traceEverOn(true);
    dut = new Vregfile{ctx};
    tfp = new VerilatedFstC;
    dut->trace(tfp, 99);
    tfp->open("build/regfile.fst");

    // write a known value to every register first so nothing reads X/garbage
    for (int r = 1; r < 32; r++) cycle(true, r, 0x1000 + r, 0, 0);

    // x0: write junk, must still read 0 (also during the write cycle)
    cycle(true, 0, 0xDEADBEEF, 0, 0);
    cycle(false, 0, 0, 0, 0);

    // same-cycle write and read of the same register
    cycle(true, 5, 0xCAFEF00D, 5, 5);
    cycle(false, 0, 0, 5, 0);

    std::mt19937 rng(301);
    for (int i = 0; i < 20000; i++) {
        bool we = rng() & 1;
        cycle(we, rng() & 31, rng(), rng() & 31, rng() & 31);
    }

    tfp->close();
    dut->final();
    delete dut;
    delete ctx;

    if (errors) { printf("REGFILE FAIL: %d / %d checks\n", errors, checks); return 1; }
    printf("REGFILE PASS: %d checks\n", checks);
    return 0;
}
