# Bug log

Anything that took more than ~30 min: symptom, how I found it, fix.

## M0 – Verilator can't find the testbench
- **Symptom:** `No rule to make target 'tb/tb_counter.cpp'`
- **Cause:** with `--Mdir build/obj_x`, Verilator's generated makefile runs from inside that folder, so relative `.cpp` paths break.
- **Fix:** pass the testbench path through `$(abspath ...)` in the Makefile.

## M0 – Space in folder path breaks make
- **Symptom:** `Cannot find file containing module: '/Users/Abhi/Documents/RISC-V'`
- **Cause:** project lived in "RISC-V project"; make splits paths on spaces.
- **Fix:** renamed the folder to `RISC-V-project`. Rule: no spaces anywhere in the path.

## M0 – `lz4.h` not found on macOS
- **Symptom:** `fstcpp_writer.cpp: fatal error: 'lz4.h' file not found` (Verilator 5.052, Homebrew)
- **Cause:** Verilator's FST trace writer uses lz4, but the Homebrew bottle doesn't pull it in, and Apple clang doesn't search /opt/homebrew/include.
- **Fix:** `brew install lz4`, and the Makefile passes `-I$(brew --prefix)/include` and `-L.../lib -llz4` to Verilator's C++ build.

## M0 – "permission denied: Makefile"
- **Symptom:** appending to the Makefile failed with `zsh: permission denied`.
- **Cause:** a few files came out of the zip read-only.
- **Fix:** `chmod -R u+w .` in the project folder.

## M2 – Combinational loop through the register file bypass
- **Symptom:** Verilator `%Warning-UNOPTFLAT: Circular combinational logic: 'soc.u_core.wb_data'` the first time the single-cycle core was built.
- **Cause:** the regfile bypass returns `wdata` when a register is read and written in the same cycle. In a single-cycle core, `addi a0, a0, 1` reads and writes a0 in the same cycle, so wb_data → bypass → rs1 → ALU → wb_data is a real loop. In hardware that's an oscillator or a latch, not just a lint warning.
- **Fix:** made the bypass a parameter (`regfile #(.BYPASS(0))` in the single-cycle core). The pipeline will turn it on, because there the reader (ID) and the writer (WB) are different instructions.

## M2 – JALR test didn't catch a missing "clear bit 0"
- **Symptom:** I broke JALR on purpose (didn't clear bit 0 of the target) and every program still passed.
- **Cause:** the RAM ignores address bits [1:0], so fetching from `func+1` returns the same word as `func`. The PC was wrong, but you couldn't see it from the results.
- **Fix:** `func` in mix.S now reads its own PC with `auipc` and compares it with its real address. The mutation now fails test 6. Lesson: break things on purpose to check that the test can actually see the bug.

## M4 – `fence.i` doesn't assemble
- **Symptom:** `unrecognized opcode 'fence.i', extension 'zifencei' required` when building the rv32ui `fence_i` test.
- **Cause:** newer GCC split FENCE.I out of the base ISA into the Zifencei extension.
- **Fix:** build everything with `-march=rv32i_zifencei`.

## M5 – Traces diverge at the cycle counter
- **Symptom:** first run of the trace comparison: pipeline vs single-cycle differed in `hello` and `mix`, both at a `lw` from `0x1000_0004`.
- **Cause:** not a CPU bug. The pipeline takes more cycles, so the cycle counter really is different, and everything that depends on it (printed digits, branches) diverges.
- **Fix:** `+det-counters` simulator switch: every counter read returns the number of counter reads before it. That's deterministic and the same on every core, so traces line up. Benchmarks run without it.

## M5 – Verilator `-G` parameters are 32 bits
- **Symptom:** `%Warning-WIDTHTRUNC: ... 'PIPELINE' expects 1 bits ... CONST '32'h1'`
- **Cause:** `-GPIPELINE=1` passes a 32-bit integer and the parameter was declared `bit`.
- **Fix:** declared the configuration parameters as `int`.

## M9 – Newer Verilator rejects `bit trace_stop = 0;`
- **Symptom:** on my Mac (Verilator 5.052): `%Warning-PROCASSINIT: Procedural assignment to declaration with initial value: 'trace_stop'`. Everything passed on 5.020.
- **Cause:** a variable with an initializer in its declaration that's also assigned in an `always_ff`. In simulation it's fine, but for hardware the initial value and the reset are two different mechanisms, so newer Verilator flags it.
- **Fix:** no initializers on process-assigned variables. They're set by reset in the always_ff (or at the top of the `initial` block for file handles). I built Verilator 5.052 from source to run the whole suite on the same version as the Mac.
