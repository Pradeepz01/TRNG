module ro_array
#(
    parameter NUM_RO = 8
)
(
    input  wire enable,
    output wire [NUM_RO-1:0] ro_bus
);

genvar i;

generate

    for(i=0;i<NUM_RO;i=i+1)

    begin : RO_ARRAY

        ro ro_inst
        (
            .enable(enable),
            .ro_out(ro_bus[i])
        );

    end

endgenerate

endmodule