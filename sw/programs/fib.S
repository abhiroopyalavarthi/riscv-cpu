// fib.S - Fibonacci two ways.
//   1) iterative: fill fib[0..24] in memory, check a few entries with lw
//   2) recursive: fib(15) with a real stack frame (jal/jalr, sw/lw on sp)
#include "test_macros.h"

    .section .text.init
    .globl _start
_start:
    li   sp, 0x10000            // stack top = end of RAM

    // ---------- 1) iterative table ----------
    la   s0, table
    li   t0, 0                  // fib(i-2)
    li   t1, 1                  // fib(i-1)
    sw   t0, 0(s0)
    sw   t1, 4(s0)
    addi s1, s0, 8              // write pointer
    li   s2, 23                 // 23 more entries -> fib[2..24]
fill:
    add  t2, t0, t1
    sw   t2, 0(s1)
    mv   t0, t1
    mv   t1, t2
    addi s1, s1, 4
    addi s2, s2, -1
    bnez s2, fill

    lw   a0, 40(s0)             // fib[10]
    CHECK a0, 55, 1
    lw   a0, 80(s0)             // fib[20]
    CHECK a0, 6765, 2
    lw   a0, 96(s0)             // fib[24]
    CHECK a0, 46368, 3

    // ---------- 2) recursive ----------
    li   a0, 15
    call fib_rec
    CHECK a0, 610, 4
    li   t0, 0x10000
    CHECK sp, 0x10000, 5        // stack balanced after all the calls

    TEST_PASS

// a0 = fib(a0), naive recursion
fib_rec:
    li   t0, 2
    blt  a0, t0, fib_base       // fib(0)=0, fib(1)=1
    addi sp, sp, -12
    sw   ra, 8(sp)
    sw   s0, 4(sp)
    sw   s1, 0(sp)
    mv   s0, a0
    addi a0, s0, -1
    call fib_rec                // fib(n-1)
    mv   s1, a0
    addi a0, s0, -2
    call fib_rec                // fib(n-2)
    add  a0, a0, s1
    lw   s1, 0(sp)
    lw   s0, 4(sp)
    lw   ra, 8(sp)
    addi sp, sp, 12
fib_base:
    ret

    .section .bss
    .align 2
table:
    .space 25 * 4
