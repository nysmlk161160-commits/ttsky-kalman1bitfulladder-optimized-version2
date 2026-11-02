# Kalman ASIC — shared top-level ALU experiment

**Suggested repository:** `ttsky-kalman1bit-shared-alu`

This is a controlled RTL architecture experiment derived from
[`ttsky-kalman1bitfulladder-optimized`](https://github.com/nysmlk161160-commits/ttsky-kalman1bitfulladder-optimized).

Only the **top-level** arithmetic scheduling is changed:

- Original: two separate 11-bit arithmetic expressions (`S=P+R`, `delta=Z-X`) and one shared 10-bit X/P update adder/subtractor.
- This experiment: **one** time-multiplexed 11-bit add/subtract expression for all four operations.
- The original `kalman_div1` and `kalman_mul1` single-bit serial engines, control state sequence, pins, test vectors, `src/config.json` and clock-period target are preserved.

For installation in a new template, read **README_REPLACE.txt**.

## Hypothesis — to test, not to assume

The change can reduce arithmetic logic duplication, but new operand MUXing may offset the gain and may change critical-path timing. Compare **final Standard Cell Area, post-route Core Utilisation, worst setup/hold, routed DRC/LVS and actual latency** at the same constraints.

## Relevant baseline (previous routed report)

- Final Standard Cell Area: 13,270.2 um^2
- Final Core Utilisation: 80.4582%
- 20 ns clock; worst setup slack +8.901932 ns, worst hold slack +0.109148 ns
- Normal RTL latency: 267 cycles (5.34 us @ 50 MHz)
- Normal gate-level observed latency: 268 cycles (5.36 us @ 50 MHz)

These **baseline** figures do not describe the new shared-ALU design.

### Protocol qualification

The shared-ALU schedule assumes the documented test sequence: input writes finish before `start`. Concurrent write-enable and start on the same clock edge are not supported by this variant; see `docs/info.md`.
