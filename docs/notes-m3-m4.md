# Milestones 3–4: running C, official tests

## M3: running C

`make run PROG=hello`:

```
Hello from my CPU
10! = 3628800
1000000 / 7 = 142857 rem 1
-12345 / 10 = -1234 rem -5
0xdeadbeef = deadbeef
cycles so far: 11851
PASS (14507 cycles)
```

### What's needed to run C on a bare CPU

| File | Why it exists |
|---|---|
| `sw/lib/crt0.S` | Runs before `main`: sets `sp` to the top of RAM, zeroes `.bss`, calls `main`, then writes main's return value to the status register (0 → pass). |
| `sw/linker.ld` | Already there from M2. Puts `.text.init` (crt0) at address 0 and defines `__bss_start/__bss_end/__stack_top` for crt0. |
| `sw/lib/print.c` + `io.h` | `putchar_`, `puts_`, `print_hex`, `print_dec`. No printf: it's big and would need a lot of libc. |
| `sw/lib/muldiv.c` | `__mulsi3`, `__divsi3`, `__udivsi3`, `__modsi3`, `__umodsi3`. RV32I has no multiply or divide, so GCC calls these for `*`, `/` and `%`. |
| `sw/lib/string.c` | `memcpy/memset/memmove/memcmp`. GCC may call them even when the code doesn't (struct copies, array init). |

Compile flags: `-march=rv32i_zifencei -mabi=ilp32 -O2 -ffreestanding -nostdlib -nostartfiles`. I also use `-fno-tree-loop-distribute-patterns`, which stops GCC from turning my own memset loop *into a call to memset* (infinite recursion).

### Decisions

- **My own mul/div instead of libgcc.** The Homebrew toolchain isn't guaranteed to ship an rv32i/ilp32 build of libgcc, and writing them is a good exercise anyway. Multiply is shift-and-add; divide is restoring division, one quotient bit per iteration. Division by zero follows the RISC-V spec (quotient = all ones, remainder = dividend), same as the M extension would.
- **muldiv.c can't use `*`, `/` or `%`**, or GCC would compile `__mulsi3` into a call to itself.
- **hello.c checks its own answers.** The inputs are `volatile` so GCC can't compute them at compile time; otherwise the test wouldn't exercise the software divide at all. If a result is wrong, `main` returns nonzero and the test fails.

## M4: official tests (riscv-tests rv32ui)

```
rv32ui on build/sim_single/Vsoc: 41 passed, 0 failed, skipped: ma_data
```

### How it's hooked up

- `tests/riscv-tests/` has the rv32ui tests copied from upstream (see `VERSION` for the commit, `LICENSE` is BSD). I copied only what's needed instead of adding a submodule, which keeps cloning and CI simple.
- Each test `#include`s `riscv_test.h`, the "environment". The upstream one sets up machine mode, trap vectors and `tohost`. My version in `tests/env/riscv_test.h` is about 40 lines:
  - `RVTEST_CODE_BEGIN` → just `_start:`
  - `RVTEST_PASS` → store 1 to `0x1000_0008`
  - `RVTEST_FAIL` → store `(gp << 1) | 1`, where `gp` holds the number of the failing test case. That's why a failure prints e.g. `FAIL: test 6`.
- `scripts/run_rv32ui.sh` runs all of them on one simulator build and exits nonzero if any fail.

### Skipped: `ma_data`

It tests misaligned loads/stores, and it expects either hardware support or a trap handler (it uses `mcause`/`mepc` CSRs). This core has neither. Every other rv32ui test passes, including `ld_st`/`st_ld` and `fence_i` (self-modifying code).

### Checking the suite catches bugs

I made SLTU compare signed on purpose: `sltu` and `sltiu` fail at test 6. The suite is also what caught the pipeline hazard bugs I planted in M5 (see `notes-m5.md`).

## Interview questions

- *What happens between reset and `main`?* PC = 0 is `_start` in crt0: set `sp`, zero `.bss`, `call main`. There's no `.data` copy because the whole program (including `.data`) is loaded into RAM, not ROM.
- *How does `a * b` work on a CPU without a multiply instruction?* GCC emits `call __mulsi3`, my shift-and-add routine, about 32 loop iterations worst case. That's why `matmul` has so many branches (see results).
- *How do you know your CPU is RISC-V compliant?* It passes the official rv32ui suite (41/42, the skip is misaligned-trap handling). Plus every pipelined config matches the single-cycle core instruction for instruction on over 1M instructions.
