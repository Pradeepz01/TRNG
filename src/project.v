/*
 * =============================================================================
 * True Random Number Generator (TRNG) - Clean ASIC Tapeout Version
 * Target: Tiny Tapeout (SkyWater 130nm)
 * Top Module: tt_um_trng
 *
 * Pipeline Flow:
 * Ring Oscillators -> Entropy Mixer -> Sampler -> Von Neumann -> Health Test -> Output Buffer
 * =============================================================================
 */

`default_nettype none
`timescale 1ns / 1ps

// =============================================================================
// 1. Ring Oscillator (ro)
// A loop of inverters that constantly flips.
// Uses a 2-input NAND gate as the first stage to turn the oscillator on/off.
// =============================================================================
module ro #(
    parameter STAGES = 4 // Number of inverters (must be an even number)
)(
    input  wire enable,  // 1 = running, 0 = stopped
    output wire ro_out   // High-speed oscillating signal
);

    // Total inverting stages = STAGES inverters + 1 NAND gate = odd number.
    // Odd number of inversions guarantees continuous oscillation when enabled.
    // (* keep = "true" *) tells the synthesis tool not to delete or merge any gates.
    (* keep = "true" *) wire [STAGES:0] node;

    // Stage 0: NAND gate for enable control
    // When enable = 0, node[0] is held at 1 (stops oscillation, saves power)
    // When enable = 1, it acts like an inverter: node[0] = ~node[STAGES]
    (* keep = "true" *) sky130_fd_sc_hd__nand2_1 u_nand (
        .A(enable),
        .B(node[STAGES]),
        .Y(node[0])
    );

    // Stages 1 to STAGES: Chain of inverters
    genvar i;
    generate
        for (i = 0; i < STAGES; i = i + 1) begin : gen_inv
            (* keep = "true" *) sky130_fd_sc_hd__inv_1 u_inv (
                .A(node[i]),
                .Y(node[i+1])
            );
        end
    endgenerate

    // Output is taken from the last inverter
    assign ro_out = node[STAGES];

endmodule


// =============================================================================
// 2. Ring Oscillator Array (ro_array)
// Runs 8 ring oscillators in parallel.
//
// Injection Locking Defense:
// If oscillators have the same length, physical coupling on the chip can pull
// them to the exact same frequency (injection locking).
// To prevent this, each oscillator uses a different PRIME number of total stages:
// RO 0:  4 inverters + 1 NAND =  5 stages (prime)
// RO 1:  6 inverters + 1 NAND =  7 stages (prime)
// RO 2: 10 inverters + 1 NAND = 11 stages (prime)
// RO 3: 12 inverters + 1 NAND = 13 stages (prime)
// RO 4: 16 inverters + 1 NAND = 17 stages (prime)
// RO 5: 18 inverters + 1 NAND = 19 stages (prime)
// RO 6: 22 inverters + 1 NAND = 23 stages (prime)
// RO 7: 28 inverters + 1 NAND = 29 stages (prime)
// =============================================================================
module ro_array #(
    parameter NUM_RO = 8
)(
    input  wire enable,
    output wire [NUM_RO-1:0] ro_bus
);

    function integer get_stages(input integer idx);
        case (idx)
            0: get_stages = 4;
            1: get_stages = 6;
            2: get_stages = 10;
            3: get_stages = 12;
            4: get_stages = 16;
            5: get_stages = 18;
            6: get_stages = 22;
            7: get_stages = 28;
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
// Combines the 8 oscillator signals into a single entropy bit using an XOR tree.
// =============================================================================
module entropy_mixer #(
    parameter NUM_RO = 8
)(
    input  wire [NUM_RO-1:0] ro_bus,
    output wire              entropy_bit
);

    // XOR reduction: 1 if an odd number of oscillators are high, 0 otherwise
    assign entropy_bit = ^ro_bus;

endmodule


