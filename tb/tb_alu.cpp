// tb/tb_alu.cpp - checks every ALU op against a C++ reference model.
// Directed edge cases first, then 10k random vectors per op.
#include <cstdio>
#include <cstdint>
#include <random>
#include "verilated.h"
#include "Valu.h"

enum { ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND, PASS_B, NUM_OPS };
static const char* names[] = {"ADD","SUB","SLL","SLT","SLTU","XOR","SRL","SRA","OR","AND","PASS_B"};

static uint32_t ref(int op, uint32_t a, uint32_t b) {
    uint32_t sh = b & 31;
    switch (op) {
        case ADD:    return a + b;
        case SUB:    return a - b;
        case SLL:    return a << sh;
        case SLT:    return (int32_t)a < (int32_t)b;
        case SLTU:   return a < b;
        case XOR:    return a ^ b;
        case SRL:    return a >> sh;
        case SRA:    return (uint32_t)((int32_t)a >> sh);   // arithmetic on gcc/clang
        case OR:     return a | b;
        case AND:    return a & b;
        case PASS_B: return b;
    }
    return 0;
}

static Valu* dut;
static int errors = 0, checks = 0;

static void check(int op, uint32_t a, uint32_t b) {
    dut->op = op; dut->a = a; dut->b = b;
    dut->eval();
    uint32_t exp = ref(op, a, b);
    checks++;
    if (dut->y != exp) {
        if (errors < 20)
            printf("FAIL %-6s a=%08x b=%08x got=%08x exp=%08x\n", names[op], a, b, dut->y, exp);
        errors++;
    }
}

int main(int argc, char** argv) {
    VerilatedContext* ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);
    dut = new Valu{ctx};

    const uint32_t edge[] = {0, 1, 2, 31, 32, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 0xFFFFFFFE, 0x12345678};
    const int N = sizeof(edge) / sizeof(edge[0]);

    // every op on every pair of edge values - covers shift by 0/31/32,
    // signed vs unsigned compare with the sign bit set, overflow on add/sub
    for (int op = 0; op < NUM_OPS; op++)
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++)
                check(op, edge[i], edge[j]);

    std::mt19937 rng(306);
    for (int op = 0; op < NUM_OPS; op++)
        for (int k = 0; k < 10000; k++)
            check(op, rng(), rng());

    dut->final();
    delete dut;
    delete ctx;

    if (errors) { printf("ALU FAIL: %d / %d checks\n", errors, checks); return 1; }
    printf("ALU PASS: %d checks\n", checks);
    return 0;
}
