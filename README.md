# RV32I CPU in SystemVerilog

A 5-stage pipelined RISC-V (RV32I) processor, built and verified in Verilator. Work in progress: the single-cycle core runs hand-written assembly programs; the pipeline comes next.

## Status

- [x] M0 setup (counter, Verilator + FST flow)
- [x] M1 ALU + register file
- [x] M2 single-cycle core: all 40 RV32I instructions, 4 self-checking assembly programs
- [ ] M3 running C
- [ ] M4 rv32ui official tests
- [ ] M5 5-stage pipeline
- [ ] M6 performance baseline
- [ ] M7 branch predictor
- [ ] M8 caches
- [ ] M9 write-up

## Running

```
brew install verilator surfer lz4 riscv64-elf-gcc
make test                    # unit tests + every program on the CPU
make run PROG=fib            # one program; instruction trace in build/sw/fib.trace
make run PROG=fib WAVE=1     # plus a waveform: make wave T=sw/fib
```

## Layout

```
rtl/        SystemVerilog (core_single, decoder, immgen, alu, regfile, ram, soc)
tb/         Verilator C++ testbenches
sw/         linker script, test macros, assembly programs
scripts/    bin2hex.py
docs/       design notes per milestone, bug log, waveform screenshots
```

## Memory map

| Address | |
|---|---|
| `0x0000_0000 – 0x0000_FFFF` | 64 KB RAM, code at 0, stack from the top |
| `0x1000_0000` | UART TX (store a byte to print it) |
| `0x1000_0004` | cycle counter (read only) |
| `0x1000_0008` | test status: 1 = pass, `(n<<1)\|1` = test n failed; ends the simulation |
