/*
 * ==============================================================================
 * True Random Number Generator (TRNG) for Tiny Tapeout (Sky130)
 * Top Module: tt_um_trng
 * 
 * Pipeline:
 * Ring Oscillators -> Entropy Mixer -> Sampler -> Von Neumann -> Health Test -> Output Buffer
 * ==============================================================================
 */

`default_nettype none
`timescale 1ns / 1ps

// ==============================================================================
// 1. Ring Oscillator (ro)
// ==============================================================================
module ro #(
    parameter STAGES = 4 // Number of inverters (even number >= 2)
)(
    input  wire enable,
    output wire ro_out
);

`ifdef SIMULATION
    // Behavioral simulation model with phase jitter for testbench verification
    reg sim_clk = 1'b0;
    integer seed;
    real jitter;

    initial begin
        seed = 12345 + STAGES * 997;
    end

    always begin
        if (enable) begin
            // Realistic simulated gate delay variation + phase jitter
            jitter = (1.1 + (STAGES * 0.13)) + (($dist_uniform(seed, -200, 200)) / 1000.0);
            if (jitter < 0.2) jitter = 0.2;
            #(jitter);
            sim_clk <= ~sim_clk;
        end else begin
            #1;
            sim_clk <= 1'b0;
        end
    end

    assign ro_out = sim_clk;

`else
    // Sky130 ASIC Standard Cell Implementation
    // STAGES inverters + 1 NAND gate = (STAGES + 1) inverting stages (always odd)
    (* keep = "true" *) wire [STAGES:0] node;

    // First stage: 2-input NAND gate for enable/gating
    (* keep = "true" *) sky130_fd_sc_hd__nand2_1 u_nand (
        .A(enable),
        .B(node[STAGES]),
        .Y(node[0])
    );

    // Inverter chain
    genvar i;
    generate
        for (i = 0; i < STAGES; i = i + 1) begin : gen_inv
            (* keep = "true" *) sky130_fd_sc_hd__inv_1 u_inv (
                .A(node[i]),
                .Y(node[i+1])
            );
        end
    endgenerate

    assign ro_out = node[STAGES];

