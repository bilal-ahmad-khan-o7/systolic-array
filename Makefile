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
RTL_MM  := rtl/pe.sv rtl/skew_feeder.sv rtl/systolic_array.sv rtl/systolic_mm.sv

.PHONY: test test_pe test_mm test_mac wave clean

test: test_pe test_mm test_mac
	@echo "All testbenches passed."

# Each test: compile, run, save the log, then fail the make if PASS is missing.
test_pe: $(BUILD)/tb_pe.vvp
	$(VVP) $< | tee $(BUILD)/tb_pe.log
	@grep -q '^PASS' $(BUILD)/tb_pe.log

$(BUILD)/tb_pe.vvp: $(RTL_PE) tb/tb_pe.sv | $(BUILD)
	$(IVERILOG) -o $@ $^

test_mm: $(BUILD)/tb_systolic_mm.vvp
	$(VVP) $< | tee $(BUILD)/tb_systolic_mm.log
	@grep -q '^PASS' $(BUILD)/tb_systolic_mm.log

$(BUILD)/tb_systolic_mm.vvp: $(RTL_MM) tb/tb_systolic_mm.sv tb/mm_tests.svh | $(BUILD)
	$(IVERILOG) -I tb -o $@ $(RTL_MM) tb/tb_systolic_mm.sv

test_mac: $(BUILD)/tb_mac_baseline.vvp
	$(VVP) $< | tee $(BUILD)/tb_mac_baseline.log
	@grep -q '^PASS' $(BUILD)/tb_mac_baseline.log

$(BUILD)/tb_mac_baseline.vvp: rtl/mac_baseline.sv tb/tb_mac_baseline.sv tb/mm_tests.svh | $(BUILD)
	$(IVERILOG) -I tb -o $@ rtl/mac_baseline.sv tb/tb_mac_baseline.sv

# The top-level test saves its first (walkthrough) run to a VCD file.
# tb/systolic_mm.gtkw opens it with the skew signals already on screen.
wave: test_mm
	gtkwave $(BUILD)/tb_systolic_mm.vcd tb/systolic_mm.gtkw &

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
