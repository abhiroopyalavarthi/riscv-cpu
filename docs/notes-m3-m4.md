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
rv32ui on build/sim_single/Vsoc: 41 passed, 0 failed, 1 trapped as expected (ma_data)
```

### How it's hooked up

- `tests/riscv-tests/` has the rv32ui tests copied from upstream (see `VERSION` for the commit, `LICENSE` is BSD). I copied only what's needed instead of adding a submodule, which keeps cloning and CI simple.
- Each test `#include`s `riscv_test.h`, the "environment". The upstream one sets up machine mode, trap vectors and `tohost`. My version in `tests/env/riscv_test.h` is about 40 lines:
  - `RVTEST_CODE_BEGIN` → just `_start:`
  - `RVTEST_PASS` → store 1 to `0x1000_0008`
  - `RVTEST_FAIL` → store `(gp << 1) | 1`, where `gp` holds the number of the failing test case. That's why a failure prints e.g. `FAIL: test 6`.
- `scripts/run_rv32ui.sh` runs all of them on one simulator build and exits nonzero if any fail.

### The 42nd test: `ma_data` (misaligned access)

`ma_data` does loads and stores at addresses that aren't aligned to their size, e.g. `lw` from `0x1001`. The spec gives a core two options: do the access in hardware (split it across two words), or raise an exception.

This core takes the second option, in the simplest form: both cores check the address in the load/store path (`addr_misaligned()` in `riscv_pkg.sv`). If a halfword isn't 2-byte aligned or a word isn't 4-byte aligned, the access is cancelled (no store, no register write), and the SoC stops the simulation:

```
FAIL: misaligned access to 000005c1 at pc=00000010
```

Before this check existed, the RAM just ignored the low address bits, so a misaligned `lw` silently returned the wrong word. That's the worst option, because a program would keep running with bad data.

`scripts/run_rv32ui.sh` expects `ma_data` to end in exactly this fault. Anything else, including passing, fails the run. I checked this by turning the detection off: the runner then reports `ma_data expected a misaligned fault, got: FAIL: test 1`.

Why not support it in hardware? Compilers never generate misaligned accesses for normal C (everything is aligned), and a word that crosses two memory words (or two cache lines) needs two accesses, which touches the load/store path, the D-cache and the stall logic. Not worth it for a case real programs don't hit. Every other rv32ui test passes, including `ld_st`/`st_ld` and `fence_i` (self-modifying code).

### Checking the suite catches bugs

I made SLTU compare signed on purpose: `sltu` and `sltiu` fail at test 6. The suite is also what caught the pipeline hazard bugs I planted in M5 (see `notes-m5.md`).

## Interview questions

- *Why 41/42?* "The last one is misaligned loads and stores. RISC-V lets you either support them in hardware or trap. I detect them and stop, like a trap, because compilers don't generate them and doing them in hardware means splitting an access into two, which gets messy with the cache. Before I added the check, the core silently returned the wrong word, which is the one thing you can't allow."
- *What happens between reset and `main`?* PC = 0 is `_start` in crt0: set `sp`, zero `.bss`, `call main`. There's no `.data` copy because the whole program (including `.data`) is loaded into RAM, not ROM.
- *How does `a * b` work on a CPU without a multiply instruction?* GCC emits `call __mulsi3`, my shift-and-add routine, about 32 loop iterations worst case. That's why `matmul` has so many branches (see results).
- *How do you know your CPU is RISC-V compliant?* It passes the official rv32ui suite: 41/42. The 42nd tests misaligned accesses; my core traps on those instead of doing them in hardware, which the spec allows, and the test runner checks that the trap happens. Plus every pipelined config matches the single-cycle core instruction for instruction on over 1M instructions.
