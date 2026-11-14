#!/usr/bin/env bash
# Run three 15-matrix functional simulations and create one full DUT VCD per precision.
# All simulations must pass before the user launches the expensive Genus synthesis.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"
SIGN="${SIGN:-3}"
VIVADO_SETTINGS="${VIVADO_SETTINGS:-/usr/local/tools/Xilinx/Vivado/2024.2/settings64.sh}"
VCD_TAG="${VCD_TAG:-3p333ns_s${SIGN}}"

case "$SIGN" in 0|1|2|3) ;; *) echo "ERROR: SIGN must be 0..3." >&2; exit 2 ;; esac
if ! command -v xvlog >/dev/null 2>&1 || ! command -v xelab >/dev/null 2>&1 || ! command -v xsim >/dev/null 2>&1; then
  [[ -r "$VIVADO_SETTINGS" ]] || { echo "ERROR: XSim tools unavailable and settings file not readable: $VIVADO_SETTINGS" >&2; exit 127; }
  # shellcheck disable=SC1090
  source "$VIVADO_SETTINGS"
fi
for t in xvlog xelab xsim; do command -v "$t" >/dev/null 2>&1 || { echo "ERROR: $t is not available after loading Vivado settings." >&2; exit 127; }; done

RTL=(
  "$ROOT/rtl/actual_adder.v"
  "$ROOT/rtl/parallel_precision_scalable_multiplier_pe.v"
  "$ROOT/rtl/precision_scalable_mac_pe_en.v"
  "$ROOT/rtl/precision_packed_tile_4x4.v"
  "$ROOT/rtl/precision_packed_systolic_array.v"
  "$ROOT/tb/tb_array_vcd16.sv"
)
for f in "${RTL[@]}" "$ROOT/scripts/xsim_vcd_capture.tcl" "$ROOT/scripts/check_vcd.py"; do
  [[ -s "$f" ]] || { echo "ERROR: Required simulation file missing/empty: $f" >&2; exit 3; }
done
mkdir -p "$ROOT/vcd" "$ROOT/logs" "$ROOT/sim"
SIMDIR="$ROOT/sim/vcd_3p333ns_s${SIGN}"
mkdir -p "$SIMDIR"
SNAPSHOT="array16_vcd_3p333ns_s${SIGN}"

(
  cd "$SIMDIR"
  echo "===== XSim compile: 3.333 ns VCD testbench ====="
  xvlog -sv "${RTL[@]}"
  echo "===== XSim elaborate: $SNAPSHOT ====="
  xelab -debug typical tb_array_vcd16 -s "$SNAPSHOT"
) 2>&1 | tee "$ROOT/logs/xsim_vcd_compile_s${SIGN}.log"

for MODE in 0 1 2; do
  case "$MODE" in 0) NAME=int4 ;; 1) NAME=int8 ;; 2) NAME=int16 ;; esac
  VCD="$ROOT/vcd/${NAME}_${VCD_TAG}.vcd"
  LOG="$ROOT/logs/xsim_vcd_${NAME}_s${SIGN}.log"
  if [[ -e "$VCD" ]]; then
    BACKUP="${VCD}.previous.$(date +%Y%m%d_%H%M%S)"
    echo "Backing up existing VCD to $BACKUP"
    mv -- "$VCD" "$BACKUP"
  fi
  export VCD_OUTPUT="$VCD"
  echo
  echo "============================================================"
  echo "XSim FUNCTIONAL + VCD: $NAME SIGN=$SIGN CLOCK=3.333ns"
  echo "VCD: $VCD"
  echo "============================================================"
  set +e
  ( cd "$SIMDIR" && xsim "$SNAPSHOT" \
      -tclbatch "$ROOT/scripts/xsim_vcd_capture.tcl" \
      -testplusarg "m=$MODE" -testplusarg "s=$SIGN" ) 2>&1 | tee "$LOG"
  STATUS=${PIPESTATUS[0]}
  set -e
  if [[ $STATUS -ne 0 ]]; then echo "ERROR: XSim failed for $NAME (exit=$STATUS). No Genus run should be started." >&2; exit "$STATUS"; fi
  grep -Fq "FINAL PASS: ARRAY16 mode=${MODE} sign=${SIGN} matrices=15 outputs=3840 errors=0" "$LOG" || {
    echo "ERROR: $NAME did not pass all 15 matrices. Do not start Genus." >&2; exit 4;
  }
  grep -Fq "VCD_CAPTURE_CLOSED: $VCD" "$LOG" || { echo "ERROR: VCD close marker missing for $NAME." >&2; exit 5; }
  python3 "$ROOT/scripts/check_vcd.py" "$VCD"
  echo "PASS: $NAME functional suite and VCD capture completed."
done

echo
echo "ALL THREE VCD SIMULATIONS PASSED. It is now safe to start the single Genus synthesis."
echo "VCD files:"
ls -lh "$ROOT/vcd"/*"${VCD_TAG}.vcd"
