VERILATOR := verilator
VFLAGS    := --cc --exe --build --trace-fst -Wall -j 0 -Irtl

# build one unit test: $(call unit,top_module,rtl files,tb file)
define unit
	@mkdir -p build
	$(VERILATOR) $(VFLAGS) --Mdir build/obj_$(1) --top-module $(1) $(2) $(abspath $(3)) -o V$(1)
	./build/obj_$(1)/V$(1)
endef

.PHONY: test counter alu regfile wave clean

test: counter alu regfile
	@echo "== all unit tests passed =="

counter:
	$(call unit,counter,rtl/counter.sv,tb/tb_counter.cpp)

alu:
	$(call unit,alu,rtl/riscv_pkg.sv rtl/alu.sv,tb/tb_alu.cpp)

regfile:
	$(call unit,regfile,rtl/regfile.sv,tb/tb_regfile.cpp)

# make wave T=regfile
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
