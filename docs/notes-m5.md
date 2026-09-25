# Milestone 5: 5-stage pipeline

`rtl/core_pipe.sv`. Same ports as `core_single`, so `soc.sv` picks one with a parameter (`PIPELINE`).

## Stages and pipeline registers

```
      IF            ID               EX                 MEM             WB
  PC -> fetch | decode, reg read | ALU, branch  | load/store     | reg write
             IF/ID            ID/EX           EX/MEM           MEM/WB
```

Each pipeline register is a packed struct with a `valid` bit. A flushed or stalled slot just gets `valid = 0` (a bubble), so nothing downstream acts on it: no register write, no store, not counted as retired.

The decoder's `ctrl_t` struct travels down the pipeline as one field. That's the payoff for putting all control signals in one struct back in M2.

## Hazards

| Hazard | What the core does | Cost |
|---|---|---|
| ALU result needed by the next instruction | forward EX/MEM → EX | 0 cycles |
| ...by the one after that | forward MEM/WB → EX | 0 |
| ...3 instructions later | regfile write-through bypass (WB → ID) | 0 |
| Load result needed by the next instruction | stall IF and ID one cycle, bubble into EX, then forward MEM/WB | 1 cycle |
| Taken branch or jump (no predictor) | resolve in EX, flush IF/ID and ID/EX, restart fetch | 2 cycles |
| FENCE.I | always "mispredicts" to PC+4, so everything after it is refetched | 2 cycles |
| Cache miss (M8) | freeze the whole pipeline until the line arrives | penalty |

Details worth knowing:

- **Forwarding priority:** EX/MEM wins over MEM/WB. If two instructions in a row write a0, the consumer needs the newer one.
- **Never forward x0.** An instruction "writing" x0 must not forward its result. I planted this bug: 16 rv32ui tests failed.
- **Store data is forwarded too.** `addi a4, a4, 1` then `sw a4, 0(t0)`: the store's rs2 goes through the same forwarding mux. Also planted and caught (5 tests).
- **The load-use check only fires if the next instruction actually reads that register.** That's why the decoder has `use_rs1/use_rs2`. `lui a0, ...` right after `lw a0` has a garbage "rs1" field and shouldn't stall.
- **The regfile bypass is on here** (it was off in single-cycle, see `bugs.md`), because in the pipeline the reader (ID) and the writer (WB) are always different instructions.
- **Flush beats stall.** If a branch in EX redirects while ID wants to stall for a load-use, the ID instruction is on the wrong path anyway, so it gets flushed.

## Seeing it: `+pipeview`

`sw/programs/hazards.S` triggers each hazard in order. Run:

```
make run PROG=hazards CFG=pipe PIPEVIEW=1
cat build/sw/hazards.pipeview
```

```
cycle  IF        ID        EX        MEM       WB        events
    7  0000001c  00000018  00000014  00000010  0000000c  fwd x10<-EX/MEM
    8  00000020  0000001c  00000018  00000014  00000010  fwd x10<-MEM/WB fwd x11<-EX/MEM
    9  00000024  00000020  0000001c  00000018  00000014  STALL(load-use)
   10  00000024  00000020  --------  0000001c  00000018
   11  00000028  00000024  00000020  --------  0000001c  fwd x13<-MEM/WB
   ...
   15  00000038  00000034  00000030  0000002c  00000028  FLUSH->0000003c
   16  0000003c  --------  --------  00000030  0000002c
```

- cycle 7: `addi a1, a0, 1` (0x14) in EX gets a0 from `addi a0` (0x10) in MEM.
- cycle 8: `add a2, a0, a1` (0x18) gets a0 from WB and a1 from MEM.
- cycle 9–10: `lw a3` (0x1c) is in EX and `addi a4, a3, 2` (0x20) is in ID. IF and ID hold, EX gets a bubble (`--------`).
- cycle 11: the load is in WB, so the addi gets a3 from MEM/WB.
- cycle 15–16: `beq` (0x30) is taken in EX. The two instructions behind it (0x34, 0x38) become bubbles, and fetch restarts at 0x3c.

For the waveform version: `make run PROG=hazards CFG=pipe WAVE=1`, then `make wave T=sw/hazards`. Add `u_core.pc_f`, `ifid`, `idex`, `exmem`, `memwb`, `load_use` and `redirect` under `TOP.soc.g_pipe.u_core`, and screenshot cycles 7–16 for the README.

## Verification: differential testing against the single-cycle core

Both cores write the same trace format: one line per retired instruction with PC, instruction, register write and store. The single-cycle trace is printed as each instruction executes; the pipeline's is printed at WB. `scripts/compare_traces.py` diffs every trace:

```
pipe vs single: all 50 traces identical (1005156 instructions)
bp vs single:   all 50 traces identical (1005156 instructions)
c1k vs single:  all 50 traces identical (1005156 instructions)
```

That's every asm program, every C program, and all 41 rv32ui tests, compared instruction by instruction. If they ever differ, the script prints the first differing line, which is where the pipeline went wrong.

**Problem I hit:** programs that read the cycle counter got different values on each core (the pipeline takes more cycles), so the traces split at the first counter read. Fix: `+det-counters` makes every counter read return "how many counter reads came before this one". That's deterministic and the same on every core. `make test` always uses it for traces; `make bench` uses the real counters.

**Other detail:** the pipeline keeps running a few cycles after the "test done" store, so both cores stop tracing right after that store, and the testbench runs 200 extra cycles to let the pipeline drain.

## Bugs I planted to check the tests

| Planted bug | Caught by |
|---|---|
| No EX/MEM forwarding | 41/41 rv32ui fail, every program fails |
| No MEM/WB forwarding | 39 rv32ui fail |
| No load-use stall | lb/lbu/lh/lhu/lw/ld_st, memcpy, hello |
| IF/ID not flushed on a taken branch | all branch tests, jalr, fence_i |
| Store data not forwarded | sb/sh/sw/ld_st/st_ld |
| Forwarding from x0 | 16 rv32ui tests, mix |
| Predictor: only checks direction, not target (bp) | fib and hello (wrong return addresses) |
| D-cache not updated on a store hit (c1k) | sb/sh/sw/ld_st/st_ld, fib, memcpy |
| I-cache ignores FENCE.I (c1k) | fence_i, and only fence_i. Good reason to keep that test. |

## Limitations (honest answers if asked)

- RAM reads are combinational (same-cycle), which is fine in simulation. On an FPGA, block RAM has a registered read, so IF and MEM would need to present the address a cycle earlier (or add stages). That's the first thing I'd change to put this on an FPGA.
- Branches resolve in EX (2-cycle penalty). Moving the compare to ID would cut it to 1 cycle but adds a forwarding path into ID and lengthens the critical path.
- No exceptions/interrupts (no CSRs). An illegal instruction just stops the simulation, at WB so wrong-path garbage never triggers it.

## Interview questions

- *Why is the load-use penalty 1 cycle and not 0?* The load's data exists only at the end of MEM. The consumer needs it at the start of EX, which is the same cycle. So it waits one cycle and gets it from MEM/WB.
- *Why flush 2 instructions on a taken branch?* The branch resolves in EX. By then IF and ID already hold the next two sequential instructions.
- *How do you know the pipeline is correct and not just passing the tests?* Differential testing: over 1M instructions retire with identical PCs, register writes and stores compared to the single-cycle reference. Plus 9 planted bugs, all caught.
- *Where would you forward from WB?* I don't need a separate path. The regfile writes in the first half and reads in the second, conceptually: the write-through bypass returns the value being written.
