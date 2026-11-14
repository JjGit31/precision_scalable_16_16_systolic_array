# Run this script from the Vivado Tcl console after creating/opening a project.
# It adds this repository's RTL and the all-modes functional testbench.

set repo_root [file normalize [file join [file dirname [info script]] ..]]
set rtl_files [glob -nocomplain [file join $repo_root rtl *.v]]
if {[llength $rtl_files] != 5} {
    error "Expected 5 RTL .v files in $repo_root/rtl, found [llength $rtl_files]"
}

add_files -norecurse -fileset sources_1 $rtl_files
foreach f $rtl_files {
    # The top uses unpacked arrays, so compile RTL as SystemVerilog in Vivado.
    set_property file_type SystemVerilog [get_files $f]
}

set tb_file [file join $repo_root tb tb_systolic_array_16x16_functional.sv]
add_files -norecurse -fileset sim_1 [list $tb_file]
set_property top tb_systolic_array_16x16_functional [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Added RTL and testbench from $repo_root"
puts "Simulation top: tb_systolic_array_16x16_functional"
