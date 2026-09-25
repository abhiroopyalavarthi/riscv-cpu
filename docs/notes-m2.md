# Milestone 2: single-cycle CPU

Status: done. `make test` runs the 4 unit tests plus 4 assembly programs on the full CPU. All pass.

```
sum      PASS (617 cycles)
fib      PASS (20900 cycles)
memcpy   PASS (704 cycles)
mix      OK
PASS (150 cycles)
```

## New files

| File | What it is |
|---|---|
| `rtl/riscv_pkg.sv` | Added opcodes, `ctrl_t` (all control signals in one struct), and helper functions for branch compare and load/store byte handling. |
| `rtl/immgen.sv` | Builds the 32-bit immediate for the I/S/B/U/J formats. |
| `rtl/decoder.sv` | Control unit: opcode/funct3/funct7 → `ctrl_t`. Flags illegal instructions. |
| `rtl/core_single.sv` | The datapath: PC, regfile, ALU, branch logic, load/store, writeback. Also writes the instruction trace. |
| `rtl/ram.sv` | 64 KB RAM with an instruction port and a data port. Byte-enable writes, loaded from `+hex=`. |
| `rtl/soc.sv` | Top level: core + RAM + I/O (UART, cycle counter, status register). |
| `tb/tb_soc.cpp` | Runs a program until it writes the status register. PASS/FAIL, timeout, illegal instruction. |
| `tb/tb_immgen.cpp` | 100k random checks of the immediate generator against a C++ decode of the spec. |
| `sw/linker.ld` | One 64 KB RAM region, `_start` at address 0. |
| `sw/include/test_macros.h` | `CHECK reg, value, n`, `TEST_PASS`, `TEST_FAIL n`, `PUTC`. |
| `sw/programs/*.S` | sum, fib, memcpy, mix (see below). |
| `scripts/bin2hex.py` | .bin → one 32-bit word per line for `$readmemh`. |

## How an instruction flows (single cycle)

```
PC ──► RAM (I port) ──► instr ──► decoder ──► ctrl_t
                          │
                          ├──► immgen ──► imm
                          └──► regfile ──► rs1_val, rs2_val
                                               │
         alu_a = alu_a_pc ? PC  : rs1_val      │
         alu_b = alu_b_imm? imm : rs2_val      ▼
                                   ALU ──► alu_y ──► RAM (D port) address
                                                       │
         wb_data = ALU / load_val / PC+4  ◄────────────┘
         next_pc = JALR ? alu_y & ~1 : (JAL | taken) ? PC+imm : PC+4
```

Everything between the PC register and the regfile write is combinational. The clock edge updates the PC, the regfile, and the RAM (stores).

## Design decisions (be ready to explain these)

**Control is one packed struct (`ctrl_t`).** The decoder fills it, and the datapath reads fields like `c.reg_we` and `c.alu_b_imm`. In the pipeline this matters: the whole struct moves down the pipeline registers as one signal instead of 12 separate wires.

**Branches get their own adder and comparator.** `pc + imm` for the target, and `branch_taken(rs1, rs2, funct3)` for the decision. The ALU isn't used for branches at all, so there's no "ALU does SUB and checks zero" trick. That also makes BLT/BLTU easy.

**AUIPC and LUI reuse the ALU.** AUIPC is `PC + imm` (ALU A = PC). LUI is `PASS_B` (result = imm). Only two small additions to the ALU for two whole instructions.

**JALR clears bit 0** of `rs1 + imm`, as the spec requires. The link value for JAL/JALR is `PC + 4` through a separate writeback option (`WB_PC4`).

**Stores replicate, byte enables select.** For SB the byte is copied into all 4 lanes (`{4{b}}`), and `be = 0001 << addr[1:0]` picks the lane that actually gets written. So there's no shifter on the store path. Loads do the reverse: read the whole word, pick the byte/half with `addr[1:0]`, then sign- or zero-extend.

**Illegal instructions stop the simulation.** The decoder flags unknown opcodes and bad funct3/funct7 combinations. `soc` ends the run and the testbench prints the PC. This saves a lot of time: jumping into data or getting the B-immediate wrong shows up right away, instead of as a weird timeout.

