// riscv_test.h - my test environment for the official riscv-tests.
//
// The upstream env (riscv-test-env) sets up machine mode, trap vectors and
// talks to the host through "tohost". This CPU has no CSRs or traps, so
// these macros replace all of that with the SoC's status register:
//   pass -> store 1 to 0x1000_0008
//   fail -> store (TESTNUM << 1) | 1, so the simulator can print which case failed
#ifndef RISCV_TEST_H
#define RISCV_TEST_H

#define RVTEST_RV32U  .macro init; .endm
#define RVTEST_RV64U  RVTEST_RV32U

#define TESTNUM gp

#define RVTEST_CODE_BEGIN       \
    .section .text.init;        \
    .align 6;                   \
    .globl _start;              \
_start:                         \
    li TESTNUM, 0;

#define RVTEST_CODE_END  unimp

#define RVTEST_PASS             \
    fence;                      \
    li   t5, 1;                 \
    li   t6, 0x10000008;        \
    sw   t5, 0(t6);             \
1:  j    1b;

#define RVTEST_FAIL             \
    fence;                      \
    slli t5, TESTNUM, 1;        \
    ori  t5, t5, 1;             \
    li   t6, 0x10000008;        \
    sw   t5, 0(t6);             \
1:  j    1b;

#define EXTRA_DATA

#define RVTEST_DATA_BEGIN       \
    EXTRA_DATA                  \
    .align 4;                   \
    .global begin_signature;    \
begin_signature:

#define RVTEST_DATA_END         \
    .align 4;                   \
    .global end_signature;      \
end_signature:

#endif
