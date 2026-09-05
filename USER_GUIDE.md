# User Guide — Environment Setup & Makefile Flows

This guide covers everything needed to reproduce the **functional verification**, **FPGA synthesis (Quartus/MAX 10)**, and **ASIC implementation (LibreLane/Sky130)** flows for this repo, all driven through the top-level `Makefile`.

---

## 1. Prerequisites

### 1.1 Common tools (verification)

| Tool | Purpose | Notes |
|---|---|---|
| [Icarus Verilog](https://github.com/steveicarus/iverilog) (`iverilog`, `vvp`) | Compile & simulate the RTL/testbench | Install with `-g2012` support (SystemVerilog-2012) |
| [Verilator](https://github.com/verilator/verilator) | Lint-only pass to catch synthesis hazards | Needs `--timing` support for testbench delays |
| [GTKWave](https://gtkwave.sourceforge.net/) | Waveform viewer | Optional, only needed for `make wave` |
| Python 3 | Runs the golden model / Dadda tree generator | `pip install` any deps your golden model script needs |

On Debian/Ubuntu:

```bash
sudo apt update
sudo apt install iverilog gtkwave verilator python3 python3-pip
```

### 1.2 ASIC flow (LibreLane + Sky130)

| Tool | Purpose |
|---|---|
| [LibreLane](https://librelane.readthedocs.io/) | Open-source RTL-to-GDSII flow (successor to OpenLane 2) |
| Sky130 PDK | Open-source 130nm process design kit, installed via LibreLane's PDK manager |
| Nix (recommended) or Docker | LibreLane's supported install/runtime methods |

Install LibreLane (Nix method, recommended by the LibreLane docs):

```bash
# Follow the official install guide:
# https://librelane.readthedocs.io/en/latest/getting_started/installation/index.html
```

Confirm it's on your `PATH`:

```bash
librelane --version
```

> The `Makefile` invokes LibreLane with an **absolute path** to `config.json`:
> `librelane ~/icprojects/macunit/config.json`
> Either clone this repo to `~/icprojects/macunit`, or edit the `flow`, `strat`, and `layout` targets in the `Makefile` to point at wherever you actually cloned it.

### 1.3 FPGA flow (optional — Intel MAX 10 / Quartus)

| Tool | Purpose |
|---|---|
| Intel Quartus Prime Lite | FPGA synthesis, fit, and timing analysis for the MAX 10 target |

The `Makefile` currently points at a Windows install path:

```makefile
QUARTUS_CMD = C:\intelFPGA_lite\20.1\quartus\bin64\quartus_sh.exe
```

Update `QUARTUS_CMD` to match your Quartus version/install path (this target assumes a Windows shell available via `cmd.exe`, e.g. WSL calling out to a Windows Quartus install, or run natively on Windows).

---

## 2. Repository Layout Relevant to the Flows

```
macunit/
├── mac_engine_2.sv          # Top-level MAC engine (synthesizable RTL)
├── axi_skid_buffer.sv       # AXI-Stream skid buffer
├── dadda_tree_gen.sv        # Generated Dadda adder tree
├── dadda_tree_generator.py  # Generator for dadda_tree_gen.sv
├── mac_verification/        # Testbench + golden model live here (or alongside RTL)
├── config.json              # LibreLane (Sky130 ASIC) configuration
├── RUN_2026-07-28_11-52-35/ # Example recorded LibreLane run
└── Makefile
```

---

## 3. Functional Verification Flow

All verification targets compile `mac_engine_2.sv` + `axi_skid_buffer.sv` against `tb_mac_engine_3.sv`.

### 3.1 Generate test data (golden model)

```bash
make data
```
Runs `mac_golden_model.py` to (re)generate the reference vectors the testbench checks against.

### 3.2 Compile only

```bash
make compile
```
Compiles the RTL + testbench with `iverilog -g2012 -Wall` into `sim.vvp`.

### 3.3 Compile + run simulation

```bash
make run
```
(Also the default target — plain `make` does the same thing.) Compiles, then runs `sim.vvp` with `vvp`.

### 3.4 Lint the RTL

```bash
make lint
```
Runs Verilator in `--lint-only` mode against the RTL sources to catch synthesis hazards (combinational loops, width mismatches, latch inference, etc.) before you trust the sim results.

### 3.5 View waveforms

```bash
make wave
```
Opens `mac_waves.vcd` in GTKWave (backgrounded). Make sure your testbench actually dumps to `mac_waves.vcd` (`$dumpfile`/`$dumpvars`).

### 3.6 Clean up

```bash
make clean
```
Removes `sim.vvp` and `mac_waves.vcd`.

**Typical loop while debugging:**
```bash
make clean && make data && make lint && make run && make wave
```

---

## 4. FPGA Flow (Intel MAX 10, optional)

### 4.1 Synthesize

```bash
make syn
```
Calls Quartus in shell mode (`quartus_sh -t build.tcl`) to synthesize, fit, and run timing/power analysis for the MAX 10 target. You'll need a `build.tcl` script (Quartus project/compile flow script) present in the repo/working directory for this to succeed.

### 4.2 Parse silicon metrics

```bash
make parse
```
Greps the Quartus `.fit.rpt`, `.sta.rpt`, `.map.rpt`, and `.pow.rpt` reports and prints a summary:
- Area: logic elements, registers, 9-bit embedded multipliers used
- Timing: worst-case setup/hold slack, 85°C Fmax
- Optimization: retiming gain
- Power: total, core dynamic, core static thermal dissipation

Run `make syn` first — `make parse` just reads the reports Quartus produces.

---

## 5. ASIC Flow (LibreLane + Sky130 PDK)

This is the RTL-to-GDSII hardening flow, driven by `config.json`.

### 5.1 Key `config.json` settings to know

| Setting | Value | Meaning |
|---|---|---|
| `DESIGN_NAME` | `mac_engine_2` | Top module to harden |
| `VERILOG_FILES` | `axi_skid_buffer.sv`, `mac_engine_2.sv` | RTL sources fed to synthesis |
| `CLOCK_PORT` / `CLOCK_PERIOD` | `clk` / `10` ns | 100 MHz target clock |
| `FP_CORE_UTIL` | `56` | Target core utilization at floorplanning |
| `PL_TARGET_DENSITY` | `0.62` | Placement density target |
| `SYNTH_STRATEGY` | `DELAY 3` | Yosys synthesis strategy tuned for delay |
| `VDD_NETS` / `GND_NETS` | `vccd1` / `vssd1` | Power/ground net names (Sky130 user-area convention) |
| `DEFAULT_CORNER` | `max_ss_100C_1v60` | Signoff timing corner |

Edit `config.json` directly if you want to retarget clock period, utilization, density, or synthesis strategy.

### 5.2 Run the full flow

```bash
make flow
```
Runs `librelane ~/icprojects/macunit/config.json` — the complete RTL-to-GDSII flow (synthesis → floorplan → placement → CTS → routing → signoff checks). Outputs land under `runs/<timestamp>/`.

### 5.3 Run a synthesis-strategy exploration

```bash
make strat
```
Runs LibreLane's `SynthesisExploration` flow, which sweeps multiple synthesis strategies against `config.json` so you can compare PPA trade-offs before committing to one.

### 5.4 Regenerate layout view only

```bash
make layout
```
Runs LibreLane's `openinklayout` flow against the **last completed run** (`--last-run`) — useful for re-rendering/inspecting layout without re-running the whole flow.

### 5.5 Parse ASIC metrics

```bash
make parse-asic
```
Finds the most recent `runs/**/metrics.csv` and prints:
- **Area:** cell count, core area, utilization, I/O pin count
- **Timing:** max frequency (derived from `ASIC_PERIOD_NS = 10` ns and worst setup slack), setup/hold slack, setup/hold clock skew, setup/hold/slew violation counts
- **Power:** total power (mW)
- **Physical:** wirelength, DRC error count, LVS error count

> `ASIC_PERIOD_NS` in the `Makefile` is currently hardcoded to `10` (matching `CLOCK_PERIOD` in `config.json`). If you change the clock period in `config.json`, update `ASIC_PERIOD_NS` to match, or the derived Max Freq figure will be wrong.

### 5.6 Clean up LibreLane runs

```bash
make clean-runs
```
Deletes the entire `runs/` directory — use this to force a clean flow re-run (e.g. after editing `config.json`).

**Typical ASIC iteration loop:**
```bash
make clean-runs && make flow && make parse-asic
```

---

## 6. Troubleshooting

- **`librelane: command not found`** — LibreLane isn't on `PATH`; re-source your Nix shell/environment or check your install method.
- **`make flow` fails to find `config.json`** — the target uses a hardcoded absolute path (`~/icprojects/macunit/config.json`). Either clone the repo there or edit the path in the `Makefile`.
- **`make parse-asic` prints blank fields** — you likely haven't run `make flow` yet, or the run failed before `metrics.csv` was generated; check `runs/<latest>/` logs.
- **`make syn` / `make parse` do nothing useful on Linux/macOS** — the FPGA target assumes a Windows Quartus install invoked via `cmd.exe`; this target is Windows-only as written.
- **Verilator lint errors on testbench delays** — make sure you're calling `make lint` (which only lints `$(SRC)`, not the testbench) — `LINT_FLAGS` includes `--timing` specifically so RTL-only linting doesn't choke on delay constructs pulled in transitively.

---

For design rationale, the pipeline stage breakdown, and PPA results, see the [full writeup](https://docs.google.com/document/d/1UoCRIFNNci7FxWnKNwOGujuK3Nf-7zGUwzDJemCEfBY/edit?usp=sharing).