**FENCE, ECALL, EBREAK are NOPs.** One hart, no caches yet, no CSRs. They get real behavior only if I do the CSR/trap stretch goal.

**The register file bypass is off here.** See `bugs.md`: it made a combinational loop in a single-cycle design.

**Memory map / I/O** (in `soc.sv`): stores to `0x1000_0000` print a character, loads from `0x1000_0004` read the cycle counter, and a store to `0x1000_0008` ends the run (1 = pass, `(n<<1)|1` = test n failed). The same convention is used by riscv-tests, so Milestone 4 reuses it.

## Test programs

| Program | What it checks |
|---|---|
| `sum.S` | Loop 1..100 (= 5050) two ways: `blt` counting up, `bne` counting down. |
| `fib.S` | Fills a table of fib(0..24) with `sw`, checks entries with `lw`. Then recursive fib(15) = 610 with a real stack frame (`call`/`ret`, save/restore on `sp`), and checks `sp` is back where it started. |
| `memcpy.S` | 64-byte copy with `lbu/sb` and with `lw/sw`, compares both. Then every load width on `0x80FF7F01` (LB/LBU/LH/LHU sign extension) and partial stores (SH, SB) that must only change their own bytes. |
| `mix.S` | LUI, AUIPC, JAL/JALR link values, JALR clearing bit 0, every branch type both taken and not taken (with -1 vs 1 so signed and unsigned disagree), SLT/SLTU/SLTI/SLTIU, shifts (incl. shift by 33 = shift by 1), x0 staying 0, cycle counter increasing, UART output. |

Each program checks its own results and writes a test number on failure, so `FAIL: test 11` points straight at a line in the .S file.

## Verification: planting bugs on purpose

I broke the design in 8 ways to make sure the programs catch each one:

| Bug planted | Caught by |
|---|---|
| B-immediate bits in the wrong order | fib: illegal instruction (a branch landed in the wrong place) |
| LB zero-extends | memcpy test 5 |
| SH always writes the low half | memcpy test 11 |
| ADDI with a negative immediate decoded as SUB | sum: timeout (the loop counter never decreased) |
| BGE compares unsigned | mix test 17 |
| JALR doesn't clear bit 0 | mix test 6, but only after I improved the test (see `bugs.md`) |
| Invalid instruction word | testbench: `FAIL: illegal instruction at pc=00000008` |
| Infinite loop | testbench: `FAIL: timeout` |

## Debugging tools you now have

- **Trace:** `build/sw/<prog>.trace`, one line per instruction: `PC  instr  xN=value  mem[addr]=data`. Open it next to the disassembly.
- **Disassembly:** `build/sw/<prog>.dis`, generated automatically. Search for the PC from the trace.
- **Waveform:** `make run PROG=fib WAVE=1`, then `make wave T=sw/fib`.

Typical flow when a test fails: note the test number → find `CHECK ..., n` in the .S → find that PC in the .dis → look at the lines just before it in the .trace.

## Likely interview questions

- *Why build a single-cycle CPU first?* It's the simplest correct design, so it becomes the reference. When the pipeline breaks, I run the same program on both and diff the traces. The first differing line is the bug.
- *What limits the clock speed of a single-cycle CPU?* The longest path: instruction fetch → decode → regfile read → ALU (address) → data memory read → writeback mux → regfile setup. Every instruction pays for the load path even if it's just an ADD. That's the motivation for pipelining.
- *How are loads of a byte at address 3 handled?* The RAM reads the whole word at `addr & ~3`, then `load_extract` takes byte 3 (`w[31:24]`) and sign-extends for LB or zero-extends for LBU.
- *What happens on an illegal instruction?* The decoder zeroes the write enables so no state changes, and the SoC stops the simulation and reports the PC. A real CPU would take a trap (mcause = 2), which needs CSRs. That's a stretch goal.
- *Why not use `objcopy -O verilog`?* Its word-width and byte-order options changed across binutils versions, and the Mac and Linux toolchains gave different output. A 20-line Python script is predictable.

## To run

```
brew install riscv64-elf-gcc          # once
make test                             # unit tests + all 4 programs
make run PROG=memcpy CFG=single       # one program (trace in build/sw/memcpy.trace)
make run PROG=fib WAVE=1              # with waveform
make wave T=sw/fib
```
