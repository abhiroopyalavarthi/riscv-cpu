// tb/tb_soc.cpp - runs a program on the CPU until it writes the status
// register (or times out).
//
//   ./Vsoc +hex=prog.hex [+trace=prog.trace] [+wave=prog.fst] [+max-cycles=N]
//
// Exit code 0 only if the program wrote 1 to the status register.
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <string>
#include "verilated.h"
#include "verilated_fst_c.h"
#include "Vsoc.h"

// "+name=value" -> value, or "" if not given
static std::string plusarg(VerilatedContext* ctx, const char* name) {
    std::string m = ctx->commandArgsPlusMatch(name);
    std::string prefix = std::string("+") + name + "=";
    if (m.rfind(prefix, 0) == 0) return m.substr(prefix.size());
    return "";
}

int main(int argc, char** argv) {
    VerilatedContext* ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);

    std::string wave = plusarg(ctx, "wave");
    std::string maxc = plusarg(ctx, "max-cycles");
    uint64_t max_cycles = maxc.empty() ? 50000000 : strtoull(maxc.c_str(), nullptr, 0);

    if (!wave.empty()) ctx->traceEverOn(true);
    Vsoc* dut = new Vsoc{ctx};

    VerilatedFstC* tfp = nullptr;
    if (!wave.empty()) {
        tfp = new VerilatedFstC;
        dut->trace(tfp, 99);
        tfp->open(wave.c_str());
    }

    auto tick = [&]() {
        dut->clk = 0; dut->eval();
        if (tfp) tfp->dump(ctx->time());
        ctx->timeInc(1);
        dut->clk = 1; dut->eval();
        if (tfp) tfp->dump(ctx->time());
        ctx->timeInc(1);
    };

    // hold reset for 2 cycles
    dut->rst = 1;
    tick(); tick();
    dut->rst = 0;

    uint64_t cycles = 0;
    while (!dut->done && cycles < max_cycles && !ctx->gotFinish()) {
        tick();
        cycles++;
    }

    // Let the pipeline drain so the last instructions reach WB and show up
    // in the trace (the SoC ignores I/O once done is set).
    if (dut->done)
        for (int i = 0; i < 200; i++) tick();

    int rc;
    fflush(stdout);
    if (!dut->done) {
        printf("FAIL: timeout after %llu cycles\n", (unsigned long long)cycles);
        rc = 2;
    } else if (dut->exit_code == 1) {
        printf("PASS (%llu cycles)\n", (unsigned long long)cycles);
        rc = 0;
    } else if (dut->exit_code == 0xFFFFFFFFu) {
        printf("FAIL: illegal instruction at pc=%08x\n", dut->fault_pc);
        rc = 3;
    } else if (dut->exit_code == 0xFFFFFFFEu) {
        printf("FAIL: misaligned access to %08x at pc=%08x\n", dut->fault_addr_q, dut->fault_pc);
        rc = 4;
    } else {
        printf("FAIL: test %u (exit code %08x) after %llu cycles\n",
               dut->exit_code >> 1, dut->exit_code, (unsigned long long)cycles);
        rc = 1;
    }

    if (tfp) tfp->close();
    dut->final();
    delete dut;
    delete ctx;
    return rc;
}