`endif

endmodule


// ==============================================================================
// 2. Ring Oscillator Array (ro_array)
// ==============================================================================
module ro_array #(
    parameter NUM_RO = 8
)(
    input  wire enable,
    output wire [NUM_RO-1:0] ro_bus
);

    genvar i;
    generate
        for (i = 0; i < NUM_RO; i = i + 1) begin : RO_ARRAY
            // Stagger inverter chain lengths (4, 6, 8, 10, 12, 14, 16, 18 inverters)
            // + 1 NAND gate = 5, 7, 9, 11, 13, 15, 17, 19 total inverting stages
            // to prevent injection locking and ensure diverse oscillation frequencies.
            ro #(
                .STAGES(4 + (i * 2))
            ) ro_inst (
                .enable(enable),
                .ro_out(ro_bus[i])
            );
        end
    endgenerate

endmodule


// ==============================================================================
// 3. Entropy Mixer (entropy_mixer)
// ==============================================================================
module entropy_mixer #(
    parameter NUM_RO = 8
)(
    input  wire [NUM_RO-1:0] ro_bus,
    output wire              entropy_bit
);

    assign entropy_bit = ^ro_bus; // XOR reduction

endmodule


// ==============================================================================
// 4. Sampler with Metastability Protection (sampler)
// ==============================================================================
module sampler #(
    parameter DIV = 8
)(
    input  wire clk,
    input  wire rst,
    input  wire entropy_bit,

    output reg  sampled_bit,
    output reg  valid
);

    // 2-stage DFF synchronizer to protect against metastability from asynchronous RO
    reg sync_0;
    reg sync_1;

    localparam CNT_WIDTH = (DIV > 1) ? $clog2(DIV) : 1;
    reg [CNT_WIDTH-1:0] counter;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sync_0      <= 1'b0;
            sync_1      <= 1'b0;
            counter     <= {CNT_WIDTH{1'b0}};
            sampled_bit <= 1'b0;
            valid       <= 1'b0;
        end else begin
            sync_0 <= entropy_bit;
            sync_1 <= sync_0;

            valid <= 1'b0;

            if (counter == (DIV - 1)) begin
                counter     <= {CNT_WIDTH{1'b0}};
                sampled_bit <= sync_1;
                valid       <= 1'b1;
            end else begin
                counter <= counter + 1'b1;
            end
        end
    end

endmodule


// ==============================================================================
// 5. Von Neumann Debiasing Corrector (von_neumann)
// ==============================================================================
module von_neumann (
    input  wire clk,
    input  wire rst,
    input  wire valid_in,
    input  wire bit_in,

    output reg  bit_out,
    output reg  valid
);

    reg first_bit;
    reg pair_ready;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            first_bit  <= 1'b0;
            pair_ready <= 1'b0;
            bit_out    <= 1'b0;
            valid      <= 1'b0;
        end else begin
            valid <= 1'b0;

            if (valid_in) begin
                if (!pair_ready) begin
                    first_bit  <= bit_in;
                    pair_ready <= 1'b1;
                end else begin
                    pair_ready <= 1'b0;

                    case ({first_bit, bit_in})
                        2'b01: begin
                            bit_out <= 1'b1;
                            valid   <= 1'b1;
                        end
                        2'b10: begin
                            bit_out <= 1'b0;
                            valid   <= 1'b1;
                        end
                        default: begin
                            valid   <= 1'b0; // discard 2'b00 and 2'b11
                        end
                    endcase
                end
            end
        end
    end

endmodule


// ==============================================================================
// 6. Health Test / Repetition Count Watchdog (health_test)
// ==============================================================================
module health_test #(
    parameter LIMIT = 16
)(
    input  wire clk,
    input  wire rst,

    input  wire valid,
    input  wire bit_in,

    output reg  healthy
);

    reg previous_bit;
    reg seen_first;
    localparam CNT_WIDTH = $clog2(LIMIT + 1);
    reg [CNT_WIDTH-1:0] repeat_count;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            previous_bit <= 1'b0;
            seen_first   <= 1'b0;
            repeat_count <= {CNT_WIDTH{1'b0}};
            healthy      <= 1'b1;
        end else if (valid) begin
            if (!seen_first) begin
                seen_first   <= 1'b1;
                previous_bit <= bit_in;
                repeat_count <= {CNT_WIDTH{1'b0}};
            end else begin
                if (bit_in == previous_bit) begin
                    if (repeat_count < LIMIT)
                        repeat_count <= repeat_count + 1'b1;
                end else begin
                    repeat_count <= {CNT_WIDTH{1'b0}};
                    previous_bit <= bit_in;
                end

                if (repeat_count >= (LIMIT - 1)) begin
                    healthy <= 1'b0; // Flag repetition fault
                end
            end
        end
    end

endmodule


// ==============================================================================
// 7. Output Buffer (output_buffer)
// ==============================================================================
module output_buffer #(
    parameter WIDTH = 8
)(
    input  wire clk,
    input  wire rst,

    input  wire bit_in,
    input  wire valid_in,

    output reg [WIDTH-1:0] random_data,
    output reg             data_valid
);

    localparam CNT_WIDTH = (WIDTH > 1) ? $clog2(WIDTH) : 1;
    reg [CNT_WIDTH-1:0] bit_count;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            random_data <= {WIDTH{1'b0}};
            bit_count   <= {CNT_WIDTH{1'b0}};
            data_valid  <= 1'b0;
        end else begin
            data_valid <= 1'b0;

            if (valid_in) begin
                random_data <= {random_data[WIDTH-2:0], bit_in};

                if (bit_count == (WIDTH - 1)) begin
                    bit_count  <= {CNT_WIDTH{1'b0}};
                    data_valid <= 1'b1;
                end else begin
                    bit_count <= bit_count + 1'b1;
                end
            end
        end
    end

endmodule


// ==============================================================================
// 8. TRNG Top Core (trng_top)
// ==============================================================================
module trng_top #(
    parameter NUM_RO      = 8,
    parameter SAMPLER_DIV = 8,
    parameter DATA_WIDTH  = 8
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  enable,

    output wire [DATA_WIDTH-1:0] random_data,
    output wire                  data_valid,
    output wire                  healthy,
    output wire                  entropy_bit_mon
);

    wire [NUM_RO-1:0] ro_bus;
    wire              entropy_bit;
    wire              sampled_bit;
    wire              sample_valid;
    wire              vn_bit;
    wire              vn_valid;
    wire              is_healthy;

    assign entropy_bit_mon = entropy_bit;
    assign healthy         = is_healthy;

    // 1. Array of Ring Oscillators
    ro_array #(
        .NUM_RO(NUM_RO)
    ) RO_ARRAY (
        .enable(enable),
        .ro_bus(ro_bus)
    );

    // 2. Entropy Mixer (XOR tree)
    entropy_mixer #(
        .NUM_RO(NUM_RO)
    ) MIXER (
        .ro_bus(ro_bus),
        .entropy_bit(entropy_bit)
    );

    // 3. Sampler with 2-stage synchronizer
    sampler #(
        .DIV(SAMPLER_DIV)
    ) SAMPLER (
        .clk(clk),
        .rst(rst),
        .entropy_bit(entropy_bit),
        .sampled_bit(sampled_bit),
        .valid(sample_valid)
    );

    // 4. Von Neumann Debiasing Corrector
    von_neumann VN (
        .clk(clk),
        .rst(rst),
        .valid_in(sample_valid),
        .bit_in(sampled_bit),
        .bit_out(vn_bit),
        .valid(vn_valid)
    );

    // 5. Health Test (Repetition Count Watchdog)
    health_test #(
        .LIMIT(16)
    ) HEALTH (
        .clk(clk),
        .rst(rst),
        .valid(vn_valid),
        .bit_in(vn_bit),
        .healthy(is_healthy)
    );

    // 6. Output Buffer (gated by health status)
    wire buffer_valid_in = vn_valid & is_healthy;

    output_buffer #(
        .WIDTH(DATA_WIDTH)
    ) BUFFER (
        .clk(clk),
        .rst(rst),
        .bit_in(vn_bit),
        .valid_in(buffer_valid_in),
        .random_data(random_data),
        .data_valid(data_valid)
    );

endmodule


// ==============================================================================
// 9. Tiny Tapeout Top Module Wrapper (tt_um_pradeepz01_trng)
// ==============================================================================
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

    // Dedicated outputs: 8-bit random data byte
    assign uo_out = random_byte;

    // Bidirectional IO outputs:
    // bit 0: byte_valid strobe
    // bit 1: healthy flag (1 = healthy, 0 = repetition fault alarm)
    // bit 2: raw entropy bit monitor (for oscilloscope / probing)
    // bits 7:3: unused (tied to 0)
    assign uio_out[0]   = byte_valid;
    assign uio_out[1]   = healthy;
    assign uio_out[2]   = entropy_mon;
    assign uio_out[7:3] = 5'b00000;

    // IO direction: bits 0..2 are outputs (1), bits 3..7 are inputs (0)
    assign uio_oe = 8'b0000_0111;

    // Prevent unused warning for uio_in and ui_in[7:1]
    wire _unused = &{1'b0, ui_in[7:1], uio_in, 1'b0};

endmodule
