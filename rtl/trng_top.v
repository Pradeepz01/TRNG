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

    // 6. Output Buffer: gated by health status
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