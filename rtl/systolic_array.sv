`timescale 1ns/1ps
// ============================================================================
// systolic_array.sv - An N x N grid of PEs
// ============================================================================
// Picture for N = 4 (each box is one PE):
//
//              b_top[0]  b_top[1]  b_top[2]  b_top[3]
//                 |         |         |         |
//                 v         v         v         v
//   a_left[0] -> PE00  ->  PE01  ->  PE02  ->  PE03  -> (dropped)
//                 |         |         |         |
//                 v         v         v         v
//   a_left[1] -> PE10  ->  PE11  ->  PE12  ->  PE13  ->
//                 |         |         |         |
//   a_left[2] -> PE20  ->  PE21  ->  PE22  ->  PE23  ->
//                 |         |         |         |
//   a_left[3] -> PE30  ->  PE31  ->  PE32  ->  PE33  ->
//                 |         |         |         |
//                 v         v         v         v
//              (dropped)
//
// PE(i,j) ends up holding C[i][j] in its accumulator.
//
// This module only does the wiring. It does NOT add the input delays
// ("skewing") - that is the job of skew_feeder.sv.
//
// Flat bus layout (so the module has simple ports):
//   a_left : lane i  is bits [i*DATA_W +: DATA_W]
//   b_top  : lane j  is bits [j*DATA_W +: DATA_W]
//   c_flat : C[i][j] is bits [(i*N + j)*ACC_W +: ACC_W]
// ============================================================================

module systolic_array #(
    parameter int N      = 4,
    parameter int DATA_W = 8,
    parameter int ACC_W  = 32
) (
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  en,
    input  logic                  clear,
    input  logic [N*DATA_W-1:0]   a_left,   // one value per row, enters on the left
    input  logic [N*DATA_W-1:0]   b_top,    // one value per column, enters on top
    output logic [N*N*ACC_W-1:0]  c_flat    // all N*N results
);

    // Internal wires between PEs.
    //   a_wire[i][j] is the "a" value going INTO PE(i,j) from the left.
    //   a_wire[i][N] is what falls off the right edge (unused).
    //   b_wire[i][j] is the "b" value going INTO PE(i,j) from above.
    //   b_wire[N][j] is what falls off the bottom edge (unused).
    wire [DATA_W-1:0] a_wire [0:N-1][0:N];
    wire [DATA_W-1:0] b_wire [0:N][0:N-1];

    genvar i, j;
    generate
        // Connect the array edges to the input buses.
        for (i = 0; i < N; i++) begin : gen_left_edge
            assign a_wire[i][0] = a_left[i*DATA_W +: DATA_W];
        end
        for (j = 0; j < N; j++) begin : gen_top_edge
            assign b_wire[0][j] = b_top[j*DATA_W +: DATA_W];
        end

        // Build the grid. gen_row[i].gen_col[j].u_pe is PE(i,j).
        for (i = 0; i < N; i++) begin : gen_row
            for (j = 0; j < N; j++) begin : gen_col
                pe #(.DATA_W(DATA_W), .ACC_W(ACC_W)) u_pe (
                    .clk   (clk),
                    .rst   (rst),
                    .en    (en),
                    .clear (clear),
                    .a_in  (a_wire[i][j]),      // from the left neighbour
                    .b_in  (b_wire[i][j]),      // from the neighbour above
                    .a_out (a_wire[i][j+1]),    // to the right neighbour
                    .b_out (b_wire[i+1][j]),    // to the neighbour below
                    .acc   (c_flat[(i*N + j)*ACC_W +: ACC_W])
                );
            end
        end
    endgenerate

endmodule
