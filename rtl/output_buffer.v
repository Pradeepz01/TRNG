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

    always @(posedge clk or posedge rst)
    begin
        if (rst)
        begin
            random_data <= {WIDTH{1'b0}};
            bit_count   <= {CNT_WIDTH{1'b0}};
            data_valid  <= 1'b0;
        end
        else
        begin
            data_valid <= 1'b0;

            if (valid_in)
            begin
                random_data <= {random_data[WIDTH-2:0], bit_in};

                if (bit_count == (WIDTH - 1))
                begin
                    bit_count  <= {CNT_WIDTH{1'b0}};
                    data_valid <= 1'b1;
                end
                else
                begin
                    bit_count <= bit_count + 1'b1;
                end
            end
        end
    end

endmodule