// mix.S - the instructions the other three programs don't really stress:
// LUI/AUIPC, JAL/JALR link values, every branch type both ways, signed vs
// unsigned compares, shifts, x0, the UART and the cycle counter.
#include "test_macros.h"

// branch that must be taken
.macro BR_TAKEN op, a, b, n
    \op  \a, \b, 1f
    TEST_FAIL \n
1:
.endm

// branch that must fall through
.macro BR_NOT op, a, b, n
    \op  \a, \b, 2f
    j    3f
2:  TEST_FAIL \n
3:
.endm

    // keep the linker from rewriting lui/addi pairs - this test cares
    // about exact instruction addresses
    .option norelax

    .section .text.init
    .globl _start
_start:
    // ---------- LUI / AUIPC ----------
    lui  a0, 0x12345
    CHECK a0, 0x12345000, 1

    // auipc result vs. the label's absolute address (built with lui/addi,
    // so it doesn't depend on auipc itself)
here:
    auipc a1, 0
    lui  a2, %hi(here)
    addi a2, a2, %lo(here)
    bne  a1, a2, fail_auipc

here2:
    auipc a1, 1                   // pc + 0x1000
    lui  a2, %hi(here2 + 0x1000)
    addi a2, a2, %lo(here2 + 0x1000)
    bne  a1, a2, fail_auipc

    // ---------- JAL link value ----------
    jal  ra, after_jal
ret_point:
    j    fail_jal                 // must never fall into this
after_jal:
    lui  a2, %hi(ret_point)
    addi a2, a2, %lo(ret_point)
    bne  ra, a2, fail_jal

    // ---------- JALR: call through a register, return with ret ----------
    li   a3, 0
    lui  t0, %hi(func)
    addi t0, t0, %lo(func)
    jalr ra, 0(t0)
    CHECK a3, 42, 4

    // JALR must clear bit 0 of the target. The RAM ignores the low address
    // bits, so a wrong PC still fetches the right instruction - func checks
    // its own PC with auipc to catch that.
    li   a3, 0
    jalr ra, 1(t0)
    CHECK a3, 42, 5
    CHECK a4, 0, 6                // a4 = func's PC minus its real address

    // ---------- branches ----------
    li   s0, -1                   // 0xFFFFFFFF: smallest signed, biggest unsigned
    li   s1, 1
    li   s2, 1

    BR_TAKEN beq,  s1, s2, 10
    BR_NOT   beq,  s0, s1, 11
    BR_TAKEN bne,  s0, s1, 12
    BR_NOT   bne,  s1, s2, 13
    BR_TAKEN blt,  s0, s1, 14     // -1 < 1 signed
    BR_NOT   blt,  s1, s0, 15
    BR_NOT   blt,  s1, s2, 16     // equal -> not less
    BR_TAKEN bge,  s1, s0, 17
    BR_TAKEN bge,  s1, s2, 18     // equal counts as >=
    BR_NOT   bge,  s0, s1, 19
    BR_TAKEN bltu, s1, s0, 20     // 1 < 0xFFFFFFFF unsigned
    BR_NOT   bltu, s0, s1, 21
    BR_TAKEN bgeu, s0, s1, 22
    BR_NOT   bgeu, s1, s0, 23

    // backward taken branch (negative B-immediate)
    li   t0, 3
back:
    addi t0, t0, -1
    bnez t0, back
    CHECK t0, 0, 24

    // ---------- compares ----------
    slt  a0, s0, s1
    CHECK a0, 1, 30
    sltu a0, s0, s1
    CHECK a0, 0, 31
    slti a0, s1, -1
    CHECK a0, 0, 32
    sltiu a0, s1, -1              // imm sign-extends to 0xFFFFFFFF, then unsigned
    CHECK a0, 1, 33

    // ---------- shifts ----------
    li   a1, 0x80000010
    srai a0, a1, 4
    CHECK a0, 0xF8000001, 40
    srli a0, a1, 4
    CHECK a0, 0x08000001, 41
    slli a0, a1, 31
    CHECK a0, 0x00000000, 42
    li   a2, 33                   // register shifts only use the low 5 bits
    sll  a0, s1, a2
    CHECK a0, 2, 43
    li   a2, 4
    sra  a0, a1, a2
    CHECK a0, 0xF8000001, 44

    // ---------- logic, sub ----------
    li   a1, 0x0F0F00FF
    xori a0, a1, -1               // NOT
    CHECK a0, 0xF0F0FF00, 50
    andi a0, a1, 0x7F0
    CHECK a0, 0x000000F0, 51
    ori  a0, a1, 0x700
    CHECK a0, 0x0F0F07FF, 52
    sub  a0, s1, s0               // 1 - (-1)
    CHECK a0, 2, 53
    sub  a0, zero, s1
    CHECK a0, -1, 54

    // ---------- x0 stays zero ----------
    addi x0, x0, 5
    lui  x0, 0xFFFFF
    add  a0, x0, x0
    CHECK a0, 0, 60

    // ---------- cycle counter moves ----------
    li   t0, CYCLES
    lw   a0, 0(t0)
    nop
    nop
    lw   a1, 0(t0)
    bgeu a0, a1, fail_cycles

    // ---------- UART ----------
    PUTC 'O'
    PUTC 'K'
    PUTC '\n'

    TEST_PASS

fail_auipc:  TEST_FAIL 2
fail_jal:    TEST_FAIL 3
fail_cycles: TEST_FAIL 61

func:
    auipc a4, 0
    lui  a5, %hi(func)
    addi a5, a5, %lo(func)
    sub  a4, a4, a5               // 0 if we landed exactly on func
    li   a3, 42
    ret
