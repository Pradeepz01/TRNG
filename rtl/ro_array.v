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
    for(i = 0; i < NUM_RO; i = i + 1)
    begin : RO_ARRAY
        // Stagger inverter chain lengths (4, 6, 8, 10, 12, 14, 16, 18 inverters)
        // + 1 NAND gate = 5, 7, 9, 11, 13, 15, 17, 19 total inverting stages
        // to prevent injection locking and ensure diverse oscillation frequencies.
        ro #(
            .STAGES(4 + (i * 2))
        ) ro_inst (
            .enable(enable),
            .ro_out(ro_bus[i])
        );
    end
endgenerate

endmodule