# Precision-Scalable 16×16 Systolic Array

A 16×16 output-stationary systolic array supporting INT4, INT8 and INT16 matrix-multiplication operations. The array is organized as a 4×4 mesh of 4×4 PE macroblocks. Each macroblock contains 16 MAC processing elements, shared A/B operand banks, precision-dependent lane extraction, registered operand-valid forwarding and local accumulator control.

The RTL is written in Verilog/SystemVerilog and is supported by Vivado simulation scripts, a self-checking functional testbench, a VCD simulation flow and Cadence Genus synthesis/power-analysis scripts.

## Features

- 256 processing elements arranged as sixteen 4×4 macroblocks.
- Output-stationary dataflow with an independent accumulator in every PE.
- INT4, INT8 and INT16 arithmetic modes.
- Shared operand storage at macroblock level.
- A operands distributed across PE rows; B operands distributed down PE columns.
- Registered A/B forwarding between adjacent macroblocks.
- Precision-dependent operand-bank clock enables.
- Operand isolation in the multiplier/accumulator datapath.
- Nine 4-bit accumulator register groups with precision-dependent enables.
- Global controller with `IDLE`, `CLEAR`, `COMPUTE` and `DONE` states.
- Vivado functional simulation and VCD generation flows.
- Cadence Genus synthesis, timing and VCD-based power-analysis flow.

## Architecture

The default configuration contains a 16×16 PE array:

- 16 PE rows and 16 PE columns.
- 4×4 macroblocks in the global mesh.
- 4×4 PEs in each macroblock.
- 256 MAC PEs in total.

Each PE computes one output element and maintains its own accumulated partial sum. Within each macroblock, A operands are shared across the four PEs in a row, while B operands are shared down the four PEs in a column.

A data moves horizontally from one macroblock to the next. B data moves vertically. Each macroblock registers its operand banks and forwards the registered bank outputs and corresponding valid signals to its right and lower neighbors.

```text
                16 × 16 Systolic Array

       +---------+---------+---------+---------+
       |   T00   |   T01   |   T02   |   T03   |
       |  4×4 PE |  4×4 PE |  4×4 PE |  4×4 PE |
       +---------+---------+---------+---------+
       |   T10   |   T11   |   T12   |   T13   |
       |  4×4 PE |  4×4 PE |  4×4 PE |  4×4 PE |
       +---------+---------+---------+---------+
       |   T20   |   T21   |   T22   |   T23   |
       |  4×4 PE |  4×4 PE |  4×4 PE |  4×4 PE |
       +---------+---------+---------+---------+
       |   T30   |   T31   |   T32   |   T33   |
       |  4×4 PE |  4×4 PE |  4×4 PE |  4×4 PE |
       +---------+---------+---------+---------+

       A forwarding: left  → right
       B forwarding: top   → bottom
```

## Precision modes

Each macroblock contains four 16-bit A operand banks and four 16-bit B operand banks. The precision decoder selects which banks capture data.

| `precision_mode` | Mode | Operand width | Active A banks | Active B banks | Accumulator width |
|---|---|---:|---:|---:|---:|
| `2'b00` | INT4 | 4 bits | 1 of 4 | 1 of 4 | 12 bits |
| `2'b01` | INT8 | 8 bits | 2 of 4 | 2 of 4 | 20 bits |
| `2'b10` | INT16 | 16 bits | 4 of 4 | 4 of 4 | 36 bits |
| `2'b11` | Reserved | — | None | None | — |

The active-bank masks are:

| Mode | Active-bank mask | Banks used |
|---|---|---|
| INT4 | `4'b0001` | Bank 0 |
| INT8 | `4'b0011` | Banks 0–1 |
| INT16 | `4'b1111` | Banks 0–3 |

The 64-bit A and B macroblock input words contain four spatial PE-lane operands for one reduction step:

- **INT4:** four 4-bit lane values occupy the low 16 bits and use one 16-bit bank.
- **INT8:** four 8-bit lane values occupy the low 32 bits and use two 16-bit banks.
- **INT16:** four 16-bit lane values occupy all 64 bits and use four 16-bit banks.

The macroblock extracts the four lanes and distributes them to its PE rows and columns. The RTL processes one reduction-step operand set per valid compute cycle; this implementation does not select multiple consecutive reduction-step values from a single word over several cycles.

## Data and control flow

### Operand-bank enables

A and B operand streams are qualified independently. For each bank, capture is enabled only when the bank is active for the selected precision and the corresponding input-valid signal is asserted:

