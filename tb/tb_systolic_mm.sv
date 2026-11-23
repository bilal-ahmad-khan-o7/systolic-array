`timescale 1ns/1ps
// ============================================================================
// tb_systolic_mm.sv - Self-checking test for the systolic-array top level
// ============================================================================
// The tests themselves live in mm_tests.svh (shared with the baseline test).
// This file only:
//   1. sets the parameters and the latency we expect,
//   2. declares the signals,
//   3. instantiates the DUT.
//
// Expected latency = 1 CLEAR cycle + (3N-2) COMPUTE cycles + 1 = 3N.
// ============================================================================

module tb_systolic_mm #(
    parameter int N = 4          // override with: iverilog -Ptb_systolic_mm.N=8
);

    localparam int    DATA_W      = 8;
    localparam int    ACC_W       = 32;
    localparam int    EXP_LATENCY = 3*N;
    localparam string TB_NAME     = "tb_systolic_mm";

    logic                  clk, rst, start, busy, done;
    logic [N*N*DATA_W-1:0] a_flat, b_flat;
    logic [N*N*ACC_W-1:0]  c_flat;

    systolic_mm #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .clk(clk), .rst(rst), .start(start),
        .a_flat(a_flat), .b_flat(b_flat),
        .busy(busy), .done(done), .c_flat(c_flat)
    );

    `include "mm_tests.svh"

endmodule
