VERILATOR := verilator
VFLAGS    := --cc --exe --build --trace-fst -Wall -j 0 -Irtl

# RISC-V toolchain prefix: Homebrew calls it riscv64-elf-, Ubuntu riscv64-unknown-elf-
RV ?= $(shell command -v riscv64-elf-gcc >/dev/null 2>&1 && echo riscv64-elf- || echo riscv64-unknown-elf-)

.PHONY: test unit counter alu regfile immgen sims progs rv32ui ctests compare bench run wave clean

# ======================================================================
# make test: everything that has to pass before a commit
# ======================================================================
TEST_CFGS := single pipe bp c1k

test: unit progs rv32ui ctests compare
	@echo "== all tests passed =="

# ======================================================================
# unit tests
# ======================================================================
# $(call unit,top_module,rtl files,tb file)
define unit
	@mkdir -p build
	$(VERILATOR) $(VFLAGS) --Mdir build/obj_$(1) --top-module $(1) $(2) $(abspath $(3)) -o V$(1)
	./build/obj_$(1)/V$(1)
endef

unit: counter alu regfile immgen

counter:
	$(call unit,counter,rtl/counter.sv,tb/tb_counter.cpp)

alu:
	$(call unit,alu,rtl/riscv_pkg.sv rtl/alu.sv,tb/tb_alu.cpp)

regfile:
	$(call unit,regfile,rtl/regfile.sv,tb/tb_regfile.cpp)

immgen:
	$(call unit,immgen,rtl/riscv_pkg.sv rtl/immgen.sv,tb/tb_immgen.cpp)

# ======================================================================
# CPU configurations - one simulator build each
# ======================================================================
SOC_RTL := rtl/riscv_pkg.sv rtl/alu.sv rtl/regfile.sv rtl/immgen.sv rtl/decoder.sv \
           rtl/ram.sv rtl/cache.sv rtl/core_single.sv rtl/core_pipe.sv rtl/soc.sv

CACHED    = -GPIPELINE=1 -GBP=1 -GICACHE_BYTES=$(1) -GDCACHE_BYTES=$(1) -GMISS_PENALTY=10
G_single := -GPIPELINE=0
G_pipe   := -GPIPELINE=1 -GBP=0
G_bp     := -GPIPELINE=1 -GBP=1
G_c256   := $(call CACHED,256)
G_c1k    := $(call CACHED,1024)
G_c4k    := $(call CACHED,4096)
ALL_CFGS := single pipe bp c256 c1k c4k

sim = build/sim_$(1)/Vsoc

build/sim_%/Vsoc: $(SOC_RTL) tb/tb_soc.cpp
	@mkdir -p build
	$(VERILATOR) $(VFLAGS) $(G_$*) --Mdir build/sim_$* --top-module soc $(SOC_RTL) $(abspath tb/tb_soc.cpp) -o Vsoc

sims: $(foreach c,$(ALL_CFGS),$(call sim,$(c)))

# ======================================================================
# software
# ======================================================================
SWB     := build/sw
ARCH    := -march=rv32i_zifencei -mabi=ilp32
LDFLAGS := -nostdlib -nostartfiles -static -T sw/linker.ld -Wl,--no-warn-rwx-segments
CFLAGS  := $(ARCH) -O2 -Wall -ffreestanding -fno-tree-loop-distribute-patterns -Isw/lib
CLIB    := sw/lib/crt0.S sw/lib/print.c sw/lib/muldiv.c sw/lib/string.c

# hand-written assembly tests
$(SWB)/%.elf: sw/programs/%.S sw/linker.ld sw/include/test_macros.h
	@mkdir -p $(SWB)
	$(RV)gcc $(ARCH) $(LDFLAGS) -Isw/include $< -o $@

# C programs (crt0 + tiny libc)
$(SWB)/%.elf: sw/c/%.c $(CLIB) sw/lib/io.h sw/linker.ld
	@mkdir -p $(SWB)
	$(RV)gcc $(CFLAGS) $(LDFLAGS) $(CLIB) $< -o $@

