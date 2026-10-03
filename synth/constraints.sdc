# Timing constraints for systolic_array_hw (100 MHz target).
# Written for Quartus but uses only standard SDC commands.


# 100 MHz clock (10 ns period)
create_clock -name clk -period 10.000 [get_ports clk]

# Clock uncertainty margin
set_clock_uncertainty 0.200 [get_clocks clk]

# Asynchronous active-low reset: not timed against the clock
set_false_path -from [get_ports rst_n]

# I/O delays (placeholders: assume 2 ns of external logic on each side).
# Replace with real board/interface numbers when they are known.
set_input_delay  -clock clk 2.000 [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_output_delay -clock clk 2.000 [all_outputs]