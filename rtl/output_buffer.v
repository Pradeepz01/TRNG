module output_buffer
(
    input  wire clk,
    input  wire rst,

    input  wire bit_in,
    input  wire valid_in,

    output reg [31:0] random_data,
    output reg data_valid
);

reg [5:0] bit_count;

always @(posedge clk or posedge rst)
begin
    if(rst)
    begin
        random_data <= 32'd0;
        bit_count   <= 0;
        data_valid  <= 0;
    end

    else
    begin
        data_valid <= 1'b0;

        if(valid_in)
        begin
            random_data <= {random_data[30:0], bit_in};

            if(bit_count == 31)
            begin
                bit_count  <= 0;
                data_valid <= 1'b1;
            end

            else
                bit_count <= bit_count + 1;
        end
    end
end

endmodule