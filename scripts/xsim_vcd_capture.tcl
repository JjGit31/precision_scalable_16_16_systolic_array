# XSim batch VCD capture. VCD scope starts at /tb_array_vcd16/dut.
if {![info exists ::env(VCD_OUTPUT)] || $::env(VCD_OUTPUT) eq ""} {
    error "VCD_OUTPUT environment variable is required."
}
set vcd_file [file normalize $::env(VCD_OUTPUT)]
file mkdir [file dirname $vcd_file]
puts "VCD_CAPTURE_BEGIN: $vcd_file"
open_vcd $vcd_file
# -level 0 logs all signals below this hierarchy, including nested tile/PE logic.
log_vcd -level 0 /tb_array_vcd16/dut/*
puts "VCD_SIMULATION_BEGIN"
run all
flush_vcd
close_vcd
puts "VCD_CAPTURE_CLOSED: $vcd_file"
quit
