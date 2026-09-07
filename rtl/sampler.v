module sampler #(
    parameter DIV = 8
)(
    input  wire clk,
    input  wire rst,
    input  wire entropy_bit,

    output reg  sampled_bit,
    output reg  valid
);

    // 2-stage DFF synchronizer to protect against metastability from asynchronous RO
    reg sync_0;
    reg sync_1;

    localparam CNT_WIDTH = (DIV > 1) ? $clog2(DIV) : 1;
    reg [CNT_WIDTH-1:0] counter;

    always @(posedge clk or posedge rst)
    begin
        if (rst)
        begin
            sync_0      <= 1'b0;
            sync_1      <= 1'b0;
            counter     <= {CNT_WIDTH{1'b0}};
            sampled_bit <= 1'b0;
            valid       <= 1'b0;
        end
        else
        begin
            // Synchronizer chain clocked by system clock
            sync_0 <= entropy_bit;
            sync_1 <= sync_0;

            valid <= 1'b0;

            if (counter == (DIV - 1))
            begin
                counter     <= {CNT_WIDTH{1'b0}};
                sampled_bit <= sync_1;
                valid       <= 1'b1;
            end
            else
            begin
                counter <= counter + 1'b1;
            end
        end
    end

endmodule