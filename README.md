# Precision-Scalable 16×16 Systolic Array

RTL, functional testbenches, timing constraints, and Cadence Genus/XSim scripts for a 16×16 output-stationary systolic array.

## 1. RTL hierarchy

Top module: `precision_packed_systolic_array`

```text
precision_packed_systolic_array
└── 4 × 4 macroblock mesh
    └── precision_packed_tile_4x4 (each macroblock)
        └── 4 × 4 PE array
            └── precision_scalable_mac_pe_en (each PE)
                ├── parallel_precision_scalable_multiplier_pe
                └── actual_adder
                    └── icg_cell
```

The design contains 16 macroblocks and 256 PEs. Each macroblock contains four 16-bit A operand banks, four 16-bit B operand banks, and 16 independent accumulators.

## 2. Precision modes

| `precision_mode` | Mode | Operand lane width | Active A/B banks per macroblock | Accumulator width |
|---|---|---:|---:|---:|
| `2'b00` | INT4 | 4 bits | 1 of 4 | 12 bits |
| `2'b01` | INT8 | 8 bits | 2 of 4 | 20 bits |
| `2'b10` | INT16 | 16 bits | 4 of 4 | 36 bits |
| `2'b11` | Reserved | — | none | — |

The top-level controller latches the selected mode and signedness when `start` is accepted. It then performs one clear cycle followed by a 23-cycle compute interval (`cycle_count` 0 through 22). The macroblock mesh uses registered A forwarding from left to right and B forwarding from top to bottom.

## 3. Important data-format note

This repository preserves the RTL implementation from the supplied Genus/VCD archive. In this RTL, each 64-bit boundary group carries four spatial PE-lane operands for one reduction index: INT4 uses the low 16 bits, INT8 uses the low 32 bits, and INT16 uses all 64 bits. The tile unpacks those four lane values and shares A across a PE row and B down a PE column.

This is **not** the separate temporal multi-operand-per-word / K-select variant shown in the later HTML simulation. The RTL here consumes one reduction-index value per compute cycle. Do not describe the RTL as implementing temporal multi-cycle K selection unless that logic is added and verified separately.

## 4. Repository layout

```text
rtl/
  actual_adder.v
  parallel_precision_scalable_multiplier_pe.v
  precision_scalable_mac_pe_en.v
  precision_packed_tile_4x4.v
  precision_packed_systolic_array.v

tb/
  tb_systolic_array_16x16_functional.sv  # Vivado all-mode functional test
  tb_array_vcd16.sv                     # Existing 15-matrix VCD workload

constraints/
  array_3p333ns_vcd.sdc

scripts/
  vivado_add_sources.tcl
  add_vivado_waves.tcl
  run_vivado_functional_sim.sh
  run_all_vcd_simulations.sh
  run_one_synth_all_vcd.sh
  genus_synth_once_vcd.tcl
  genus_power_from_vcd_db.tcl
  xsim_vcd_capture.tcl
  check_vcd.py
```

## 5. Run functional verification in Vivado

### Option A — Vivado GUI

1. Create a new RTL project (the functional simulation does not require a specific FPGA part).
2. Open the Vivado Tcl Console and `cd` to this repository folder.
3. Source the project-import script:

   ```tcl
   source scripts/vivado_add_sources.tcl
   ```

4. In **Sources → Simulation Sources**, confirm `tb_systolic_array_16x16_functional` is the simulation top.
5. Click **Run Simulation → Run Behavioral Simulation**.
6. In the XSim Tcl Console, load the suggested waveform list:

   ```tcl
   source [file normalize scripts/add_vivado_waves.tcl]
   ```

7. Click **Run All**. The testbench should print a PASS line for each mode/signedness combination and a final summary.

The RTL `.v` files use unpacked net arrays in the top-level hierarchy. The import script marks them as **SystemVerilog** in Vivado. If adding files manually, set each RTL `.v` file's File Type to SystemVerilog, or compile with `xvlog -sv`.

### Option B — XSim command line

From the repository root:

```bash
GUI=0 ./scripts/run_vivado_functional_sim.sh
```

For the XSim GUI:

```bash
GUI=1 ./scripts/run_vivado_functional_sim.sh
```

The new functional testbench runs 12 complete transactions: INT4, INT8, and INT16, each with unsigned/unsigned, unsigned/signed, signed/unsigned, and signed/signed operands. It compares all 256 output elements per transaction (3,072 output checks total) against a testbench-only matrix multiplication reference. It also checks that the controller finishes at `cycle_count = 22`.

Expected final message:

```text
FUNCTIONAL TEST PASS: transactions=12 outputs_checked=3072 errors=0
```

If a mismatch occurs, the testbench prints the mode, signedness, output coordinate, actual value, and expected value, then terminates with `$fatal`.

## 6. Existing full VCD workload

The original archive's VCD testbench is retained as `tb/tb_array_vcd16.sv`. It runs 15 matrices for a selected precision/sign configuration and is used by the Genus VCD flow.

From the repository root, with Vivado/XSim available:

```bash
SIGN=3 ./scripts/run_all_vcd_simulations.sh
```

`SIGN` encoding: `0 = U/U`, `1 = U/S`, `2 = S/U`, `3 = S/S`. The script runs INT4, INT8 and INT16 at the selected signedness and creates VCDs under `vcd/`.

Then, with the approved Genus environment and standard-cell library loaded:

```bash
OPT_MODE=balanced SIGN=3 RUN_ID="array_3p333ns_$(date +%Y%m%d_%H%M%S)" \
  ./scripts/run_one_synth_all_vcd.sh
```

Set `GENUS_ENV_SCRIPT`, `GENUS_SETUP_TCL`, or `STD_CELL_LIB` to match the lab environment. The shell script deliberately refuses to proceed if the VCDs or functional PASS logs are missing.

## 7. Timing constraint

`constraints/array_3p333ns_vcd.sdc` specifies a 3.333 ns clock period. This is a synthesis/static-timing constraint; running functional simulation at a 3.333 ns clock does not itself prove timing closure. Use the Genus timing report for that assessment.

## 8. Verification status and limitations

- The RTL was preserved from the user-supplied archive; filenames and script paths were normalized for this repository.
- A new Vivado-oriented self-checking testbench was added. It covers all three precision modes and all four A/B signedness combinations, checks 3,072 outputs, and checks the 23-cycle controller terminal count.
- The existing 15-matrix VCD testbench and Genus scripts are retained.
- **No Vivado/XSim or Genus run was possible in this build environment.** The new testbench and scripts have been reviewed for source/port consistency, but functional PASS is not claimed until the user runs them in Vivado/XSim.
- The VCD checker only checks trace structure and activity. It does not prove VCD annotation coverage or power correctness; inspect the Genus `read_vcd` messages.

## 9. Main module interface

`precision_packed_systolic_array` inputs:

- `clk`, `rst_n`, `start`
- `precision_mode[1:0]`, `signed_a`, `signed_b`
- `a_left_data[255:0]`, `a_left_valid[3:0]`
- `b_top_data[255:0]`, `b_top_valid[3:0]`

Outputs:

- `busy`, `done`
- `active_mode[1:0]`, `active_signed_a`, `active_signed_b`
- `cycle_count[4:0]`, `state_debug[1:0]`
- `c_flat[9215:0]`, containing 256 consecutive 36-bit results in row-major order.
