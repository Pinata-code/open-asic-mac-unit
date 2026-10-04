# Systolic-Matrix-Accelerator

An open-source, hardware accelerator implementing an 8-bit matrix multiplication data path via systolic array architecture. Written in SystemVerilog, the design features pipelined processing elements (PEs) optimized for Multiply-Accumulate (MAC) operations, validated through automated synthesis and simulation toolflows.

## Systolic Array Matrix Multiplier

A 4×4 systolic-array matrix multiplier in SystemVerilog (signed 8-bit inputs,
18-bit accumulators). The core is written with `generate` loops and an `ARRAY_N`
parameter, but only `ARRAY_N = 4` has been tested (see
[Limitations](#limitations)).

Verified in simulation on Icarus Verilog and Verilator, and lint-clean under
`verilator -Wall`. It has not been synthesized yet.

---

## Architecture

Each processing element (PE) multiplies the data arriving from its left by the
weight arriving from above, adds the product to a local accumulator, and
forwards both operands (registered) to its right and bottom neighbours. There is
no global data bus.

```text
             col_in[0]   col_in[1]   col_in[2]   col_in[3]
                 |           |           |           |
                 v           v           v           v
row_in[0] --> [PE 0,0] --> [PE 0,1] --> [PE 0,2] --> [PE 0,3]
                 |           |           |           |
row_in[1] --> [PE 1,0] --> [PE 1,1] --> [PE 1,2] --> [PE 1,3]
                 |           |           |           |
row_in[2] --> [PE 2,0] --> [PE 2,1] --> [PE 2,2] --> [PE 2,3]
                 |           |           |           |
row_in[3] --> [PE 3,0] --> [PE 3,1] --> [PE 3,2] --> [PE 3,3]
```

The result `C = A x B` stays in the accumulators: PE(i,j) holds `C[i][j]`.
Nothing flows out of the array edges.

### Modules

| File | Purpose |
| `rtl/pe.sv` | Signed MAC with operand forwarding registers, async active-low reset, and a `clear` input |
| `rtl/systolic_array_top.sv` | Core `ARRAY_N x ARRAY_N` grid. Packed (flat) ports, exposes all accumulators on `row_out_flat` |
| `rtl/systolic_array_hw.sv` | Hardware-friendly wrapper: `busy`/`done` flags and a small read port (`rd_addr` -> `rd_data`) instead of the 288-bit result bus |

### Input skew

Operands must be fed with a diagonal skew. For `C = A x B` at cycle `t`
(`t = 0 .. 2*ARRAY_N-2`):

- row `i` carries `A[i][t-i]`
- column `j` carries `B[t-j][j]`
- anything outside `0 <= k < ARRAY_N` is 0

Hold `valid_in` high for those `2*ARRAY_N-1` cycles. Flat port packing: element
`k` is at bits `[k*DATA_WIDTH +: DATA_WIDTH]`; result `[r][c]` is at
`[(r*ARRAY_N+c)*ACC_W +: ACC_W]`.

### Using the hardware wrapper

1. (Optional) Pulse `clear` for one cycle while the inputs are zero and the
   array is idle. This zeroes every accumulator, so no reset is needed between
   runs.
2. Stream the skewed inputs with `valid_in` high.
3. Wait for `done` (sticky until the next `valid_in`).
4. Set `rd_addr = r*ARRAY_N + c` and read `rd_data` one clock later.

---

## Project structure

```text
docs/
  architecture.md             # system design & timing
rtl/
  pe.sv
  systolic_array_top.sv
  systolic_array_hw.sv
sim/
  tb_pe.sv                    # self-checking PE test (519 checks)
  tb_systolic_array_top.sv    # smoke test of the core; prints a matrix, does not check it
  tb_systolic_array_hw.sv     # self-checking A x B test via the wrapper
synth/
  constraints.sdc             # timing constraints (100 MHz target)
  synth.ys                    # Yosys synthesis script
Makefile
README.md
```

---

## Verification

| Testbench | What it checks |
| `tb_pe` | Reset, forwarding latency, accumulation, `clear` behaviour, signed corner cases, async reset, 500 random vectors against a reference model |
| `tb_systolic_array_hw` | Correctly skewed `A x B` against a software reference: `A x I`, hand-checkable matrices, signed extremes, 5 random matrices, run back-to-back using `clear` |
| `tb_systolic_array_top` | It feeds a fixed pattern and prints the result matrix; it does not compare against an expected value |

Each testbench prints `PASS` or `FAIL`.

### Running (Windows / Icarus Verilog)

```bat
iverilog -g2012 -o sim\sim_pe rtl\pe.sv sim\tb_pe.sv
vvp sim\sim_pe

iverilog -g2012 -o sim\sim_hw rtl\pe.sv rtl\systolic_array_top.sv rtl\systolic_array_hw.sv sim\tb_systolic_array_hw.sv
vvp sim\sim_hw

iverilog -g2012 -o sim\sim_out rtl\pe.sv rtl\systolic_array_top.sv sim\tb_systolic_array_top.sv
vvp sim\sim_out
```

### Running with `make` (Linux / macOS / WSL)

```text
make            # lint + all testbenches on Icarus and Verilator
make lint       # verilator -Wall
make iverilog   # all testbenches on Icarus
make verilator  # all testbenches on Verilator
make wave TB=tb_pe   # dump a VCD and open GTKWave
make clean
```

---

## Limitations

- Only `ARRAY_N = 4`, `DATA_WIDTH = 8` has been tested. `pe.sv` hard-codes its
  accumulator width as `2*DATA_WIDTH + 2`, which matches the top level only when
  `ARRAY_N = 4`. Other sizes need an `ACC_WIDTH` parameter on the PE.
- `clear` is global. It zeroes the accumulators only when the inputs are zero and
  the array is idle; it can't overlap one matrix's drain with the next one's
  start.
- `valid_out` of the core is a delayed copy of `valid_in` (latency
  `2*ARRAY_N-1`). It is not a "results final" flag for arbitrary stream
  lengths; use `done` from the wrapper for that.
- Synthesized in Yosys, LUT counts and Fmax were not     measured.
  
>>>>>>> 5830bbf (Added hardware accelerator RTL, testbenches, and synthesis documentations)
