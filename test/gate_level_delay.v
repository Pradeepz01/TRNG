// SPDX-FileCopyrightText: © 2024 Tiny Tapeout
// SPDX-License-Identifier: Apache-2.0

`ifndef GATE_LEVEL_DELAY_V
`define GATE_LEVEL_DELAY_V

`timescale 1ns / 1ps
`default_nettype none

// Provide propagation delay for ring oscillator cells during gate-level simulation.
// In silicon, inverters have ~30-50ps analog delay and thermal jitter.
// In digital event-driven simulation (Icarus), zero-delay inverter loops cause an infinite
// delta-cycle lock. Defining propagation delays allows the ring oscillators to oscillate properly.

`define SKY130_FD_SC_HD__INV_FUNCTIONAL_PP_V
`celldefine
module sky130_fd_sc_hd__inv (
    output wire Y,
    input  wire A,
    input  wire VPWR,
    input  wire VGND,
    input  wire VPB,
    input  wire VNB
);
    assign #0.2 Y = ~A;
endmodule
`endcelldefine

`define SKY130_FD_SC_HD__NAND2_FUNCTIONAL_PP_V
`celldefine
module sky130_fd_sc_hd__nand2 (
    output wire Y,
    input  wire A,
    input  wire B,
    input  wire VPWR,
    input  wire VGND,
    input  wire VPB,
    input  wire VNB
);
    assign #0.2 Y = ~(A & B);
endmodule
`endcelldefine

`endif
