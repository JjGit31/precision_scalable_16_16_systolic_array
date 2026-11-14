# Source this file from the Vivado/XSim Tcl console after launching
# tb_systolic_array_16x16_functional simulation.

add_wave -group "Clock and Reset" \
    {/tb_systolic_array_16x16_functional/clk} \
    {/tb_systolic_array_16x16_functional/rst_n} \
    {/tb_systolic_array_16x16_functional/start}

add_wave -group "Controller" \
    {/tb_systolic_array_16x16_functional/precision_mode} \
    {/tb_systolic_array_16x16_functional/active_mode} \
    {/tb_systolic_array_16x16_functional/state_debug} \
    {/tb_systolic_array_16x16_functional/cycle_count} \
    {/tb_systolic_array_16x16_functional/busy} \
    {/tb_systolic_array_16x16_functional/done}

add_wave -group "Boundary Operand Streams" \
    {/tb_systolic_array_16x16_functional/a_left_valid} \
    {/tb_systolic_array_16x16_functional/b_top_valid} \
    {/tb_systolic_array_16x16_functional/a_left_data[63:0]} \
    {/tb_systolic_array_16x16_functional/b_top_data[63:0]}

add_wave -group "Array Output Sample C00" \
    {/tb_systolic_array_16x16_functional/c_flat[35:0]}

# For deeper inspection, expand dut/ROW[0]/COL[0]/u_tile in the Scope pane and
# add bank_capture_en, a_gate_en, b_gate_en, mac_valid and the local PE signals.
