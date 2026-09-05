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
# Automated Silicon Metrics Parser
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