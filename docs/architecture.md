# Architecture and Timing Notes

## 1. Overview

A 4x4 output-stationary systolic array computing `C = A x B` with signed 8-bit
operands. Each processing element (PE) owns one output element: PE(i,j) holds
`C[i][j]` in its accumulator. `A` streams in from the left, `B` from the top,
and both are forwarded one PE per clock.

## 2. Hierarchy

```
systolic_array_hw          (rtl/systolic_array_hw.sv)   optional wrapper
 └─ systolic_array_top     (rtl/systolic_array_top.sv)  ARRAY_N x ARRAY_N grid
     └─ pe  x 16           (rtl/pe.sv)                  MAC cell
```

## 3. Processing element

Inputs `left_in` (data) and `top_in` (weight), both signed `DATA_WIDTH` bits.

Every rising clock edge (async active-low reset clears everything):

| Register | Update |
|----------|--------|
| `r_data` -> `right_out` | `left_in` |
| `r_weight` -> `bot_out` | `top_in` |
| `r_acc` -> `acc_out` | `clear ? left_in*top_in : r_acc + left_in*top_in` |

Accumulator width is `2*DATA_WIDTH + 2` = 18 bits. Note `clear` *loads the new
product*; it does not set the accumulator to zero. With zero inputs, though, a
single `clear` cycle does zero it.

## 4. Core array (`systolic_array_top`)

- Parameters: `DATA_WIDTH` (8), `ARRAY_N` (4).
- Ports are packed vectors (not unpacked arrays), which keeps them portable
  across simulators:
  - `row_in_flat`, `col_in_flat`: element `k` at `[k*DATA_WIDTH +: DATA_WIDTH]`
  - `row_out_flat`: element `[r][c]` at `[(r*ARRAY_N+c)*ACC_W +: ACC_W]`,
    where `ACC_W = 2*DATA_WIDTH + $clog2(ARRAY_N)`
- All `ARRAY_N^2` accumulators are visible on `row_out_flat`; nothing leaves
  through the array edges.
- `valid_out` is `valid_in` delayed by `2*ARRAY_N-1` cycles.

## 5. Input skew

At cycle `t` (counting from 0 at the first `valid_in` cycle):

- row `i` carries `A[i][t-i]`
- column `j` carries `B[t-j][j]`
- values outside `0 <= k < ARRAY_N` are 0

Since operands move one PE per cycle, PE(i,j) sees `A[i][k]` and `B[k][j]` on
the same cycle `t = k + i + j`, so each product lands in the right accumulator.
The stream is `2*ARRAY_N-1` = 7 cycles long.

## 6. Timing (N = 4)

| Event | Cycle (0-indexed) |
|-------|-------------------|
| First product at PE(0,0) | 0 |
| First product at PE(i,j) | `i+j` |
| Last product at PE(3,3) | `3*(N-1)` = 9 |
| `done` rises | about `N+1` cycles after the last `valid_in` cycle (2 cycles of margin) |

`done` is deliberately conservative: it waits `ARRAY_N` cycles after `valid_in`
falls so the last operand has reached the far corner.

## 7. Hardware wrapper (`systolic_array_hw`)

| Port | Dir | Description |
|------|-----|-------------|
| `row_in_flat`, `col_in_flat`, `valid_in`, `clear` | in | Same as the core |
| `busy` | out | High while streaming or draining |
| `done` | out | Results final; sticky until the next `valid_in` |
| `rd_addr` | in | Result index `r*ARRAY_N + c` |
| `rd_data` | out | Registered result, valid one clock after `rd_addr` |

This replaces the 288-bit result bus (16 x 18 bits) with a small read port.

Usage: (optional) one `clear` cycle with zero inputs while idle -> stream the
skewed inputs -> wait for `done` -> sweep `rd_addr` and read `rd_data`.

## 8. Verification summary

| Testbench | Type |
| `tb_pe` | Self-checking, reference model, 519 checks |
| `tb_systolic_array_hw` | Self-checking, `A x B` vs software reference, 8 runs |
| `tb_systolic_array_top` | Smoke test, prints the result matrix, no expected-value check |

Simulated on Icarus Verilog and Verilator; lint-clean with `verilator -Wall`.

## 9. Synthesis

`synth/synth.ys` is a technology-independent Yosys flow (LUT6 mapping). Yosys
0.33 reports roughly 3,370 LUT6 and 504 flip-flops for `systolic_array_hw`.
Multipliers are built from LUTs because no DSP mapping is used in that flow, so
a vendor flow (e.g. Quartus targeting DSP blocks) will use far fewer LUTs.
Fmax has not been measured. `synth/constraints.sdc` sets a 100 MHz target for
that flow and has not yet been run through a timing analyzer.

## 10. Limitations

- Only `ARRAY_N = 4`, `DATA_WIDTH = 8` is tested. `pe.sv` hard-codes the
  accumulator width as `2*DATA_WIDTH + 2`, which matches the top level only
  when `ARRAY_N = 4`.
- `clear` is global: it can zero the array only when idle, and cannot overlap
  one matrix's drain with the next one's start.
- No overflow detection: accumulators are sized for 8-bit signed inputs at 4x4.
  