// =============================================================================
// 4. Sampler (sampler)
// Samples the fast, asynchronous entropy bit at a lower system clock rate.
// Includes a 2-flip-flop synchronizer to prevent metastability.
// =============================================================================
module sampler #(
    parameter DIV = 8 // Sample once every DIV clock cycles
)(
    input  wire clk,
    input  wire rst,
    input  wire entropy_bit,

    output reg  sampled_bit,
    output reg  valid
);

    // 2-stage synchronizer: stabilizes asynchronous input into the clk domain
    reg sync_0;
    reg sync_1;

    // Small counter (only 3 bits for DIV = 8, saves area)
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
            // Shift through synchronizer
            sync_0 <= entropy_bit;
            sync_1 <= sync_0;

            valid <= 1'b0;

            if (counter == (DIV - 1)) begin
                counter     <= {CNT_WIDTH{1'b0}};
                sampled_bit <= sync_1;
                valid       <= 1'b1; // Pulse high for 1 cycle when new sample is ready
            end else begin
                counter <= counter + 1'b1;
            end
        end
    end

endmodule


// =============================================================================
// 5. Von Neumann Debiasing Corrector (von_neumann)
// Removes 0/1 bias from physical variations.
//
// Algorithm:
// Takes pairs of consecutive valid bits:
// - Pair 01 -> Output 1 (valid)
// - Pair 10 -> Output 0 (valid)
// - Pair 00 or 11 -> Discard (not valid)
// =============================================================================
module von_neumann (
    input  wire clk,
    input  wire rst,
    input  wire valid_in, // Only read bit_in when this is 1
    input  wire bit_in,

    output reg  bit_out,
    output reg  valid     // Pulses 1 when an unbiased bit is produced
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

            // Only advance the FSM when a brand-new sample arrives
            if (valid_in) begin
                if (!pair_ready) begin
                    // Store the first bit of the pair
                    first_bit  <= bit_in;
                    pair_ready <= 1'b1;
                end else begin
                    // Compare with second bit of the pair
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
                            // 2'b00 or 2'b11: discard both bits
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
// Continuously monitors the random stream for faults (e.g. stuck high/low).
// Flags an alarm if the same bit repeats LIMIT times in a row.
// =============================================================================
module health_test #(
    parameter LIMIT = 16 // Alarm after 16 consecutive identical bits
)(
    input  wire clk,
    input  wire rst,

    input  wire valid,
    input  wire bit_in,

    output reg  healthy  // 1 = Normal/Healthy, 0 = Fault Alarm
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

                // If identical bits reach LIMIT, flag alarm
                if (repeat_count >= (LIMIT - 1)) begin
                    healthy <= 1'b0;
                end
            end
        end
    end

endmodule


// =============================================================================
// 7. Output Buffer (output_buffer)
// Collects 8 unbiased bits into a full 8-bit random byte for Tiny Tapeout.
// =============================================================================
module output_buffer #(
    parameter WIDTH = 8 // 8-bit byte output
)(
    input  wire clk,
    input  wire rst,

    input  wire bit_in,
    input  wire valid_in,

    output reg [WIDTH-1:0] random_data,
    output reg             data_valid // Pulses 1 when full byte is ready
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
                // Shift in the new bit
                random_data <= {random_data[WIDTH-2:0], bit_in};

                // Check if all 8 bits have arrived
                if (bit_count == (WIDTH - 1)) begin
                    bit_count  <= {CNT_WIDTH{1'b0}};
                    data_valid <= 1'b1; // Complete 8-bit byte ready!
                end else begin
                    bit_count <= bit_count + 1'b1;
                end
            end
        end
    end

endmodule


// =============================================================================
// 8. TRNG Core (trng_top)
// Wires all pipeline stages together.
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

    // 1. Array of Ring Oscillators
    ro_array #(.NUM_RO(NUM_RO)) RO_ARRAY (
        .enable(enable),
        .ro_bus(ro_bus)
    );

    // 2. Entropy Mixer (XOR tree)
    entropy_mixer #(.NUM_RO(NUM_RO)) MIXER (
        .ro_bus(ro_bus),
        .entropy_bit(entropy_bit)
    );

    // 3. Sampler
    sampler #(.DIV(SAMPLER_DIV)) SAMPLER (
        .clk(clk),
        .rst(rst),
        .entropy_bit(entropy_bit),
        .sampled_bit(sampled_bit),
        .valid(sample_valid)
    );

    // 4. Von Neumann Debiasing
    von_neumann VN (
        .clk(clk),
        .rst(rst),
        .valid_in(sample_valid),
        .bit_in(sampled_bit),
        .bit_out(vn_bit),
        .valid(vn_valid)
    );

    // 5. Health Test Watchdog
    health_test #(.LIMIT(16)) HEALTH (
        .clk(clk),
        .rst(rst),
        .valid(vn_valid),
        .bit_in(vn_bit),
        .healthy(is_healthy)
    );

    // 6. Output Buffer: gated by health status (blocks output if unhealthy)
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
// Standard pinout for Tiny Tapeout.
// =============================================================================
module tt_um_trng (
    input  wire [7:0] ui_in,    // Dedicated inputs:  ui_in[0] = enable
    output wire [7:0] uo_out,   // Dedicated outputs: uo_out[7:0] = 8-bit random byte
    input  wire [7:0] uio_in,   // IOs: Input path (unused)
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Direction (1=output, 0=input)
    input  wire       ena,      // Power enable signal (always 1 when chip is active)
    input  wire       clk,      // System clock (e.g. 50 MHz)
    input  wire       rst_n     // Reset (active low: 0 = reset, 1 = run)
);

    // Active-high reset for internal logic
    wire rst = !rst_n;

    // Enable TRNG only when chip is powered and ui_in[0] is set high
    wire trng_en = ena & ui_in[0];

    wire [7:0] random_byte;
    wire       byte_valid;
    wire       healthy;
    wire       entropy_mon;

    // Instantiate TRNG core
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

    // Pin connections:
    // Dedicated outputs: random byte
    assign uo_out = random_byte;

    // Bidirectional IO outputs:
    // uio_out[0]: byte_valid pulse (high for 1 cycle when random byte is ready)
    // uio_out[1]: healthy flag (1 = healthy, 0 = error alarm)
    // uio_out[2]: raw entropy monitor bit (for oscilloscope probing)
    // uio_out[7:3]: unused (tied to 0)
    assign uio_out[0]   = byte_valid;
    assign uio_out[1]   = healthy;
    assign uio_out[2]   = entropy_mon;
    assign uio_out[7:3] = 5'b00000;

    // Set IO direction: bits 0, 1, 2 are outputs (1), bits 3 to 7 are inputs (0)
    assign uio_oe = 8'b0000_0111;

    // Suppress warnings for unused pins
    wire _unused = &{1'b0, ui_in[7:1], uio_in, 1'b0};

endmodule
