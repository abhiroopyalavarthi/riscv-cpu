// tb/tb_counter.cpp — self-checking testbench for rtl/counter.sv
#include <cstdio>
#include <cstdint>
#include "verilated.h"
#include "verilated_fst_c.h"
#include "Vcounter.h"

int main(int argc, char** argv) {
    VerilatedContext* ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);
    ctx->traceEverOn(true);

    Vcounter* dut = new Vcounter{ctx};
    VerilatedFstC* tfp = new VerilatedFstC;
    dut->trace(tfp, 99);
    tfp->open("build/counter.fst");

    const int CYCLES = 300;   // > 256 so the 8-bit wraparound gets checked
    uint32_t expected = 0;
    int errors = 0;

    for (int cycle = 0; cycle < CYCLES; cycle++) {
        // Drive inputs while clk is low
        dut->rst = (cycle < 2 || cycle == 150);        // reset at start + once mid-run
        dut->en  = (cycle % 7 != 0);                    // en drops every 7th cycle
        dut->clk = 0;
        dut->eval();
        tfp->dump(ctx->time());
        ctx->timeInc(1);

        // Rising edge
        dut->clk = 1;
        dut->eval();
        tfp->dump(ctx->time());
        ctx->timeInc(1);

        // Reference model
        if (dut->rst)      expected = 0;
        else if (dut->en)  expected = (expected + 1) & 0xFF;

        if (dut->count != expected) {
            printf("FAIL cycle %d: rst=%d en=%d count=%u expected=%u\n",
                   cycle, dut->rst, dut->en, dut->count, expected);
            errors++;
        }
    }

    tfp->close();
    dut->final();
    delete dut;
    delete ctx;

    if (errors) {
        printf("FAIL: %d mismatches\n", errors);
        return 1;
    }
    printf("PASS: %d cycles\n", CYCLES);
    return 0;
}
