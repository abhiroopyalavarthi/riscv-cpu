# RV32I CPU in SystemVerilog

A 5-stage pipelined RISC-V (RV32I) processor, built and verified in Verilator. Work in progress.

## Status

- [x] M0 setup (counter, Verilator + FST flow)
- [x] M1 ALU + register file
- [ ] M2 single-cycle core
- [ ] M3 running C
- [ ] M4 rv32ui official tests
- [ ] M5 5-stage pipeline
- [ ] M6 performance baseline
- [ ] M7 branch predictor
- [ ] M8 caches
- [ ] M9 write-up

## Running

```
brew install verilator surfer riscv64-elf-gcc
make test
```
