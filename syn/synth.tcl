# ============================================================================
# synth.tcl - Vivado non-project synthesis for both designs
# ============================================================================
# Run from anywhere (paths are relative to this script):
#     vivado -mode batch -source syn/synth.tcl
#
# For each top (systolic_mm and mac_baseline) it:
#   1. reads the RTL and the 100 MHz clock constraint
#   2. runs synth_design in out-of-context mode. OOC means "this block lives
#      inside a bigger design", so Vivado does not try to put every port on a
#      package pin (our buses are 256 + 256 + 512 bits wide - far more than
#      the 125 user I/O pins on the xc7z020clg400).
#   3. writes utilization and timing reports to syn/out/<top>/
#   4. pulls out LUTs, FFs, DSPs and WNS, and estimates Fmax
# A side-by-side summary is written to syn/out/summary.txt.
#
# Note: these are POST-SYNTHESIS numbers. Timing does not include routing
# delays yet, so the real Fmax after place & route will be somewhat lower.
# ============================================================================

set part      xc7z020clg400-1
set period_ns 10.0
set root      [file normalize [file join [file dirname [info script]] ..]]
set out_root  [file join $root syn out]
file mkdir $out_root

set designs {
    systolic_mm  {rtl/pe.sv rtl/skew_feeder.sv rtl/systolic_array.sv rtl/systolic_mm.sv}
    mac_baseline {rtl/mac_baseline.sv}
}

# Find the "Used" number on a line like "| Slice LUTs* | 123 | 0 | ..."
proc util_value {report label} {
    if {[regexp "\\|\\s*${label}\\s*\\|\\s*(\[0-9\]+)" $report -> value]} {
        return $value
    }
    return "?"
}

set summary {}

foreach {top files} $designs {
    puts "\n================ Synthesizing $top ================\n"
    set out_dir [file join $out_root $top]
    file mkdir $out_dir

    # Start from an empty in-memory design each time.
    close_project -quiet
    create_project -in_memory -part $part

    foreach f $files {
        read_verilog -sv [file join $root $f]
    }
    read_xdc [file join $root syn clock.xdc]

    synth_design -top $top -part $part -mode out_of_context

    # Full reports, for reading by hand
    report_utilization     -file [file join $out_dir utilization.rpt]
    report_timing_summary  -file [file join $out_dir timing_summary.rpt]
    report_timing -max_paths 5 -file [file join $out_dir critical_paths.rpt]

    # Numbers for the summary table
    set util [report_utilization -return_string]
    set luts [util_value $util {Slice LUTs\*?}]
    set ffs  [util_value $util {Slice Registers}]
    set dsps [util_value $util {DSPs}]

    set worst [get_timing_paths -max_paths 1 -nworst 1 -setup]
    if {[llength $worst] == 0} {
        set wns  "n/a"
        set fmax "n/a"
    } else {
        set wns  [get_property SLACK $worst]
        # The worst path takes (period - slack) ns, so that is the shortest
        # clock period this design could run at.
        set fmax [format "%.1f" [expr {1000.0 / ($period_ns - $wns)}]]
        set wns  [format "%.3f" $wns]
    }

    lappend summary [list $top $luts $ffs $dsps $wns $fmax]
}

# ------------------------------------------------------------------
# Print and save the summary table
# ------------------------------------------------------------------
set lines {}
lappend lines "Part: $part   Clock constraint: [format %.0f [expr {1000.0 / $period_ns}]] MHz ($period_ns ns)   Post-synthesis, out-of-context"
lappend lines ""
lappend lines [format "%-14s %8s %8s %6s %10s %12s" Design LUTs FFs DSPs "WNS (ns)" "Fmax (MHz)"]
lappend lines [string repeat "-" 63]
foreach row $summary {
    lassign $row top luts ffs dsps wns fmax
    lappend lines [format "%-14s %8s %8s %6s %10s %12s" $top $luts $ffs $dsps $wns $fmax]
}
set text [join $lines "\n"]

set fh [open [file join $out_root summary.txt] w]
puts $fh $text
close $fh

puts "\n$text\n"
puts "Reports written to $out_root"
