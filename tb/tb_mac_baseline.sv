`timescale 1ns/1ps
// ============================================================================
// tb_mac_baseline.sv - Self-checking test for the single-MAC baseline
// ============================================================================
// The tests themselves live in mm_tests.svh (shared with the systolic-array test).
// This file only:
//   1. sets the parameters and the latency we expect,
//   2. declares the signals,
//   3. instantiates the DUT.
//
// Expected latency = N*N*N COMPUTE cycles + 1 (DONE) = N^3 + 1.
// ============================================================================

module tb_mac_baseline #(
    parameter int N = 4          // override with: iverilog -Ptb_mac_baseline.N=8
);

    localparam int    DATA_W      = 8;
    localparam int    ACC_W       = 32;
    localparam int    EXP_LATENCY = N*N*N + 1;
    localparam string TB_NAME     = "tb_mac_baseline";

    logic                  clk, rst, start, busy, done;
    logic [N*N*DATA_W-1:0] a_flat, b_flat;
    logic [N*N*ACC_W-1:0]  c_flat;

    mac_baseline #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .clk(clk), .rst(rst), .start(start),
        .a_flat(a_flat), .b_flat(b_flat),
        .busy(busy), .done(done), .c_flat(c_flat)
    );

    `include "mm_tests.svh"

endmodule