```verilog
 a_gate_en = active_banks & {4{a_valid_in}};
 b_gate_en = active_banks & {4{b_valid_in}};
```

Each macroblock uses four A-bank and four B-bank clock-gating cells. The registered valid paths use the system clock so that valid and invalid cycles propagate through the macroblock mesh.

### PE MAC enable

The local PE MAC enable is:

```verilog
mac_valid = compute_en && a_valid_q && b_valid_q;
```

A PE accumulates only when the global controller is in `COMPUTE` and both registered operand-valid signals are high.

### Accumulator control

Each PE has a 36-bit accumulator implemented as nine 4-bit register groups. The active groups depend on precision:

| Mode | Active accumulator bits | Enabled 4-bit groups |
|---|---:|---:|
| INT4 | 12 | 3 |
| INT8 | 20 | 5 |
| INT16 | 36 | 9 |

All accumulator groups can be enabled during clear. During MAC operation, the precision mode and `mac_en` qualify the group clock enables.

## Global controller and schedule

The top-level controller uses four states:

| State | Encoding | Function |
|---|---|---|
| `IDLE` | `2'b00` | Wait for `start` and a valid precision mode; latch mode and signedness. |
| `CLEAR` | `2'b01` | Clear the PE accumulators and reset the cycle counter. |
| `COMPUTE` | `2'b10` | Run the array schedule and increment the global cycle counter. |
| `DONE` | `2'b11` | Assert `done` and wait for `start` to deassert. |

For the default `PE_N = 16` configuration, the RTL calculates:

```verilog
LAST_CYCLE = PE_N + 2*(PE_N/4) - 2;
```

This gives `LAST_CYCLE = 22`. The counter visits cycle indices 0 through 22, so the global `COMPUTE` interval is 23 clock cycles. The macroblocks do not all begin at the same time: A/B forwarding and the boundary input schedule create tile-position-dependent activity. The cycle counter is global; individual macroblocks do not contain separate FSMs or local schedule counters.

## RTL hierarchy

```text
precision_packed_systolic_array
└── 4 × 4 macroblock mesh
    └── precision_packed_tile_4x4
        ├── 4 × 16-bit A operand banks
        ├── 4 × 16-bit B operand banks
        ├── Precision decoder and lane extraction
        ├── Registered A/B valid forwarding
        └── 4 × 4 PE array
            └── precision_scalable_mac_pe_en
                ├── parallel_precision_scalable_multiplier_pe
                └── actual_adder
                    ├── CLA arithmetic slices
                    ├── Precision-dependent correction logic
                    └── 9 × 4-bit accumulator groups
```

## Repository structure

```text
precision_scalable_systolic_array_repo/
├── rtl/
│   ├── actual_adder.v
│   ├── parallel_precision_scalable_multiplier_pe.v
│   ├── precision_scalable_mac_pe_en.v
│   ├── precision_packed_tile_4x4.v
│   ├── precision_packed_systolic_array.v
│   └── files.f
├── tb/
│   ├── tb_systolic_array_16x16_functional.sv
│   └── tb_array_vcd16.sv
├── constraints/
│   └── array_3p333ns_vcd.sdc
├── scripts/
│   ├── vivado_add_sources.tcl
│   ├── add_vivado_waves.tcl
│   ├── run_vivado_functional_sim.sh
│   ├── run_all_vcd_simulations.sh
│   ├── run_one_synth_all_vcd.sh
│   ├── genus_synth_once_vcd.tcl
│   ├── genus_power_from_vcd_db.tcl
│   ├── xsim_vcd_capture.tcl
│   └── check_vcd.py
├── .gitattributes
├── .gitignore
└── README.md
```

## Functional verification in Vivado

The self-checking testbench is `tb/tb_systolic_array_16x16_functional.sv`. It runs:

- INT4, INT8 and INT16.
- All four signedness combinations: unsigned/unsigned, unsigned/signed, signed/unsigned and signed/signed.
- A complete 16×16 matrix multiplication for each mode/signedness combination.
- All 256 output elements in each transaction.
- The expected terminal cycle count (`cycle_count = 22`).

The testbench is configured for 12 transactions and 3,072 output comparisons across the three precision modes and four signedness combinations.

### Run from the Vivado GUI

1. Create or open a Vivado project.
2. Open the Vivado Tcl Console and run the following from the repository root:

   ```tcl
   source scripts/vivado_add_sources.tcl
   ```

