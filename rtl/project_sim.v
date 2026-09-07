/*
 * =============================================================================
 * True Random Number Generator (TRNG) - Behavioral Simulation Version
 * Purpose: Used for functional verification and testbenches in Icarus Verilog
 * Top Module: tt_um_trng
 *
 * Pipeline Flow:
 * Ring Oscillators (simulated jitter) -> Mixer -> Sampler -> Von Neumann -> Health -> Buffer
 * =============================================================================
 */

`default_nettype none
`timescale 1ns / 1ps

// =============================================================================
// 1. Ring Oscillator (ro) - Behavioral Simulation Model
// In digital simulation, zero-delay physical loops cause simulators to hang.
// Here we model realistic gate delay variation and phase jitter using delays (#).
// =============================================================================
module ro #(
    parameter STAGES = 4 // Inverter count
)(
    input  wire enable,  // 1 = running, 0 = stopped
    output wire ro_out   // Simulated oscillating signal
);

    reg sim_clk = 1'b0;
    integer seed;
    real jitter;

    initial begin
        // Unique seed for each oscillator based on STAGES
        seed = 12345 + STAGES * 997;
    end

    always begin
        if (enable) begin
            // Model analog delay + random phase noise/jitter
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

endmodule


// =============================================================================
// 2. Ring Oscillator Array with Injection Locking Protection (ro_array)
// Runs 8 ring oscillators, each with a different prime number of stages.
// =============================================================================
module ro_array #(
    parameter NUM_RO = 8
)(
    input  wire enable,
    output wire [NUM_RO-1:0] ro_bus
);

    function integer get_stages(input integer idx);
        case (idx)
            0: get_stages = 4;  // Total 5 stages (prime)
            1: get_stages = 6;  // Total 7 stages (prime)
            2: get_stages = 10; // Total 11 stages (prime)
            3: get_stages = 12; // Total 13 stages (prime)
            4: get_stages = 16; // Total 17 stages (prime)
            5: get_stages = 18; // Total 19 stages (prime)
            6: get_stages = 22; // Total 23 stages (prime)
            7: get_stages = 28; // Total 29 stages (prime)
            default: get_stages = 4 + (idx * 2);
        endcase
    endfunction

    genvar i;
    generate
        for (i = 0; i < NUM_RO; i = i + 1) begin : RO_ARRAY
            ro #(
                .STAGES(get_stages(i))
            ) ro_inst (
                .enable(enable),
                .ro_out(ro_bus[i])
            );
        end
    endgenerate

endmodule


// =============================================================================
// 3. Entropy Mixer (entropy_mixer)
// XOR reduction across all 8 oscillators into 1 entropy bit.
// =============================================================================
module entropy_mixer #(
    parameter NUM_RO = 8
)(
    input  wire [NUM_RO-1:0] ro_bus,
    output wire              entropy_bit
);

    assign entropy_bit = ^ro_bus;

endmodule


// =============================================================================
// 4. Sampler (sampler)
// Samples the asynchronous entropy bit with a 2-stage synchronizer.
// =============================================================================
module sampler #(
    parameter DIV = 8
)(
    input  wire clk,
    input  wire rst,
    input  wire entropy_bit,

    output reg  sampled_bit,
    output reg  valid
);

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


// =============================================================================
// 5. Von Neumann Debiasing Corrector (von_neumann)
// =============================================================================
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
                            valid   <= 1'b0;
                        end
                    endcase
                end
            end
        end
    end

endmodule


// =============================================================================
// 6. Health Test Watchdog (health_test)
// =============================================================================
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
                    healthy <= 1'b0;
                end
            end
        end
    end

endmodule


// =============================================================================
// 7. Output Buffer (output_buffer)
// Collects 8 bits into a random byte.
// =============================================================================
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


// =============================================================================
// 8. TRNG Core (trng_top)
// =============================================================================
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

    ro_array #(.NUM_RO(NUM_RO)) RO_ARRAY (
        .enable(enable),
        .ro_bus(ro_bus)
    );

    entropy_mixer #(.NUM_RO(NUM_RO)) MIXER (
        .ro_bus(ro_bus),
        .entropy_bit(entropy_bit)
    );

    sampler #(.DIV(SAMPLER_DIV)) SAMPLER (
        .clk(clk),
        .rst(rst),
        .entropy_bit(entropy_bit),
        .sampled_bit(sampled_bit),
        .valid(sample_valid)
    );

    von_neumann VN (
        .clk(clk),
        .rst(rst),
        .valid_in(sample_valid),
        .bit_in(sampled_bit),
        .bit_out(vn_bit),
        .valid(vn_valid)
    );

    health_test #(.LIMIT(16)) HEALTH (
        .clk(clk),
        .rst(rst),
        .valid(vn_valid),
        .bit_in(vn_bit),
        .healthy(is_healthy)
    );

    wire buffer_valid_in = vn_valid & is_healthy;

    output_buffer #(.WIDTH(DATA_WIDTH)) BUFFER (
        .clk(clk),
        .rst(rst),
        .bit_in(vn_bit),
        .valid_in(buffer_valid_in),
        .random_data(random_data),
        .data_valid(data_valid)
    );

endmodule


// =============================================================================
// 9. Tiny Tapeout Top Module (tt_um_trng)
// =============================================================================
module tt_um_trng (
    input  wire [7:0] ui_in,    // Dedicated inputs:  ui_in[0] = enable
    output wire [7:0] uo_out,   // Dedicated outputs: uo_out[7:0] = 8-bit random byte
    input  wire [7:0] uio_in,   // IOs: Input path (unused)
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Direction (1=output, 0=input)
    input  wire       ena,      // Power enable signal
    input  wire       clk,      // System clock
    input  wire       rst_n     // Reset (active low: 0 = reset, 1 = run)
);

    wire rst = !rst_n;
    wire trng_en = ena & ui_in[0];

    wire [7:0] random_byte;
    wire       byte_valid;
    wire       healthy;
    wire       entropy_mon;

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

    assign uo_out = random_byte;

    assign uio_out[0]   = byte_valid;
    assign uio_out[1]   = healthy;
    assign uio_out[2]   = entropy_mon;
    assign uio_out[7:3] = 5'b00000;

    assign uio_oe = 8'b0000_0111;

    wire _unused = &{1'b0, ui_in[7:1], uio_in, 1'b0};

endmodule
