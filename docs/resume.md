# Resume / LinkedIn text

## Resume bullets (pick 2–3)

**RISC-V CPU (SystemVerilog, Verilator, C)** | github.com/abhiroopyalavarthi/riscv-cpu

- Designed a 5-stage pipelined RV32I processor in SystemVerilog with data forwarding, load-use stall detection and branch flush; passes 41/42 official riscv-tests (rv32ui) and runs GCC-compiled C programs.
- Verified the pipeline by differential testing against my own single-cycle reference core: over 1M retired instructions compared trace by trace across 4 configurations, plus 18 deliberately planted bugs to confirm test coverage.
- Added a 64-entry BTB with 2-bit counters, cutting pipeline CPI from 1.34 to 1.01 on sort (99% prediction accuracy), and parameterized direct-mapped I/D caches; measured hit rates and CPI at 256 B–4 KB.
- Wrote the bare-metal software stack: startup code, linker script, UART printing and software multiply/divide.

## One-line version

5-stage pipelined RISC-V (RV32I) CPU in SystemVerilog with forwarding, branch prediction (99% accuracy on sort) and caches; passes the official riscv-tests and matches a single-cycle reference on 1M+ instructions.

## 30-second explanation (for "tell me about a project")

"I built a RISC-V processor in SystemVerilog. I started with a single-cycle version that runs every RV32I instruction, then used it as a reference while I built a 5-stage pipeline with forwarding and hazard detection. Both cores write an instruction trace, and a script compares them line by line, so any pipeline bug shows up as the first differing instruction. Then I added a branch predictor and caches and measured the effect with performance counters: the predictor took CPI on a sort from 1.34 to about 1.0. It passes the official RISC-V test suite and runs C programs I compile with GCC."
