// memcpy.S - byte and word copies, plus every load/store width.
#include "test_macros.h"

#define NBYTES 64

    .section .text.init
    .globl _start
_start:
    // ---------- byte-by-byte copy src -> dst1 ----------
    la   a0, src
    la   a1, dst1
    li   a2, NBYTES
bcopy:
    lbu  t0, 0(a0)
    sb   t0, 0(a1)
    addi a0, a0, 1
    addi a1, a1, 1
    addi a2, a2, -1
    bnez a2, bcopy

    // ---------- word copy src -> dst2 ----------
    la   a0, src
    la   a1, dst2
    li   a2, NBYTES / 4
wcopy:
    lw   t0, 0(a0)
    sw   t0, 0(a1)
    addi a0, a0, 4
    addi a1, a1, 4
    addi a2, a2, -1
    bnez a2, wcopy

    // ---------- compare both copies with src ----------
    la   a0, src
    la   a1, dst1
    la   a3, dst2
    li   a2, NBYTES / 4
cmp:
    lw   t0, 0(a0)
    lw   t1, 0(a1)
    lw   t2, 0(a3)
    bne  t0, t1, bad_byte_copy
    bne  t0, t2, bad_word_copy
    addi a0, a0, 4
    addi a1, a1, 4
    addi a3, a3, 4
    addi a2, a2, -1
    bnez a2, cmp
    j    loads

bad_byte_copy:
    TEST_FAIL 1
bad_word_copy:
    TEST_FAIL 2

    // ---------- load widths / sign extension ----------
    // src word 0 is 0x80FF7F01 -> bytes (low to high): 01 7F FF 80
loads:
    la   s0, src
    lb   a0, 0(s0)
    CHECK a0, 0x00000001, 3
    lb   a0, 1(s0)
    CHECK a0, 0x0000007F, 4
    lb   a0, 2(s0)
    CHECK a0, 0xFFFFFFFF, 5
    lb   a0, 3(s0)
    CHECK a0, 0xFFFFFF80, 6
    lbu  a0, 3(s0)
    CHECK a0, 0x00000080, 7
    lh   a0, 0(s0)
    CHECK a0, 0x00007F01, 8
    lh   a0, 2(s0)
    CHECK a0, 0xFFFF80FF, 9
    lhu  a0, 2(s0)
    CHECK a0, 0x000080FF, 10

    // ---------- partial stores only touch their bytes ----------
    la   s1, dst1                 // dst1 word 0 is a copy of 0x80FF7F01
    li   t0, 0xABCD
    sh   t0, 2(s1)
    lw   a0, 0(s1)
    CHECK a0, 0xABCD7F01, 11
    li   t0, 0x55
    sb   t0, 1(s1)
    lw   a0, 0(s1)
    CHECK a0, 0xABCD5501, 12
    li   t0, 0x12345678
    sh   t0, 0(s1)                // only the low half (5678) should land
    lw   a0, 0(s1)
    CHECK a0, 0xABCD5678, 13

    TEST_PASS

    .section .data
    .align 2
src:
    .word 0x80FF7F01, 0x12345678, 0xDEADBEEF, 0x00000000
    .word 0xFFFFFFFF, 0x7FFFFFFF, 0x80000000, 0x0F0F0F0F
    .word 0x11111111, 0x22222222, 0x33333333, 0x44444444
    .word 0xCAFEF00D, 0xA5A5A5A5, 0x5A5A5A5A, 0x01020304

    .section .bss
    .align 2
dst1: .space NBYTES
dst2: .space NBYTES
