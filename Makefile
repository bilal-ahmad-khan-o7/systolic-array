# ============================================================================
# Makefile - simulation with Icarus Verilog
#   make test   : build and run every testbench, stop on the first FAIL
#   make wave   : run the top-level test and open the waveform in GTKWave
#   make clean  : delete build outputs
# ============================================================================

IVERILOG := iverilog -g2012 -Wall
VVP      := vvp -n
BUILD    := build

RTL_PE  := rtl/pe.sv

.PHONY: test test_pe clean

test: test_pe
	@echo "All testbenches passed."

# Each test: compile, run, save the log, then fail the make if PASS is missing.
test_pe: $(BUILD)/tb_pe.vvp
	$(VVP) $< | tee $(BUILD)/tb_pe.log
	@grep -q '^PASS' $(BUILD)/tb_pe.log

$(BUILD)/tb_pe.vvp: $(RTL_PE) tb/tb_pe.sv | $(BUILD)
	$(IVERILOG) -o $@ $^

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
