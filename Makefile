# ==========================================
# MAC Engine Verification Makefile
# ==========================================

# Toolchain Definitions
CC      = iverilog
SIM     = vvp
LINTER  = verilator
VIEWER  = gtkwave

# Flags
# -g2012 enforces SystemVerilog 2012 standard
CFLAGS      = -g2012 -Wall
# --timing allows Verilator to parse the testbench delays without crashing
LINT_FLAGS  = --lint-only -Wall --timing

# Source Files
SRC     = mac_engine_2.sv axi_skid_buffer.sv
TB      = tb_mac_engine_3.sv
OUT     = sim.vvp
WAVE    = mac_waves.vcd

# ==========================================
# Targets
# ==========================================

# Default target: Compiles and runs the simulation
all: run

# Compile the SystemVerilog files
compile:
	@echo "----------------------------------------"
	@echo "🔨 Compiling RTL and Testbench..."
	@echo "----------------------------------------"
	$(CC) $(CFLAGS) -o $(OUT) $(SRC) $(TB)

# Run the simulation executable
run: compile
	@echo "----------------------------------------"
	@echo "🚀 Running Simulation..."
	@echo "----------------------------------------"
	$(SIM) $(OUT)

# Run Verilator strictly to catch synthesis hazards
lint:
	@echo "----------------------------------------"
	@echo "🔍 Linting RTL with Verilator..."
	@echo "----------------------------------------"
	$(LINTER) $(LINT_FLAGS) $(SRC)

# Open the waveforms in GTKWave in the background
wave:
	@echo "----------------------------------------"
	@echo "🌊 Opening Waveforms..."
	@echo "----------------------------------------"
	$(VIEWER) $(WAVE) &

# Clean up generated files
clean:
	@echo "----------------------------------------"
	@echo "🧹 Cleaning Build Files..."
	@echo "----------------------------------------"
	rm -f $(OUT) $(WAVE)

data: 
	@echo "----------------------------------------"
	@echo "💾 Generating Test Data..."
	@echo "----------------------------------------"
	python3 mac_golden_model.py


# Define the Windows Quartus Shell executable (Update version as needed)
QUARTUS_CMD = C:\intelFPGA_lite\20.1\quartus\bin64\quartus_sh.exe

syn:
	@echo "----------------------------------------"
	@echo "🏭 Synthesizing for Intel MAX 10..."
	@echo "----------------------------------------"
	cmd.exe /c "$(QUARTUS_CMD) -t build.tcl"

# ==========================================
# Automated Silicon Metrics Parser (Quartus)
# ==========================================
parse:
	@echo "=================================================="
	@echo " 📊 SILICON METRICS SUMMARY (INTEL MAX 10)"
	@echo "=================================================="
	@echo "[AREA] Logic Elements :" `grep -m 1 "^; Total logic elements" mac_engine.fit.rpt | tr -d '\r' | awk -F';' '{print $$3}' | xargs`
	@echo "[AREA] Registers      :" `grep -m 1 "^;[ \t]*Dedicated logic registers" mac_engine.fit.rpt | tr -d '\r' | awk -F';' '{print $$3}' | xargs`
	@echo "[AREA] DSP 9-bit      :" `grep -m 1 "^; Embedded Multiplier 9-bit elements" mac_engine.fit.rpt | tr -d '\r' | awk -F';' '{print $$3}' | xargs`
	@echo "--------------------------------------------------"
	@echo "[TIMING] Setup Slack  :" `grep -m 1 "Worst-case setup slack" mac_engine.sta.rpt | tr -d '\r' | awk '{print $$7}'` "ns"
	@echo "[TIMING] Hold Slack   :" `grep -m 1 "Worst-case hold slack" mac_engine.sta.rpt | tr -d '\r' | awk '{print $$7}'` "ns"
	@echo "[TIMING] 85C Fmax     :" `grep -m 1 -A 4 "; Slow 1200mV 85C Model Fmax Summary" mac_engine.sta.rpt | tail -n 1 | tr -d '\r' | awk -F';' '{print $$2}' | xargs`
	@echo "--------------------------------------------------"
	@echo "[OPT] Retiming Gain   :" `grep -m 1 "register retiming complete: estimated slack improvement" mac_engine.map.rpt | tr -d '\r' | awk -F'of ' '{print $$2}'`
	@echo "--------------------------------------------------"
	@echo "[POWER] Total Thermal :" `grep -m 1 "^; Total Thermal Power Dissipation" mac_engine.pow.rpt | tr -d '\r' | awk -F';' '{print $$3}' | xargs`
	@echo "[POWER] Core Dynamic  :" `grep -m 1 "^; Core Dynamic Thermal Power Dissipation" mac_engine.pow.rpt | tr -d '\r' | awk -F';' '{print $$3}' | xargs`
	@echo "[POWER] Core Static   :" `grep -m 1 "^; Core Static Thermal Power Dissipation" mac_engine.pow.rpt | tr -d '\r' | awk -F';' '{print $$3}' | xargs`
	@echo "=================================================="



