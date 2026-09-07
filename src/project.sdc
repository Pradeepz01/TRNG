# ==============================================================================
# Synopsys Design Constraints (SDC) for Tiny Tapeout TRNG
# Target Frequency: 100 MHz (Clock Period = 10.0 ns)
# ==============================================================================

# 1. Define 100 MHz clock on the main clock port
create_clock -name clk -period 10.000 [get_ports clk]

# 2. Clock uncertainty / jitter margin (200 ps)
set_clock_uncertainty 0.200 [get_clocks clk]
set_clock_transition 0.150 [get_clocks clk]

# 3. Input Delays (assuming 20% of clock period external delay)
set_input_delay -clock clk 2.000 [get_ports {ui_in[*]}]
set_input_delay -clock clk 2.000 [get_ports {uio_in[*]}]
set_input_delay -clock clk 2.000 [get_ports rst_n]
set_input_delay -clock clk 2.000 [get_ports ena]

# 4. Output Delays (assuming 20% of clock period external setup time)
set_output_delay -clock clk 2.000 [get_ports {uo_out[*]}]
set_output_delay -clock clk 2.000 [get_ports {uio_out[*]}]
set_output_delay -clock clk 2.000 [get_ports {uio_oe[*]}]

# 5. False paths (asynchronous inputs / monitor outputs)
set_false_path -through [get_ports {uio_out[2]}]
