# Milestones 0–1: counter, ALU, register file

Status: done. `make test` passes all three with `-Wall` and no lint waivers.

## Files

| File | What it is |
|---|---|
| `rtl/counter.sv` | 8-bit counter, sync reset, enable. Only exists to prove the Verilator → FST → Surfer flow works. |
| `rtl/riscv_pkg.sv` | Package holding `alu_op_e`. Every module imports this so op codes are defined once. |
| `rtl/alu.sv` | Combinational ALU, 11 ops (10 RV32I ops + `PASS_B` for LUI). |
| `rtl/regfile.sv` | 31 real registers (x1–x31), 2 read ports, 1 write port, write-through bypass. |
| `tb/tb_*.cpp` | Self-checking C++ testbenches. Exit code 1 on any mismatch so `make` stops. |

## Design decisions (be ready to explain these)

**ALU op encoding is my own, not funct3/funct7.** The decoder maps instruction bits to `alu_op_e`. That keeps the ALU simple and means ops like ADD can be reused for address calculation (loads/stores), AUIPC and JALR without the ALU knowing about instruction formats.

**Shifts use `b[4:0]` only.** The RV32I spec says the shift amount is the low 5 bits of rs2 (or the shamt field for immediates). Shifting by 32 must behave like shifting by 0, and the tests check that.

**SRA:** `$signed(a) >>> shamt`. `>>>` only does an arithmetic shift if the left operand is signed. That's a classic Verilog bug, and it's why the `$signed` cast is there. The result is cast back with `$unsigned` to keep lint quiet.

**SLT vs SLTU:** the only difference is the `$signed` casts. I checked the testbench catches this by swapping SLT to an unsigned compare: 5030 failures, e.g. `0x80000000 < 0` should be 1 when signed.

**No storage for x0.** The array is `regs[1:31]`. x0 reads are a hardwired 0, and writes to x0 are gated off. That's cheaper and harder to get wrong than storing a register and forcing it to 0.

**Write-through bypass in the register file.** If WB writes register r in the same cycle ID reads r, the read returns `wdata` instead of the old value. In the 5-stage pipeline, an instruction 3 behind a producer reads the register in ID while the producer is in WB. Without the bypass I'd need a third forwarding path. Removing the bypass made the regfile test fail 614 times, so the test covers it.

*Update from M2:* the bypass is now a parameter (`BYPASS`), and the single-cycle core turns it off. In that core, the reader and the writer are the same instruction, so the bypass created a combinational loop. See `bugs.md`.

## Verification approach

- **ALU:** every op × every pair from 10 edge values (0, 1, 2, 31, 32, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 0xFFFFFFFE, one "random-looking" value). Then 10,000 random vectors per op, compared with a C++ reference function. 111,100 checks total.
- **Regfile:** fill all registers, write junk to x0, test the same-cycle write/read, then 20,000 random cycles checked against a shadow array in C++.
- **Mutation check:** I broke SLT and removed the bypass on purpose to make sure the tests fail. Both did, so the tests actually test something.

## Likely interview questions

- *Why is the ALU combinational?* Every RV32I ALU op finishes in one cycle. Registering it would add a pipeline stage for no reason.
- *What does `unique case` do?* It tells the tool the cases are mutually exclusive and complete. Simulators warn if no case matches, and synthesis can build a parallel mux instead of a priority chain.
- *How would you handle x0 in a pipeline?* The regfile never writes it, and the forwarding logic must also check `rd != 0`. Otherwise an instruction writing x0 would forward a nonzero value.
- *Why C++ testbenches instead of SV?* Verilator compiles the RTL to C++, so the reference model is just C++ code. It's fast (the whole suite runs in a second), and a nonzero exit code plugs into `make` and CI.

## To run

```
make test          # counter + alu + regfile
make wave T=alu    # (counter and regfile dump FST; alu is combinational, no clock)
make wave T=regfile
```
