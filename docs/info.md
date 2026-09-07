<!---
This file is used to generate your project datasheet on Tiny Tapeout.
-->

## How it works

This project implements a hardware True Random Number Generator (TRNG) targeting the SkyWater 130nm process (Sky130). It harvests entropy from physical jitter, manufacturing variation, and thermal noise in silicon.

### Architecture Pipeline:
1. **Ring Oscillator Array (8 Oscillators)**:
   - Built using Sky130 standard cells (`sky130_fd_sc_hd__nand2_1` and `sky130_fd_sc_hd__inv_1`) tagged with `keep` attributes.
   - **Injection Locking Defense**: Each oscillator has a distinct **prime number** of inverting stages (5, 7, 11, 13, 17, 19, 23, and 29 stages). Mutually prime lengths ensure no two oscillators share lower-order harmonics, preventing them from locking together on silicon.
2. **Entropy Mixer**:
   - An XOR reduction tree (`^ro_bus`) that combines all 8 asynchronous oscillator outputs into a single high-speed entropy bit stream.
3. **Sampler (100 MHz Clock Domain)**:
   - Uses a 2-stage DFF synchronizer to eliminate metastability hazards.
   - Divides down the 100 MHz clock to sample the asynchronous entropy stream.
4. **Von Neumann Debiasing Corrector**:
   - Compares pairs of consecutive samples: `01` yields `1`, `10` yields `0`, while `00` and `11` are discarded.
   - Removes statistical 0/1 bias caused by process variations.
5. **Health Test Watchdog (Repetition Count Test)**:
   - Continuously monitors the output stream.
   - Flags an alarm (`healthy = 0`) if 16 consecutive identical bits occur.
6. **Output Buffer**:
   - Accumulates 8 debiased bits and produces an 8-bit random byte on `uo_out[7:0]` with a 1-cycle `byte_valid` strobe on `uio_out[0]`.

## How to test

1. Apply power and set `rst_n = 0` for at least 10 clock cycles.
2. Set `rst_n = 1` and `ena = 1`.
3. Set `ui_in[0] = 1` to enable the ring oscillator array.
4. Verify that `uio_out[1]` (`healthy`) is high (1).
5. Monitor `uio_out[0]` (`byte_valid`). When `byte_valid` pulses high for 1 clock cycle, read the new random byte from `uo_out[7:0]`.
6. (Optional) Probe `uio_out[2]` on an oscilloscope to observe the raw XOR oscillator toggling.

## External hardware

None required. The design runs self-contained on the Tiny Tapeout demo board.
