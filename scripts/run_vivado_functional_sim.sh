#!/usr/bin/env bash
# Compile the complete RTL and run the Vivado-friendly all-modes testbench.
# Set GUI=1 (default) to open XSim GUI; set GUI=0 for batch execution.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VIVADO_SETTINGS="${VIVADO_SETTINGS:-/usr/local/tools/Xilinx/Vivado/2024.2/settings64.sh}"

if ! command -v xvlog >/dev/null 2>&1 || ! command -v xelab >/dev/null 2>&1 || ! command -v xsim >/dev/null 2>&1; then
    [[ -r "$VIVADO_SETTINGS" ]] || {
        echo "ERROR: XSim is unavailable and Vivado settings were not found: $VIVADO_SETTINGS" >&2
        exit 127
    }
    # shellcheck disable=SC1090
    source "$VIVADO_SETTINGS"
fi
for tool in xvlog xelab xsim; do
    command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool is not available." >&2; exit 127; }
done

RTL=(
    "$ROOT/rtl/actual_adder.v"
    "$ROOT/rtl/parallel_precision_scalable_multiplier_pe.v"
    "$ROOT/rtl/precision_scalable_mac_pe_en.v"
    "$ROOT/rtl/precision_packed_tile_4x4.v"
    "$ROOT/rtl/precision_packed_systolic_array.v"
    "$ROOT/tb/tb_systolic_array_16x16_functional.sv"
)
for file in "${RTL[@]}"; do
    [[ -s "$file" ]] || { echo "ERROR: missing RTL/testbench: $file" >&2; exit 3; }
done

SIM_DIR="$ROOT/sim/vivado_functional"
mkdir -p "$SIM_DIR"
(
    cd "$SIM_DIR"
    xvlog -sv "${RTL[@]}"
    xelab -debug typical tb_systolic_array_16x16_functional -s systolic_array_functional
    if [[ "${GUI:-1}" == "1" ]]; then
        xsim systolic_array_functional -gui
    else
        xsim systolic_array_functional -runall
    fi
)
