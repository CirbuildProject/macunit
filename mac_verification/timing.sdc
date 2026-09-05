# ==========================================
# Synopsys Design Constraints (.sdc)
# ==========================================
# Define the base clock: 150 MHz = 6.666 ns period
create_clock -name clk -period 6.666 [get_ports {clk}]

# Automatically calculate realistic jitter and clock network skew
derive_clock_uncertainty

# Treat reset as an asynchronous false path so the synthesizer 
# doesn't waste effort trying to close timing on the reset tree.
set_false_path -from [get_ports {rst_n}]