3. In **Simulation Sources**, check that `tb_systolic_array_16x16_functional` is the simulation top.
4. Select **Run Simulation → Run Behavioral Simulation**.
5. In the XSim Tcl Console, add the suggested signals:

   ```tcl
   source [file normalize scripts/add_vivado_waves.tcl]
   ```

6. Select **Run All**. Check the simulator transcript for the per-transaction PASS messages and the final summary.

The RTL source files use a `.v` extension but include SystemVerilog constructs. The Vivado Tcl setup marks these files as SystemVerilog. When adding the RTL manually, set the file type to **SystemVerilog**.

### Run from a Linux shell with Vivado/XSim on `PATH`

Run the functional testbench in batch mode:

```bash
GUI=0 ./scripts/run_vivado_functional_sim.sh
```

Set `GUI=1` to launch the XSim GUI.

## VCD generation and Cadence Genus analysis

The VCD workload is in `tb/tb_array_vcd16.sv`. It runs a multi-matrix test for the selected signedness configuration and generates VCD activity for INT4, INT8 and INT16.

### 1. Generate simulation and VCD activity

From a Linux shell with Vivado/XSim available:

```bash
SIGN=3 ./scripts/run_all_vcd_simulations.sh
```

`SIGN` selects the signedness combination:

| `SIGN` | A | B |
|---:|---|---|
| 0 | Unsigned | Unsigned |
| 1 | Unsigned | Signed |
| 2 | Signed | Unsigned |
| 3 | Signed | Signed |

The script checks the functional PASS marker and VCD structure before continuing. VCD files are written under `vcd/`; logs are written under `logs/`.

### 2. Run Genus synthesis and VCD-based power analysis

With Cadence Genus and the target standard-cell library configured:

```bash
OPT_MODE=balanced SIGN=3 \
RUN_ID="array_3p333ns_$(date +%Y%m%d_%H%M%S)" \
./scripts/run_one_synth_all_vcd.sh
```

The script performs one synthesis at the 3.333 ns constraint and then runs VCD-based power analysis for INT4, INT8 and INT16 using the mapped database. It expects the VCD files and corresponding simulation PASS logs to exist first.

Environment variables supported by the script:

- `GENUS_ENV_SCRIPT`: shell script for loading the local Cadence environment.
- `GENUS_SETUP_TCL`: Genus library/setup Tcl file.
- `STD_CELL_LIB`: Liberty file to read when `GENUS_SETUP_TCL` is not used.
- `OPT_MODE`: `fast`, `balanced` or `aggressive`.
- `SIGN`: signedness scenario, 0 through 3.
- `RUN_ID`: unique identifier for the synthesis and report directory.

Review the Genus logs for VCD annotation messages. Confirm that the expected design activity is annotated before using the power results. `check_vcd.py` checks VCD structure and activity; it does not confirm complete Genus annotation.

## Timing constraint

`constraints/array_3p333ns_vcd.sdc` applies a 3.333 ns clock period (approximately 300 MHz) and defines the input delays, output delays, input transition and output load used by the Genus flow. This is a timing target. Timing closure must be assessed from the Genus timing reports; a functional simulation with a 3.333 ns clock does not by itself prove timing closure.

## Top-level interface

Top module: `precision_packed_systolic_array`

### Inputs

| Port | Width (default configuration) | Description |
|---|---:|---|
| `clk` | 1 | System clock |
| `rst_n` | 1 | Asynchronous active-low reset |
| `start` | 1 | Starts a transaction while the controller is idle |
| `precision_mode` | 2 | `00` INT4, `01` INT8, `10` INT16, `11` reserved |
| `signed_a`, `signed_b` | 1 each | A/B operand signedness |
| `a_left_data` | 256 | Four 64-bit A boundary groups |
| `a_left_valid` | 4 | Valid for each A boundary group |
| `b_top_data` | 256 | Four 64-bit B boundary groups |
| `b_top_valid` | 4 | Valid for each B boundary group |

### Outputs

| Port | Width (default configuration) | Description |
|---|---:|---|
| `busy` | 1 | High during CLEAR and COMPUTE |
| `done` | 1 | High in DONE |
| `active_mode` | 2 | Latched precision mode |
| `active_signed_a`, `active_signed_b` | 1 each | Latched signedness |
| `cycle_count` | 5 | Global compute-cycle index |
| `state_debug` | 2 | Encoded global FSM state |
| `c_flat` | 9,216 | 256 consecutive 36-bit outputs, row-major order |

## License

A license has not been selected for this project. Add a license file before granting permissions for reuse or redistribution.
