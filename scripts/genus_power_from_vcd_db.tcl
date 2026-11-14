# Read one full-chip RTL VCD and annotate the already-mapped 3.333 ns design.
# This script performs NO RTL read/elaboration/synthesis/mapping/optimization.

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set ROOT_DIR [file normalize [file join $SCRIPT_DIR ..]]
if {![info exists ::env(SYNTH_DB)] || $::env(SYNTH_DB) eq ""} { error "SYNTH_DB is not set." }
if {![info exists ::env(VCD_FILE)] || $::env(VCD_FILE) eq ""} { error "VCD_FILE is not set." }
if {![info exists ::env(REPORT_ROOT)] || $::env(REPORT_ROOT) eq ""} { error "REPORT_ROOT is not set." }
set DB_FILE [file normalize $::env(SYNTH_DB)]
set VCD_FILE [file normalize $::env(VCD_FILE)]
set REPORT_ROOT [file normalize $::env(REPORT_ROOT)]
if {![file exists $DB_FILE] || [file size $DB_FILE] == 0} { error "Mapped DB missing/empty: $DB_FILE" }
if {![file exists $VCD_FILE] || [file size $VCD_FILE] == 0} { error "VCD missing/empty: $VCD_FILE" }

set REPORT_TAG "vcd_power"
if {[info exists ::env(REPORT_TAG)] && $::env(REPORT_TAG) ne ""} { set REPORT_TAG $::env(REPORT_TAG) }
set OUT_DIR [file join $REPORT_ROOT $REPORT_TAG]
file mkdir $OUT_DIR

puts "============================================================"
puts "GENUS VCD POWER-ONLY RUN"
puts "DB          : $DB_FILE"
puts "VCD         : $VCD_FILE"
puts "VCD SCOPE   : tb_array_vcd16/dut"
puts "REPORTS     : $OUT_DIR"
puts "============================================================"

read_db $DB_FILE
# VCD contains the testbench wrapper; map its DUT subtree to the Genus top.
# With no -instance option, Genus annotates the current design root.
read_vcd -static -vcd_scope tb_array_vcd16/dut $VCD_FILE
puts "READ_VCD_COMMAND_COMPLETED"

report_power > [file join $OUT_DIR power_vcd.rpt]
report_messages > [file join $OUT_DIR messages.rpt]
puts "GENUS_VCD_POWER_RUN_COMPLETE: [file join $OUT_DIR power_vcd.rpt]"
