#!/usr/bin/env bash
# One 3.333 ns Genus synthesis, then three VCD-annotated power analyses from its DB.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"
SIGN="${SIGN:-3}"
OPT_MODE="${OPT_MODE:-balanced}"
RUN_ID="${RUN_ID:-3p333ns_${OPT_MODE}_vcd_s${SIGN}}"
GENUS_BIN_DIR="${GENUS_BIN_DIR:-/usr/local/tools/cadence/digital_ic_design/23.35-s106_1/GENUS231/bin}"
GENUS_ENV_SCRIPT="${GENUS_ENV_SCRIPT:-}"
STD_CELL_LIB="${STD_CELL_LIB:-/afs/iitd.ac.in/service/tools/public/asiclib/tsmc/L65/libraries/LP/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65lp_220a/tcbn65lptc.lib}"
SDC_FILE="$ROOT/constraints/array_3p333ns_vcd.sdc"
VCD_TAG="${VCD_TAG:-3p333ns_s${SIGN}}"
REPORT_ROOT="$ROOT/reports_${RUN_ID}"
SYNTH_DB="$ROOT/netlist/precision_packed_systolic_array_mapped_${RUN_ID}.db"

case "$SIGN" in 0|1|2|3) ;; *) echo "ERROR: SIGN must be 0..3." >&2; exit 2 ;; esac
case "$OPT_MODE" in balanced) EFFORT=medium ;; fast) EFFORT=low ;; aggressive) EFFORT=high ;; *) echo "ERROR: OPT_MODE must be balanced, fast, or aggressive." >&2; exit 2 ;; esac

# Load only the lab-approved environment supplied by the user, if requested.
if [[ -n "$GENUS_ENV_SCRIPT" ]]; then
  [[ -r "$GENUS_ENV_SCRIPT" ]] || { echo "ERROR: Cannot read GENUS_ENV_SCRIPT=$GENUS_ENV_SCRIPT" >&2; exit 2; }
  # shellcheck disable=SC1090
  source "$GENUS_ENV_SCRIPT"
fi
if ! command -v genus >/dev/null 2>&1 && [[ -d "$GENUS_BIN_DIR" ]]; then export PATH="$GENUS_BIN_DIR:$PATH"; fi
command -v genus >/dev/null 2>&1 || { echo "ERROR: genus is not in PATH; load the IIT Cadence environment." >&2; exit 127; }
if [[ -z "${CDS_LIC_FILE:-}" && -z "${LM_LICENSE_FILE:-}" ]]; then
  echo "ERROR: No CDS_LIC_FILE/LM_LICENSE_FILE in this shell. Load the official IIT Cadence license environment; do not guess a license server." >&2
  exit 78
fi
if [[ -n "${GENUS_SETUP_TCL:-}" ]]; then
  [[ -r "$GENUS_SETUP_TCL" ]] || { echo "ERROR: GENUS_SETUP_TCL not readable: $GENUS_SETUP_TCL" >&2; exit 2; }
  unset STD_CELL_LIB
else
  [[ -r "$STD_CELL_LIB" ]] || { echo "ERROR: TSMC Liberty file not readable: $STD_CELL_LIB. Set STD_CELL_LIB or GENUS_SETUP_TCL." >&2; exit 2; }
  export STD_CELL_LIB
fi

# Verify all source files, exact SDC period, VCD traces and pass logs before consuming a Genus license.
RTL=(rtl/actual_adder.v rtl/parallel_precision_scalable_multiplier_pe.v rtl/precision_scalable_mac_pe_en.v rtl/precision_packed_tile_4x4.v rtl/precision_packed_systolic_array.v)
for f in "${RTL[@]}" tb/tb_array_vcd16.sv scripts/genus_synth_once_vcd.tcl scripts/genus_power_from_vcd_db.tcl; do
  [[ -s "$ROOT/$f" ]] || { echo "ERROR: Missing/empty required file: $ROOT/$f" >&2; exit 3; }
done
[[ -s "$SDC_FILE" ]] || { echo "ERROR: Missing/empty SDC: $SDC_FILE" >&2; exit 3; }
grep -Eq 'create_clock[[:space:]].*-period[[:space:]]+3\.333([[:space:]]|$)' "$SDC_FILE" || { echo "ERROR: SDC must constrain 3.333 ns." >&2; exit 3; }
for MODE in 0 1 2; do
  case "$MODE" in 0) NAME=int4 ;; 1) NAME=int8 ;; 2) NAME=int16 ;; esac
  VCD="$ROOT/vcd/${NAME}_${VCD_TAG}.vcd"
  LOG="$ROOT/logs/xsim_vcd_${NAME}_s${SIGN}.log"
  [[ -s "$VCD" ]] || { echo "ERROR: Missing VCD: $VCD. Run ./scripts/run_all_vcd_simulations.sh first." >&2; exit 3; }
  [[ -s "$LOG" ]] && grep -Fq "FINAL PASS: ARRAY16 mode=${MODE} sign=${SIGN} matrices=15 outputs=3840 errors=0" "$LOG" || {
    echo "ERROR: Functional PASS log missing for $NAME. Do not start Genus." >&2; exit 3;
  }
  python3 "$ROOT/scripts/check_vcd.py" "$VCD"
