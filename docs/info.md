# Kalman correction accelerator — 1-bit serial arithmetic and shared top-level adder

This Q4.6 Kalman update accelerator preserves the original 1-bit serial divider and multiplier, but time-multiplexes the top-level **11-bit parallel adder/subtractor** across four operations.

- `K = floor(64 * P / (P + R))`, K=0 for P+R=0
- `X_new = (X + floor(K*(Z-X)/64)) mod 1024`
- `P_new = (P - floor(K*P/64)) mod 1024`

Z and X are signed 10-bit two's-complement inputs. P and R are unsigned 10-bit inputs.

## Datapath scheduling

| Control phase | One shared 11-bit ALU operation |
| --- | --- |
| IDLE with `start` | `S = P + R` |
| DIV_START | `delta = Z - X` (in parallel with divider start) |
| X_WAIT when `mul_done` | `X_out = X + mul_result` (low 10 bits) |
| P_WAIT when `mul_done` | `P_out = P - mul_result` (low 10 bits) |

The divider and multiplier continue to each use a single one-bit full-adder; only the top-level parallel logic has been rescheduled/shared. Normal-path operation latency should remain **267 cycles** at 20 ns clock (RTL baseline), pending simulation of this candidate.

## Interface

- `ui_in[7:0]`: input byte
- `uio_in[1:0]`: write address 0=Z, 1=X, 2=P, 3=R
- `uio_in[2]`: select low 8 / upper 2 bits
- `uio_in[3]`: write enable, while idle
- `uio_in[4]`: start update
- `uio_in[5]`: select read result (0=X, 1=P)
- `uo_out[7:0]`: selected result byte
- `uio_out[7]`: ready, `uio_out[6]`: busy

## Research question

Does scheduling the four top-level add/sub operations onto one 11-bit unit reduce standard-cell area, and how does that affect worst-case timing, buffer insertion, and routed utilisation? Use the identical clock period, tile, constraints, test vectors and PPA reporting stage as the baseline.

Do not claim an area or power improvement until post-PNR metrics have been measured.

## Protocol assumption

Write transactions and `start` are separate control actions, as in the repository's 65-vector Cocotb test. Do **not** assert write-enable (`uio_in[3]`) and start (`uio_in[4]`) simultaneously: the shared-ALU version delays delta capture by one clock and can then see a newly written Z/X, whereas the baseline computed delta from pre-write operands. Concurrent write+start is outside the supported protocol of this experiment.
