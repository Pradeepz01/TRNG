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
    // Counter width enough to hold LIMIT
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
                    healthy <= 1'b0; // Flag repetition failure (stuck bitstream)
                end
            end
        end
    end

endmodule