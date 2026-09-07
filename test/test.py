# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


@cocotb.test()
async def test_trng(dut):
    dut._log.info("==================================================")
    dut._log.info("   Tiny Tapeout TRNG Cocotb 100 MHz Testbench     ")
    dut._log.info("==================================================")

    # 1. Start 100 MHz clock (10 ns clock period)
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # 2. Reset Sequence
    dut._log.info("Applying reset...")
    dut.ena.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)

    # Release reset and enable TRNG
    dut._log.info("Releasing reset and enabling TRNG...")
    dut.rst_n.value = 1
    dut.ena.value = 1
    dut.ui_in.value = 1  # ui_in[0] = enable

    # Wait 2 cycles for internal reset release
    await ClockCycles(dut.clk, 2)

    # 3. Verify IO direction (uio_oe bits 0..2 should be outputs: 0x07)
    assert dut.uio_oe.value == 0x07, f"Expected uio_oe=0x07, got {dut.uio_oe.value}"
    dut._log.info("IO Direction verified: uio_oe = 0x07 (bits 0..2 are outputs)")

    # 4. Verify initial health status (uio_out[1] == 1)
    uio_val = int(dut.uio_out.value)
    healthy = (uio_val >> 1) & 1
    assert healthy == 1, f"Expected healthy=1, got {healthy}"
    dut._log.info("Health Watchdog status verified: HEALTHY (1)")

    # 5. Collect random bytes
    dut._log.info("Waiting for random bytes from TRNG...")
    collected_bytes = []
    max_cycles = 15000  # Timeout limit

    while len(collected_bytes) < 10 and max_cycles > 0:
        await RisingEdge(dut.clk)
        max_cycles -= 1

        uio = int(dut.uio_out.value)
        byte_valid = uio & 1
        is_healthy = (uio >> 1) & 1

        if byte_valid == 1:
            byte_val = int(dut.uo_out.value)
            collected_bytes.append(byte_val)
            dut._log.info(
                f"Byte #{len(collected_bytes)} received: 0x{byte_val:02x} "
                f"(binary: {byte_val:08b}), healthy: {is_healthy}"
            )
            assert is_healthy == 1, "Health watchdog reported failure during byte collection!"

    # 6. Verify collection results
    assert len(collected_bytes) >= 10, f"Timeout! Only collected {len(collected_bytes)} bytes."
    dut._log.info(f"Successfully collected {len(collected_bytes)} random bytes: {[hex(b) for b in collected_bytes]}")

    # Check that bytes are non-trivial (entropy is being generated)
    unique_bytes = set(collected_bytes)
    dut._log.info(f"Unique byte count: {len(unique_bytes)} / {len(collected_bytes)}")
    assert len(unique_bytes) > 1, "Degenerate TRNG output: all bytes were identical!"

    dut._log.info("==================================================")
    dut._log.info("   ALL COCOTB TEST ASSERTIONS PASSED!             ")
    dut._log.info("==================================================")
