VERILATOR := verilator
VFLAGS    := --cc --exe --build --trace-fst -Wall -j 0 -Irtl

# RISC-V toolchain prefix: Homebrew calls it riscv64-elf-, Ubuntu riscv64-unknown-elf-
RV ?= $(shell command -v riscv64-elf-gcc >/dev/null 2>&1 && echo riscv64-elf- || echo riscv64-unknown-elf-)

# ---------------------------------------------------------------- unit tests
# $(call unit,top_module,rtl files,tb file)
define unit
	@mkdir -p build
	$(VERILATOR) $(VFLAGS) --Mdir build/obj_$(1) --top-module $(1) $(2) $(abspath $(3)) -o V$(1)
	./build/obj_$(1)/V$(1)
endef

.PHONY: test unit counter alu regfile immgen progs run wave clean

test: unit progs
	@echo "== all tests passed =="

unit: counter alu regfile immgen

counter:
	$(call unit,counter,rtl/counter.sv,tb/tb_counter.cpp)

alu:
	$(call unit,alu,rtl/riscv_pkg.sv rtl/alu.sv,tb/tb_alu.cpp)

regfile:
	$(call unit,regfile,rtl/regfile.sv,tb/tb_regfile.cpp)

immgen:
	$(call unit,immgen,rtl/riscv_pkg.sv rtl/immgen.sv,tb/tb_immgen.cpp)

# ---------------------------------------------------------------- full CPU
SOC_RTL := rtl/riscv_pkg.sv rtl/alu.sv rtl/regfile.sv rtl/immgen.sv rtl/decoder.sv \
           rtl/ram.sv rtl/core_single.sv rtl/soc.sv
SIM     := build/obj_soc/Vsoc

$(SIM): $(SOC_RTL) tb/tb_soc.cpp
	@mkdir -p build
	$(VERILATOR) $(VFLAGS) --Mdir build/obj_soc --top-module soc $(SOC_RTL) $(abspath tb/tb_soc.cpp) -o Vsoc

# ---------------------------------------------------------------- software
SWB     := build/sw
ASFLAGS := -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -static \
           -Isw/include -T sw/linker.ld -Wl,--no-warn-rwx-segments

$(SWB)/%.elf: sw/programs/%.S sw/linker.ld sw/include/test_macros.h
	@mkdir -p $(SWB)
	$(RV)gcc $(ASFLAGS) $< -o $@

# .hex for the RAM, plus a disassembly next to it for debugging
$(SWB)/%.hex: $(SWB)/%.elf scripts/bin2hex.py
	$(RV)objcopy -O binary $< $(SWB)/$*.bin
	python3 scripts/bin2hex.py $(SWB)/$*.bin $@
	$(RV)objdump -d $< > $(SWB)/$*.dis

.PRECIOUS: $(SWB)/%.elf $(SWB)/%.hex

PROGS := sum fib memcpy mix

# run every program, stop at the first failure
progs: $(SIM) $(foreach p,$(PROGS),$(SWB)/$(p).hex)
	@for p in $(PROGS); do \
		printf "%-8s " $$p; \
		./$(SIM) +hex=$(SWB)/$$p.hex +trace=$(SWB)/$$p.trace || exit 1; \
	done

# make run PROG=fib        (add WAVE=1 to dump build/sw/fib.fst)
PROG ?= sum
run: $(SIM) $(SWB)/$(PROG).hex
	./$(SIM) +hex=$(SWB)/$(PROG).hex +trace=$(SWB)/$(PROG).trace $(if $(WAVE),+wave=$(SWB)/$(PROG).fst)

# make wave T=regfile   or   make wave T=sw/fib   (after make run PROG=fib WAVE=1)
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
