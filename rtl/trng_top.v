module trng_top
(
    input  wire clk,
    input  wire rst,
    input  wire enable,

    output wire [31:0] random_data,
    output wire data_valid,
    output wire healthy
);

wire [7:0] ro_bus;

wire entropy_bit;

wire sampled_bit;
wire sample_valid;

wire vn_bit;
wire vn_valid;

ro_array RO_ARRAY
(
    .enable(enable),
    .ro_bus(ro_bus)
);

entropy_mixer MIXER
(
    .ro_bus(ro_bus),
    .entropy_bit(entropy_bit)
);

sampler
#(
    .DIV(8)
)
SAMPLER
(
    .clk(clk),
    .rst(rst),
    .entropy_bit(entropy_bit),

    .sampled_bit(sampled_bit),
    .valid(sample_valid)
);

von_neumann VN
(
    .clk(clk),
    .rst(rst),

    .bit_in(sampled_bit),

    .bit_out(vn_bit),
    .valid(vn_valid)
);

health_test HEALTH
(
    .clk(clk),
    .rst(rst),

    .valid(vn_valid),
    .bit_in(vn_bit),

    .healthy(healthy)
);

output_buffer BUFFER
(
    .clk(clk),
    .rst(rst),

    .bit_in(vn_bit),
    .valid_in(vn_valid),

    .random_data(random_data),
    .data_valid(data_valid)
);

endmodule