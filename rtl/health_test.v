module health_test(

    input clk,
    input rst,

    input valid,
    input bit_in,

    output reg healthy

);

parameter LIMIT = 16;

reg previous_bit;
reg [4:0] repeat_count;

always @(posedge clk) begin

    if(rst) begin

        previous_bit <= 0;
        repeat_count <= 0;
        healthy <= 1;

    end

    else if(valid) begin

        if(bit_in == previous_bit)

            repeat_count <= repeat_count + 1;

        else begin

            repeat_count <= 0;
            previous_bit <= bit_in;

        end

        if(repeat_count >= LIMIT)

            healthy <= 0;

    end

end

endmodule