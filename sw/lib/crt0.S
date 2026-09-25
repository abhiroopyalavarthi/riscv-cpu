// crt0.S - C startup. Runs before main():
//   1. set up the stack pointer (top of RAM, from the linker script)
//   2. zero .bss (C expects globals without an initializer to be 0)
//   3. call main
//   4. report main's return value: 0 -> pass (1), n -> (n<<1)|1
    .section .text.init
    .globl _start
_start:
    la   sp, __stack_top

    la   t0, __bss_start
    la   t1, __bss_end
1:  bgeu t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b
2:
    call main

    slli a0, a0, 1
    ori  a0, a0, 1          // main returned 0 -> 1 = pass
    li   t0, 0x10000008
    sw   a0, 0(t0)
3:  j    3b
