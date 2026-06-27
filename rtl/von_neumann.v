module von_neumann(
    input clk,
    input rst,
    input bit_in,

    output reg bit_out,
    output reg valid
);

reg first_bit;
reg pair_ready;

always @(posedge clk) begin

    if(rst) begin
        first_bit <= 0;
        pair_ready <= 0;
        valid <= 0;
    end

    else begin

        valid <= 0;

        if(!pair_ready) begin
            first_bit <= bit_in;
            pair_ready <= 1;
        end

        else begin

            pair_ready <= 0;

            case({first_bit,bit_in})

                2'b01:
                begin
                    bit_out <= 1'b1;
                    valid <= 1;
                end

                2'b10:
                begin
                    bit_out <= 1'b0;
                    valid <= 1;
                end

                default:
                begin
                    valid <= 0;
                end

            endcase

        end

    end

end

endmodule