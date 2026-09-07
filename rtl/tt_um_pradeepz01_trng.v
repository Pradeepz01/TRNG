/*
 * Tiny Tapeout Top Module for True Random Number Generator (TRNG)
 * Author: Pradeep
 * Target: Tiny Tapeout (Sky130)
 */

`default_nettype none

module tt_um_pradeepz01_trng (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // Active-high internal reset
    wire rst = !rst_n;

    // TRNG enable controlled by ena & ui_in[0]
    wire trng_en = ena & ui_in[0];

    wire [7:0] random_byte;
    wire       byte_valid;
    wire       healthy;
    wire       entropy_mon;

    // Instantiate core TRNG
    trng_top #(
        .NUM_RO(8),
        .SAMPLER_DIV(8),
        .DATA_WIDTH(8)
    ) u_trng (
        .clk(clk),
        .rst(rst),
        .enable(trng_en),
        .random_data(random_byte),
        .data_valid(byte_valid),
        .healthy(healthy),
        .entropy_bit_mon(entropy_mon)
    );

    // Pin Assignments:
    // Dedicated outputs: 8-bit random data byte
    assign uo_out = random_byte;

    // Bidirectional IO outputs:
    // bit 0: byte_valid strobe
    // bit 1: healthy flag (1 = healthy, 0 = repetition failure alarm)
    // bit 2: raw entropy bit monitor (for oscilloscope / observation)
    // bits 7:3: unused (tied to 0)
    assign uio_out[0]   = byte_valid;
    assign uio_out[1]   = healthy;
    assign uio_out[2]   = entropy_mon;
    assign uio_out[7:3] = 5'b00000;

    // Configure IO direction: bits 0..2 are outputs (1), bits 3..7 are inputs (0)
    assign uio_oe = 8'b0000_0111;

    // Prevent unused warning for uio_in and ui_in[7:1]
    wire _unused = &{1'b0, ui_in[7:1], uio_in, 1'b0};

endmodule
