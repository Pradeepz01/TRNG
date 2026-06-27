module sampler #
(
    parameter DIV = 8
)
(
    input  wire clk,
    input  wire rst,
    input  wire entropy_bit,

    output reg sampled_bit,
    output reg valid
);

reg [31:0] counter;

always @(posedge clk or posedge rst)
begin
    if(rst)
    begin
        counter     <= 0;
        sampled_bit <= 0;
        valid       <= 0;
    end

    else
    begin
        valid <= 1'b0;

        if(counter == DIV-1)
        begin
            counter     <= 0;
            sampled_bit <= entropy_bit;
            valid       <= 1'b1;
        end

        else
            counter <= counter + 1;
    end
end

endmodule