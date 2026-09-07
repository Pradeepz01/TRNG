# 🎲 TRNG — True Random Number Generator

A hardware-based True Random Number Generator (TRNG) implemented in Verilog, designed for submission to [Tiny Tapeout](https://tinytapeout.com/). This project harvests entropy from the physical unpredictability of silicon — gate delays, temperature drift, and manufacturing variation — to produce genuinely random bitstreams.

---

## 📐 Architecture Overview

![TRNG Architecture](https://github.com/user-attachments/assets/275a4d0d-8327-4b5a-bb4c-dfaa5d868c3d)

The design is a pipeline of modules, each with a distinct responsibility:

```
Ring Oscillators → Entropy Mixer → Sampler → Von Neumann Corrector → Health Test → Output Buffer
```

---

## 🔩 Module Breakdown

### 1. Ring Oscillator

A ring oscillator is a chain of inverters wired in a loop. Each inverter introduces a tiny, unpredictable delay caused by internal capacitance, temperature variation, and process-level manufacturing differences — making the oscillation frequency inherently noisy.

**The Verilog catch:** You can't just write:
```verilog
assign a = ~in;
assign b = ~a;
assign c = ~b;
```
The synthesizer will optimize the entire chain down to a single inverter. To preserve the actual hardware delay cells, inverters are instantiated explicitly using the sky130 standard cell library:
```verilog
sky130_fd_sc_hd__inv_1
```

---

### 2. Array of Ring Oscillators

Multiple ring oscillators are instantiated in parallel. The count is chosen based on Tiny Tapeout's area constraints. Running many ROs simultaneously increases the entropy pool and decorrelates the noise sources.

---

### 3. Entropy Mixer

Takes the parallel outputs of all ring oscillators and collapses them into a single entropy bit using XOR reduction.

**Example:**
```
RO outputs:  1 0 1 1 0 0 1 0
XOR result:  1⊕0⊕1⊕1⊕0⊕0⊕1⊕0 = 1   (five 1s → odd → output: 1)

RO outputs:  1 1 1 0 1 0 0 0
XOR result:  1⊕1⊕1⊕0⊕1⊕0⊕0⊕0 = 0   (four 1s → even → output: 0)
```

The output flips continuously as the RO states evolve. This logic can be extended in future versions (e.g., using CRC or hash-based mixing).

---

### 4. Sampler

Uses a **clock divider** on Tiny Tapeout's system clock to sample the entropy mixer output at a lower, asynchronous rate.

The system clock runs near 100 MHz, but not exactly — it drifts slightly (e.g., 99.997 MHz, 100.031 MHz). Dividing it down to ~10 MHz and sampling an RO chain that runs at its own independent frequency means the sample point is effectively random relative to the entropy source. This **frequency mismatch** is a feature, not a bug.

---

### 5. Von Neumann Corrector

Removes **statistical bias** introduced by unequal 0/1 probabilities in the raw bitstream.

**Algorithm (Von Neumann debiasing):**
| Input Pair | Output |
|------------|--------|
| `00`       | discard |
| `01`       | `1` |
| `10`       | `0` |
| `11`       | discard |

**Example:**
```
Before:  1 1 1 1 1 1 1 0 1 1 1 1 1 1 1 0 1 1 1 1
After:   1 0 1 0 0 1 1 0 1 ...
```
The output is more balanced and closer to a uniform distribution.

---

### 6. Health Test

Monitors the output stream for statistical anomalies **without modifying the data**. Acts as a watchdog — it only raises an alarm.

**Example:**
```
Input:  1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1  →  ❌ ERROR (stuck high)
Input:  1 0 1 0 1 0 0 1 1 0 1 0 0 1 0 1 1 0 1 0  →  ✅ PASS
```

If the health test fails, downstream logic is notified so the output can be gated or flagged.

---

### 7. Output Buffer

Accumulates N valid (post-corrector, post-health-check) bits and assembles them into a complete random word for output. Acts as the final stage before data is consumed by the user or an external interface.

---

### 8. Top Module (`tt_um_pradeepz01_trng`)

Wires all pipeline modules together into a complete synthesizable Tiny Tapeout design conforming to the standard TT pinout.

### 📌 Tiny Tapeout Pinout

| Pin | Direction | Signal | Description |
| :--- | :--- | :--- | :--- |
| `ui_in[0]` | Input | `enable` | Enables the ring oscillator array (active high) |
| `ui_in[7:1]`| Input | - | Unused (tied off) |
| `uo_out[7:0]`| Output | `random_data[7:0]` | 8-bit random byte output |
| `uio_out[0]`| Output | `data_valid` | High for 1 cycle when a new random byte is available |
| `uio_out[1]`| Output | `healthy` | Continuous health monitor (1 = healthy, 0 = repetition fault) |
| `uio_out[2]`| Output | `entropy_mon` | Raw XOR entropy monitor bit (for oscilloscope/probing) |
| `uio_out[7:3]`| Output | - | Unused (tied to 0) |
| `clk` | Input | `clk` | System clock (e.g. 50 MHz) |
| `rst_n` | Input | `rst_n` | Active-low reset |

---

## 🛠️ Implementation Notes

- **Target platform:** [Tiny Tapeout](https://tinytapeout.com/) (Sky130 PDK)
- **HDL:** Verilog-2005 / SystemVerilog
- **Standard cells used for RO:** `sky130_fd_sc_hd__nand2_1` and `sky130_fd_sc_hd__inv_1` with `(* keep = "true" *)`
- **Total Silicon Area:** ~184 standard cells (< 20% of a 1x1 TT tile)
- **Entropy source:** Gate delay variations across 8 staggered ring oscillators (5 to 19 stages)

---

## 🧪 Simulation & Verification

### Running the Testbench (Icarus Verilog)
```bash
iverilog -g2012 -DSIMULATION -o tb_trng.vvp rtl/project.v test/tb_trng.v
vvp tb_trng.vvp
```

### Checking ASIC Synthesis (Yosys)
```bash
yosys -p "read_liberty -lib /home/pradeep/vsd/OpenLane/pdks/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib; read_verilog rtl/project.v; synth -top tt_um_pradeepz01_trng; check -assert; stat"
```

---

## 📄 License

This project is open-source. See [LICENSE](LICENSE) for details.

