// sum.S - add 1..100, expect 5050.
// Exercises: addi, add, branch loop.
#include "test_macros.h"

    .section .text.init
    .globl _start
_start:
    li   a0, 0          // sum
    li   a1, 1          // i
    li   a2, 101        // loop bound
loop:
    add  a0, a0, a1
    addi a1, a1, 1
    blt  a1, a2, loop

    CHECK a0, 5050, 1
    CHECK a1, 101,  2   // loop ran exactly 100 times

    // same sum counting down with bne, to hit a different branch
    li   a3, 0
    li   a4, 100
down:
    add  a3, a3, a4
    addi a4, a4, -1
    bne  a4, zero, down
    CHECK a3, 5050, 3

    TEST_PASS
