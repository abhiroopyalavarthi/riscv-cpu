// tb/tb_immgen.cpp - random instruction words through every immediate
// format, checked against a C++ decode written straight from the spec.
#include <cstdio>
#include <cstdint>
#include <random>
#include "verilated.h"
#include "Vimmgen.h"

enum { I, S, B, U, J };
static const char* names[] = {"I", "S", "B", "U", "J"};

static uint32_t bits(uint32_t x, int hi, int lo) { return (x >> lo) & ((1u << (hi - lo + 1)) - 1); }
static int32_t  sext(uint32_t x, int width) { return (int32_t)(x << (32 - width)) >> (32 - width); }

static uint32_t ref(int t, uint32_t in) {
    switch (t) {
        case I: return sext(bits(in, 31, 20), 12);
        case S: return sext((bits(in, 31, 25) << 5) | bits(in, 11, 7), 12);
        case B: return sext((bits(in, 31, 31) << 12) | (bits(in, 7, 7) << 11) |
                            (bits(in, 30, 25) << 5) | (bits(in, 11, 8) << 1), 13);
        case U: return in & 0xFFFFF000u;
        case J: return sext((bits(in, 31, 31) << 20) | (bits(in, 19, 12) << 12) |
                            (bits(in, 20, 20) << 11) | (bits(in, 30, 21) << 1), 21);
    }
    return 0;
}

int main(int argc, char** argv) {
    VerilatedContext* ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);
    Vimmgen* dut = new Vimmgen{ctx};

    std::mt19937 rng(2);
    int errors = 0, checks = 0;

    // a few hand-picked words: all zeros, all ones, only the sign bit
    const uint32_t fixed[] = {0x00000000, 0xFFFFFFFF, 0x80000000, 0x7FFFFFFF, 0x00000F80, 0x000FF000};

    for (int t = 0; t <= J; t++) {
        for (int k = 0; k < 20000 + 6; k++) {
            uint32_t in = (k < 6) ? fixed[k] : rng();
            dut->instr = in >> 7;          // port is instr[31:7]
            dut->imm_type = t;
            dut->eval();
            uint32_t exp = ref(t, in);
            checks++;
            if (dut->imm != exp) {
                if (errors < 20)
                    printf("FAIL %s-type instr=%08x got=%08x exp=%08x\n", names[t], in, dut->imm, exp);
                errors++;
            }
        }
    }

    dut->final();
    delete dut;
    delete ctx;
    if (errors) { printf("IMMGEN FAIL: %d / %d checks\n", errors, checks); return 1; }
    printf("IMMGEN PASS: %d checks\n", checks);
    return 0;
}
