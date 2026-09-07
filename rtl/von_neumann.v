module von_neumann(
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
                            // 2'b00 or 2'b11: discard bit
                            valid   <= 1'b0;
                        end
                    endcase
                end
            end
        end
    end

endmodule