flow:
	@echo "=================================================="
	@echo "🚀 INITIATING LIBRELANE FLOW"
	@echo "=================================================="
	librelane ~/icprojects/macunit/config.json

strat:
	librelane --flow SynthesisExploration ~/icprojects/macunit/config.json

layout:
	@echo "=================================================="
	@echo "🔍 RUNNING OpenINK LAYOUT"
	@echo "=================================================="
	librelane --last-run --flow openinklayout ~/icprojects/macunit/config.json

clean-runs:
	@echo "=================================================="
	@echo "🧹 CLEANING LIBRELANE RUNS"
	@echo "=================================================="
	rm -rf runs/

# ==========================================
# OpenLane / Sky130 Metrics Parser
# ==========================================
ASIC_METRICS = $(shell find runs/ -name "metrics.csv" -type f 2>/dev/null | xargs ls -t 2>/dev/null | head -n 1)
ASIC_PERIOD_NS = 10

parse-asic:
	@echo "=================================================="
	@echo " 📊 SILICON METRICS SUMMARY (SKY130 PDK)"
	@echo "=================================================="
	@echo "[AREA] Cell Count     :" `awk -F',' '$$1=="design__instance__count"{print $$2}' $(ASIC_METRICS)`
	@echo "[AREA] Core Area      :" `awk -F',' '$$1=="design__core__area"{printf "%.2f um^2", $$2}' $(ASIC_METRICS)`
	@echo "[AREA] Utilization    :" `awk -F',' '$$1=="design__instance__utilization"{printf "%.1f%%", $$2*100}' $(ASIC_METRICS)`
	@echo "[AREA] I/O Pins       :" `awk -F',' '$$1=="design__io"{print $$2}' $(ASIC_METRICS)`
	@echo "--------------------------------------------------"
	@echo "[TIMING] Max Freq     :" `awk -F',' -v period=$(ASIC_PERIOD_NS) '$$1=="timing__setup__ws"{cp = period - $$2; if(cp > 0) printf "%.1f MHz", 1000 / cp; else print "ERROR"}' $(ASIC_METRICS)`
	@echo "[TIMING] Setup Slack  :" `awk -F',' '$$1=="timing__setup__ws"{printf "%.3f ns", $$2}' $(ASIC_METRICS)`
	@echo "[TIMING] Hold Slack   :" `awk -F',' '$$1=="timing__hold__ws"{printf "%.3f ns", $$2}' $(ASIC_METRICS)`
	@echo "[TIMING] Setup Skew   :" `awk -F',' '$$1=="clock__skew__worst_setup"{printf "%.3f ns", $$2}' $(ASIC_METRICS)`
	@echo "[TIMING] Hold Skew    :" `awk -F',' '$$1=="clock__skew__worst_hold"{printf "%.3f ns", $$2}' $(ASIC_METRICS)`
	@echo "[TIMING] Setup Vio    :" `awk -F',' '$$1=="timing__setup_vio__count"{print $$2}' $(ASIC_METRICS)`
	@echo "[TIMING] Hold Vio     :" `awk -F',' '$$1=="timing__hold_vio__count"{print $$2}' $(ASIC_METRICS)`
	@echo "[TIMING] Slew Vio     :" `awk -F',' '$$1=="design__max_slew_violation__count"{print $$2}' $(ASIC_METRICS)`
	@echo "--------------------------------------------------"
	@echo "[POWER] Total Power   :" `awk -F',' '$$1=="power__total"{printf "%.2f mW", $$2*1000}' $(ASIC_METRICS)`
	@echo "--------------------------------------------------"
	@echo "[PHYSICAL] Wirelength :" `awk -F',' '$$1=="route__wirelength"{printf "%.2f um", $$2}' $(ASIC_METRICS)`
	@echo "[PHYSICAL] DRC Errors :" `awk -F',' '$$1=="magic__drc_error__count"{print $$2}' $(ASIC_METRICS)`
	@echo "[PHYSICAL] LVS Errors :" `awk -F',' '$$1=="design__lvs_error__count"{print $$2}' $(ASIC_METRICS)`
	@echo "=================================================="