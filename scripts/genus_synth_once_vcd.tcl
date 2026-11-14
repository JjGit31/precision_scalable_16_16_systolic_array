# One-time Genus synthesis for the 16x16 systolic array at 3.333 ns.
# This creates ONE mapped DB reused by all three VCD power scenarios.

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set ROOT_DIR   [file normalize [file join $SCRIPT_DIR ..]]
set TOP        "precision_packed_systolic_array"

# Load either the institute's complete Genus setup or the TSMC Liberty file.
if {[info exists ::env(GENUS_SETUP_TCL)] && $::env(GENUS_SETUP_TCL) ne ""} {
    if {![file readable $::env(GENUS_SETUP_TCL)]} { error "GENUS_SETUP_TCL is not readable: $::env(GENUS_SETUP_TCL)" }
    source $::env(GENUS_SETUP_TCL)
} elseif {[info exists ::env(STD_CELL_LIB)] && $::env(STD_CELL_LIB) ne ""} {
    if {![file readable $::env(STD_CELL_LIB)]} { error "STD_CELL_LIB is not readable: $::env(STD_CELL_LIB)" }
    read_libs $::env(STD_CELL_LIB)
} else {
    error "Set GENUS_SETUP_TCL or STD_CELL_LIB before starting Genus."
}

set SDC_FILE [file join $ROOT_DIR constraints/array_3p333ns_vcd.sdc]
if {![file exists $SDC_FILE]} { error "SDC not found: $SDC_FILE" }
if {![info exists ::env(REPORT_ROOT)] || $::env(REPORT_ROOT) eq ""} { error "REPORT_ROOT is not set." }
if {![info exists ::env(SYNTH_DB)] || $::env(SYNTH_DB) eq ""} { error "SYNTH_DB is not set." }
set REPORT_ROOT [file normalize $::env(REPORT_ROOT)]
set DB_FILE [file normalize $::env(SYNTH_DB)]
file mkdir $REPORT_ROOT
file mkdir [file dirname $DB_FILE]
file copy -force $SDC_FILE [file join $REPORT_ROOT constraints_used.sdc]

set EFFORT "medium"
if {[info exists ::env(SYNTH_EFFORT)] && $::env(SYNTH_EFFORT) ne ""} { set EFFORT $::env(SYNTH_EFFORT) }

puts "============================================================"
puts "ONE-TIME ARRAY SYNTHESIS — 3.333 ns / VCD FLOW"
puts "TOP          : $TOP"
puts "CLOCK        : 3.333 ns (approximately 300 MHz)"
puts "SDC          : $SDC_FILE"
if {[info exists ::env(STD_CELL_LIB)] && $::env(STD_CELL_LIB) ne ""} {
    puts "LIBRARY      : $::env(STD_CELL_LIB)"
} else {
    puts "LIBRARY SETUP: $::env(GENUS_SETUP_TCL)"
}
puts "DATABASE     : $DB_FILE"
puts "REPORTS      : $REPORT_ROOT"
puts "EFFORT       : $EFFORT"
puts "============================================================"

read_hdl -sv [list \
    [file join $ROOT_DIR rtl actual_adder.v] \
    [file join $ROOT_DIR rtl parallel_precision_scalable_multiplier_pe.v] \
    [file join $ROOT_DIR rtl precision_scalable_mac_pe_en.v] \
    [file join $ROOT_DIR rtl precision_packed_tile_4x4.v] \
    [file join $ROOT_DIR rtl precision_packed_systolic_array.v] \
]

elaborate $TOP
check_design -unresolved
read_sdc $SDC_FILE

# Preserve the arithmetic/tile hierarchy to limit destructive flattening.
set_db / .merge_combinational_hier_instances false
set_db / .auto_ungroup none
set_db / .syn_generic_effort $EFFORT
set_db / .syn_map_effort     $EFFORT
set_db / .syn_opt_effort     $EFFORT

puts "GENERIC_SYNTHESIS_BEGIN"
syn_generic
puts "GENERIC_SYNTHESIS_DONE"

puts "TECHNOLOGY_MAPPING_BEGIN"
syn_map
puts "TECHNOLOGY_MAPPING_DONE"

puts "POST_MAP_OPTIMIZATION_BEGIN"
syn_opt
puts "POST_MAP_OPTIMIZATION_DONE"

report_area > [file join $REPORT_ROOT area.rpt]
report_timing -max_paths 50 > [file join $REPORT_ROOT timing.rpt]
report_qor > [file join $REPORT_ROOT qor.rpt]
write_hdl > [file join $ROOT_DIR netlist ${TOP}_mapped_[file tail $REPORT_ROOT].v]
write_sdc > [file join $ROOT_DIR netlist ${TOP}_used_[file tail $REPORT_ROOT].sdc]

puts "DATABASE_SAVE_BEGIN"
write_db -to_file $DB_FILE
if {![file exists $DB_FILE] || [file size $DB_FILE] == 0} { error "Expected Genus DB missing/empty: $DB_FILE" }
puts "GENUS_SYNTHESIS_DB_READY: $DB_FILE"
puts "GENUS_SYNTHESIS_REPORT_ROOT: $REPORT_ROOT"
