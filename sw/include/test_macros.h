// Small macros for the hand-written assembly tests.
// Uses t4-t6 as scratch, so tests shouldn't keep values in those.

#define UART_TX  0x10000000
#define CYCLES   0x10000004
#define STATUS   0x10000008

// write 1 to the status register -> simulation ends with PASS
.macro TEST_PASS
    li   t6, STATUS
    li   t5, 1
    sw   t5, 0(t6)
99: j    99b
.endm

// end the simulation reporting test number n as failed
.macro TEST_FAIL n
    li   t6, STATUS
    li   t5, ((\n) << 1) | 1
    sw   t5, 0(t6)
97: j    97b
.endm

// if reg != expected, fail with test number n
.macro CHECK reg, expected, n
    li   t4, \expected
    beq  \reg, t4, 98f
    TEST_FAIL \n
98:
.endm

// print one character on the UART
.macro PUTC ch
    li   t6, UART_TX
    li   t5, \ch
    sb   t5, 0(t6)
.endm
