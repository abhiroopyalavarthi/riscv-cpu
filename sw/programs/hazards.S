// hazards.S - one of each pipeline hazard, back to back, so they're easy to
// find in a waveform or with +pipeview:
//   make run PROG=hazards CFG=pipe PIPEVIEW=1   ->  build/sw/hazards.pipeview
#include "test_macros.h"

    .section .text.init
    .globl _start
_start:
    la   t0, value           // value = 40
    nop
    nop
    nop

    // 1) EX/MEM forwarding: a1 needs a0 from the instruction right before
    addi a0, zero, 5
    addi a1, a0, 1           // a1 = 6
    // 2) both paths at once: a0 from MEM/WB, a1 from EX/MEM
    add  a2, a0, a1          // a2 = 11

    // 3) load-use: a4 needs a3 the cycle after the load -> 1 bubble
    lw   a3, 0(t0)
    addi a4, a3, 2           // a4 = 42

    // 4) store data forwarding: sw needs a4 from the previous instruction
    addi a4, a4, 1           // 43
    sw   a4, 4(t0)
    lw   a5, 4(t0)           // 43

    // 5) taken branch: 2 wrong-path instructions get flushed
    beq  a0, a0, 1f
    addi a2, zero, -1        // flushed, must not happen
    addi a2, zero, -1        // flushed
1:
    CHECK a1, 6, 1
    CHECK a2, 11, 2
    CHECK a4, 43, 3
    CHECK a5, 43, 4
    TEST_PASS

    .section .data
    .align 2
value: .word 40
       .word 0
