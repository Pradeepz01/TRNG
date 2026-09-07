![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# 🎲 True Random Number Generator (TRNG) for Tiny Tapeout (Sky130)

A hardware-based True Random Number Generator implemented in Verilog for submission to [Tiny Tapeout](https://tinytapeout.com/) using the SkyWater 130nm process.

- [Datasheet Documentation](docs/info.md)

---

## 📐 Architecture Overview

```
Ring Oscillators (Prime Stages) -> Entropy Mixer -> Sampler -> Von Neumann Corrector -> Health Test -> Output Buffer
```

### Features:
1. **8 Ring Oscillators with Prime Stages**: Stage lengths of 5, 7, 11, 13, 17, 19, 23, and 29 inverting stages to prevent physical injection-locking on the chip.
2. **Standard Cell Primitives**: Direct instantiation of `sky130_fd_sc_hd__nand2_1` and `sky130_fd_sc_hd__inv_1` with `(* keep = "true" *)` attributes to prevent synthesis tools from collapsing the delay chains.
3. **Entropy Mixer**: XOR reduction tree across all 8 asynchronous oscillators.
4. **Metastability Protected Sampler**: 2-stage flip-flop synchronizer clocked by the 100 MHz system clock.
5. **Von Neumann Debiasing**: Strips process-induced bias by evaluating non-overlapping pairs (`01` -> `1`, `10` -> `0`, `00`/`11` discarded).
6. **Health Watchdog**: Repetition count watchdog alarm triggered if 16 consecutive identical bits occur.
7. **8-Bit Byte Output**: Assembles random bits into bytes for Tiny Tapeout output pins.

---

## 📌 Pinout

| Pin | Direction | Signal | Description |
| :--- | :--- | :--- | :--- |
| `ui_in[0]` | Input | `enable` | Enables the ring oscillator array (active high) |
| `ui_in[7:1]`| Input | - | Unused (tied off) |
| `uo_out[7:0]`| Output | `random_data[7:0]` | 8-bit random byte output |
| `uio_out[0]`| Output | `byte_valid` | High for 1 cycle when a new random byte is available |
| `uio_out[1]`| Output | `healthy` | Continuous health monitor (1 = healthy, 0 = repetition fault) |
| `uio_out[2]`| Output | `entropy_mon` | Raw XOR entropy monitor bit (for oscilloscope/probing) |
| `uio_out[7:3]`| Output | - | Unused (tied to 0) |
| `clk` | Input | `clk` | 100 MHz system clock |
| `rst_n` | Input | `rst_n` | Active-low reset |

---

## 🧪 Simulation & Verification

### Running the Cocotb Testbench (100 MHz)
```bash
cd test
make -B
```

### Checking ASIC Synthesis (Yosys + Sky130)
```bash
yosys -p "read_liberty -lib /home/pradeep/vsd/OpenLane/pdks/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib; read_verilog src/project.v; synth -top tt_um_trng; check -assert; stat"
```
