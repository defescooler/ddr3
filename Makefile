# DDR3 controller regression: SIM=xcelium (default when xrun is on PATH) or SIM=verilator

SIM ?= $(if $(shell command -v xrun),xcelium,verilator)
TEST ?= mc_smoke_test
SEED ?= 1
TESTS ?= mc_smoke_test mc_page_test mc_refresh_test mc_rand_test
SEEDS ?= 1 2 3 4 5
PLUSARGS ?=
LOGS ?= logs

RTL := $(wildcard rtl/*.sv)
TB := $(wildcard tb/*.sv) tb/files.f
DPI := tb/ref_mem.cpp tb/jedec_check.cpp

# xcelium and imc
XRUN ?= xrun
# imc from PATH, else from the vManager install
IMC ?= $(or $(shell command -v imc),/tools/software/cadence/vmanager/latest/tools.lnx86/vmgr/bin/imc)
UVMHOME ?= CDNS-1.2
COV_WORK ?= cov_work
XRUN_FLAGS := -64bit -uvm -uvmhome $(UVMHOME) -timescale 1ns/1ps -f tb/files.f $(DPI) -top tb_top \
    -coverage all -covdut mc_top -covworkdir $(COV_WORK) -covscope mc -covoverwrite +UVM_NO_RELNOTES

# verilator
VERILATOR ?= verilator
VERILATOR_COVERAGE ?= $(VERILATOR)_coverage
UVM_CORE ?= third_party/uvm-core
UVM_VERSION ?= 2020.3.1
VBUILD ?= build/verilator
VFLAGS := --binary --timing --assert --coverage-user -Wno-fatal -Wno-lint -Wno-style \
    --timescale 1ns/1ps +define+UVM_NO_DPI +incdir+$(UVM_CORE)/src --top-module tb_top -Mdir $(VBUILD) -j 0

# one run: $(call RUN,<test>,<seed>), log in $(LOGS)/<test>_s<seed>.log
ifeq ($(SIM),xcelium)
RUN = $(XRUN) $(XRUN_FLAGS) -svseed $(2) -covtest $(1)_s$(2) +UVM_TESTNAME=$(1) $(PLUSARGS) \
    -l $(LOGS)/$(1)_s$(2).log > /dev/null 2>&1
BUILD_DEP :=
else ifeq ($(SIM),verilator)
RUN = $(VBUILD)/Vtb_top +UVM_TESTNAME=$(1) +verilator+seed+$(2) +UVM_NO_RELNOTES $(PLUSARGS) \
    +verilator+coverage+file+$(LOGS)/$(1)_s$(2).dat > $(LOGS)/$(1)_s$(2).log 2>&1
BUILD_DEP := $(VBUILD)/Vtb_top
else
$(error SIM must be xcelium or verilator)
endif

.PHONY: all lint build sim regress cov imc trace-check clean

all: regress

# RTL lint
lint:
	$(VERILATOR) --lint-only -Wall -Wno-UNUSEDPARAM --top-module mc_top rtl/mc_pkg.sv $(filter-out rtl/mc_pkg.sv,$(RTL))

$(UVM_CORE):
	git clone -q --depth 1 --branch $(UVM_VERSION) https://github.com/accellera-official/uvm-core.git $@

$(VBUILD)/Vtb_top: $(RTL) $(TB) $(DPI) | $(UVM_CORE)
	@mkdir -p $(VBUILD)
	$(VERILATOR) $(VFLAGS) $(UVM_CORE)/src/uvm_pkg.sv -f tb/files.f $(DPI)

build: $(BUILD_DEP)
ifeq ($(SIM),xcelium)
	$(XRUN) $(XRUN_FLAGS) -elaborate
endif

# one test
sim: $(BUILD_DEP)
	@mkdir -p $(LOGS)
	$(call RUN,$(TEST),$(SEED)); tail -n 25 $(LOGS)/$(TEST)_s$(SEED).log

# TESTS x SEEDS, pass = TEST PASSED in the log, non-zero exit on any failure
regress: $(BUILD_DEP)
	@mkdir -p $(LOGS); rm -f $(LOGS)/*.log $(LOGS)/*.dat; rm -rf $(COV_WORK); fail=0; \
	for t in $(TESTS); do for s in $(SEEDS); do \
	    $(call RUN,$${t},$${s}); \
	    if grep -q "TEST PASSED" $(LOGS)/$${t}_s$${s}.log; then r=PASS; \
	    else r=FAIL; fail=1; rm -rf $(LOGS)/$${t}_s$${s}.dat $(COV_WORK)/mc/$${t}_s$${s}; fi; \
	    printf "%-18s seed %-3s %s\n" $$t $$s $$r; \
	done; done; exit $$fail

# merged coverage of the passing runs in the last regression
cov:
ifeq ($(SIM),xcelium)
	$(IMC) -exec scripts/imc_cov.tcl
else
	$(VERILATOR_COVERAGE) -write $(LOGS)/merged.dat $(LOGS)/*_s*.dat > /dev/null
	python3 scripts/cov_report.py $(LOGS)/merged.dat
endif

# merged coverage in the IMC GUI
imc:
	$(IMC) -load $(abspath $(COV_WORK))/merged

# offline JEDEC check of a trace dumped with PLUSARGS=+dfi_trace=<file>
trace-check: build/jedec_trace
	./build/jedec_trace $(TRACE)

build/jedec_trace: tb/jedec_check.cpp
	@mkdir -p build
	$(CXX) -std=c++17 -O2 -DJEDEC_MAIN -o $@ $<

clean:
	rm -rf build $(LOGS) $(COV_WORK) xcelium.d xrun.* *.log *.key .simvision
