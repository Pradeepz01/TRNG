`timescale 1ns / 1ps

module ro #(
    parameter STAGES = 4 // Number of inverters (must be an even number >= 2)
)(
    input  wire enable,
    output wire ro_out
);

`ifdef SIMULATION
    // Behavioral simulation model with phase jitter for testbench verification
    reg sim_clk = 1'b0;
    integer seed;
    real jitter;

    initial begin
        seed = 12345 + STAGES * 997;
    end

    always begin
        if (enable) begin
            // Realistic simulated gate delay variation + phase jitter
            jitter = (1.1 + (STAGES * 0.13)) + (($dist_uniform(seed, -200, 200)) / 1000.0);
            if (jitter < 0.2) jitter = 0.2;
            #(jitter);
            sim_clk <= ~sim_clk;
        end else begin
            #1;
            sim_clk <= 1'b0;
        end
    end

    assign ro_out = sim_clk;


`else
    // Sky130 ASIC Standard Cell Implementation
    // STAGES inverters + 1 NAND gate = (STAGES + 1) inverting stages (always odd)
    (* keep = "true" *) wire [STAGES:0] node;

    // First stage: 2-input NAND gate for enable/gating
    (* keep = "true" *) sky130_fd_sc_hd__nand2_1 u_nand (
        .A(enable),
        .B(node[STAGES]),
        .Y(node[0])
    );

    // Inverter chain
    genvar i;
    generate
        for (i = 0; i < STAGES; i = i + 1) begin : gen_inv
            (* keep = "true" *) sky130_fd_sc_hd__inv_1 u_inv (
                .A(node[i]),
                .Y(node[i+1])
            );
        end
    endgenerate

    assign ro_out = node[STAGES];

`endif

endmodule

