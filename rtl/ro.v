`timescale 1ns / 1ps
module ro(
    input  wire enable,
    output wire ro_out
);

(* keep = "true" *) wire n1;
(* keep = "true" *) wire n2;
(* keep = "true" *) wire n3;
(* keep = "true" *) wire n4;
(* keep = "true" *) wire n5;

assign n1 = ~(enable & n5);
assign n2 = ~n1;
assign n3 = ~n2;
assign n4 = ~n3;
assign n5 = ~n4;

assign ro_out = n5;

endmodule