# official rv32ui tests, built against my tests/env/riscv_test.h
RVT := tests/riscv-tests/isa
build/rv32ui/%.elf: $(RVT)/rv32ui/%.S $(RVT)/rv64ui/%.S tests/env/riscv_test.h
	@mkdir -p build/rv32ui
	$(RV)gcc $(ARCH) $(LDFLAGS) -Itests/env -I$(RVT)/macros/scalar $< -o $@

# any .elf -> .hex for the RAM (+ disassembly next to it)
%.hex: %.elf scripts/bin2hex.py
	$(RV)objcopy -O binary $< $*.bin
	python3 scripts/bin2hex.py $*.bin $@
	$(RV)objdump -d $< > $*.dis

.PRECIOUS: %.elf %.hex

PROGS    := sum fib memcpy mix hazards
CPROGS   := hello
BENCH    := sort matmul crc32
RV32UI   := $(sort $(basename $(notdir $(wildcard $(RVT)/rv32ui/*.S))))

PROG_HEX   := $(foreach p,$(PROGS) $(CPROGS) $(BENCH),$(SWB)/$(p).hex)
RV32UI_HEX := $(foreach t,$(RV32UI),build/rv32ui/$(t).hex)

progs: $(foreach c,$(TEST_CFGS),$(call sim,$(c))) $(PROG_HEX)
	@echo "== assembly programs =="
	@for c in $(TEST_CFGS); do \
		bash scripts/run_progs.sh $$c $(foreach p,$(PROGS),$(SWB)/$(p).hex) || exit 1; \
	done

ctests: $(foreach c,$(TEST_CFGS),$(call sim,$(c))) $(PROG_HEX)
	@echo "== C programs =="
	@for c in $(TEST_CFGS); do \
		bash scripts/run_progs.sh $$c $(foreach p,$(CPROGS) $(BENCH),$(SWB)/$(p).hex) || exit 1; \
	done

rv32ui: $(foreach c,$(TEST_CFGS),$(call sim,$(c))) $(RV32UI_HEX)
	@echo "== riscv-tests rv32ui =="
	@for c in $(TEST_CFGS); do \
		mkdir -p build/trace/$$c; \
		bash scripts/run_rv32ui.sh build/sim_$$c/Vsoc build/rv32ui build/trace/$$c | tail -1 || exit 1; \
	done

# every pipelined config must retire exactly the same instructions with the
# same results as the single-cycle core
compare: progs ctests rv32ui
	@echo "== trace comparison against the single-cycle core =="
	@for c in $(filter-out single,$(TEST_CFGS)); do \
		python3 scripts/compare_traces.py build/trace/single build/trace/$$c || exit 1; \
	done

# ======================================================================
# benchmarks -> docs/results.md
# ======================================================================
bench: sims $(foreach b,$(BENCH),$(SWB)/$(b).hex)
	python3 scripts/bench.py $(ALL_CFGS) > docs/results.md
	@cat docs/results.md

# ======================================================================
# one program by hand
#   make run PROG=fib              (asm, C or benchmark name)
#   make run PROG=fib CFG=pipe     (any of: $(ALL_CFGS))
#   make run PROG=fib WAVE=1       then: make wave T=sw/fib
#   make run PROG=hazards PIPEVIEW=1   cycle-by-cycle pipeline chart
# ======================================================================
PROG ?= hello
CFG  ?= bp
run: $(call sim,$(CFG)) $(SWB)/$(PROG).hex
	./$(call sim,$(CFG)) +hex=$(SWB)/$(PROG).hex +trace=$(SWB)/$(PROG).trace $(if $(WAVE),+wave=$(SWB)/$(PROG).fst) $(if $(PIPEVIEW),+pipeview=$(SWB)/$(PROG).pipeview)

T ?= counter
wave:
	surfer build/$(T).fst

clean:
	rm -rf build

# macOS/Homebrew: Verilator's FST writer needs lz4 headers + lib
BREW := $(shell brew --prefix 2>/dev/null)
ifneq ($(BREW),)
VFLAGS += -CFLAGS -I$(BREW)/include -LDFLAGS "-L$(BREW)/lib -llz4"
endif
