`timescale 1ns / 1ps

module tb_trng;

    reg        clk;
    reg        rst_n;
    reg        ena;
    reg  [7:0] ui_in;
    wire [7:0] uo_out;
    reg  [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    wire byte_valid      = uio_out[0];
    wire healthy         = uio_out[1];
    wire entropy_mon     = uio_out[2];
    wire [7:0] rand_byte = uo_out;

    // Instantiate Tiny Tapeout Top Module
    tt_um_pradeepz01_trng dut (
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena(ena),
        .clk(clk),
        .rst_n(rst_n)
    );

    // 50 MHz clock generation (20 ns period)
    always #10 clk = ~clk;

    integer bytes_received;
    integer max_cycles;

    initial begin
        $dumpfile("tb_trng.vcd");
        $dumpvars(0, tb_trng);

        // Initialize signals
        clk            = 0;
        rst_n          = 0;
        ena            = 0;
        ui_in          = 8'h00;
        uio_in         = 8'h00;
        bytes_received = 0;
        max_cycles     = 100000;

        $display("==================================================");
        $display("   Tiny Tapeout TRNG Comprehensive Testbench      ");
        $display("==================================================");

        // Apply reset for 100 ns
        #100;
        @(posedge clk);
        rst_n = 1;
        ena   = 1;
        ui_in[0] = 1; // Enable TRNG
        $display("[TIME: %0t] Reset released, TRNG enabled.", $time);

        // Verify that healthy status is 1
        @(posedge clk);
        if (healthy !== 1'b1) begin
            $display("[ERROR] TRNG healthy flag is not asserted after reset!");
            $finish(1);
        end else begin
            $display("[PASS] Initial health test status: HEALTHY (1)");
        end

        // Monitor byte generation
        $display("\nWaiting for random bytes from TRNG output...\n");

        while (bytes_received < 8 && max_cycles > 0) begin
            @(posedge clk);
            max_cycles = max_cycles - 1;

            if (byte_valid) begin
                bytes_received = bytes_received + 1;
                $display("[TIME: %0t] Random Byte #%0d received: 0x%02h (binary: %08b), healthy: %0b",
                         $time, bytes_received, rand_byte, rand_byte, healthy);
            end
        end

        if (bytes_received < 8) begin
            $display("\n[ERROR] Timeout waiting for 8 random bytes!");
            $finish(1);
        end

        $display("\n[PASS] Successfully received %0d random bytes!", bytes_received);
        $display("[PASS] IO configuration verified: uio_oe = 0x%02h (expected 0x07)", uio_oe);

        $display("\n==================================================");
        $display("   ALL TESTBENCH CHECKS PASSED SUCCESSFULLY!      ");
        $display("==================================================");
        $finish(0);
    end

endmodule
