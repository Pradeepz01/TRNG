module entropy_mixer
#(
    parameter NUM_RO = 8
)
(
    input  wire [NUM_RO-1:0] ro_bus,
    output wire entropy_bit
);

assign entropy_bit = ^ro_bus;      // XOR reduction

endmodule