done

# Refuse accidental overwrite of a valuable prior DB/report set.
if [[ -e "$SYNTH_DB" || -e "$REPORT_ROOT" ]]; then
  echo "ERROR: Output path already exists for RUN_ID=$RUN_ID:" >&2
  echo "  DB: $SYNTH_DB" >&2
  echo "  reports: $REPORT_ROOT" >&2
  echo "Choose a fresh RUN_ID; existing results will not be overwritten." >&2
  exit 4
fi
mkdir -p "$ROOT/logs" "$ROOT/netlist"
export REPORT_ROOT SYNTH_DB SYNTH_EFFORT="$EFFORT"

SYN_LOG="$ROOT/logs/genus_synthesis_once_${RUN_ID}.log"
SYN_TEE="$ROOT/logs/genus_synthesis_once_${RUN_ID}_terminal.log"
echo "============================================================"
echo "ONE FULL GENUS SYNTHESIS — 3.333 ns"
echo "Run ID: $RUN_ID"
echo "Library: ${STD_CELL_LIB:-GENUS_SETUP_TCL=${GENUS_SETUP_TCL:-unset}}"
echo "SDC: $SDC_FILE"
echo "Effort: $EFFORT"
echo "Database: $SYNTH_DB"
echo "Reports: $REPORT_ROOT"
echo "============================================================"
set +e
genus -no_gui -batch -files "$ROOT/scripts/genus_synth_once_vcd.tcl" -log "$SYN_LOG" 2>&1 | tee "$SYN_TEE"
STATUS=${PIPESTATUS[0]}
set -e
if [[ $STATUS -ne 0 ]]; then echo "ERROR: Genus synthesis failed (exit=$STATUS). See $SYN_LOG" >&2; exit "$STATUS"; fi
[[ -s "$SYNTH_DB" ]] || { echo "ERROR: mapped Genus DB missing/empty: $SYNTH_DB" >&2; exit 5; }
grep -Fq "GENUS_SYNTHESIS_DB_READY: $SYNTH_DB" "$SYN_LOG" "$SYN_TEE" || { echo "ERROR: Genus DB completion marker missing." >&2; exit 5; }

# Power-only replays: no read_hdl, syn_generic, syn_map or syn_opt below.
for MODE in 0 1 2; do
  case "$MODE" in 0) NAME=int4 ;; 1) NAME=int8 ;; 2) NAME=int16 ;; esac
  export VCD_FILE="$ROOT/vcd/${NAME}_${VCD_TAG}.vcd"
  export REPORT_TAG="${NAME}_s${SIGN}_${RUN_ID}"
  LOG="$ROOT/logs/genus_power_${REPORT_TAG}.log"
  TEE_LOG="$ROOT/logs/genus_power_${REPORT_TAG}_terminal.log"
  echo
  echo "============================================================"
  echo "VCD POWER ONLY: $NAME SIGN=$SIGN"
  echo "VCD: $VCD_FILE"
  echo "============================================================"
  set +e
  genus -no_gui -batch -files "$ROOT/scripts/genus_power_from_vcd_db.tcl" -log "$LOG" 2>&1 | tee "$TEE_LOG"
  STATUS=${PIPESTATUS[0]}
  set -e
  if [[ $STATUS -ne 0 ]]; then echo "ERROR: VCD power analysis failed for $NAME (exit=$STATUS). See $LOG" >&2; exit "$STATUS"; fi
  grep -Fq "GENUS_VCD_POWER_RUN_COMPLETE" "$LOG" "$TEE_LOG" || { echo "ERROR: power completion marker missing for $NAME." >&2; exit 6; }
  [[ -s "$REPORT_ROOT/$REPORT_TAG/power_vcd.rpt" ]] || { echo "ERROR: missing power report for $NAME." >&2; exit 7; }
  echo "PASS: $REPORT_ROOT/$REPORT_TAG/power_vcd.rpt"
done

echo
echo "============================================================"
echo "ALL DONE: one 3.333 ns synthesis + three VCD power scenarios"
echo "Area/timing/QoR: $REPORT_ROOT/{area,timing,qor}.rpt"
for NAME in int4 int8 int16; do echo "Power: $REPORT_ROOT/${NAME}_s${SIGN}_${RUN_ID}/power_vcd.rpt"; done
echo "Review read_vcd annotation messages in each power log before accepting the power numbers."
echo "============================================================"
