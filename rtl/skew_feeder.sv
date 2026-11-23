`timescale 1ns/1ps
// ============================================================================
// skew_feeder.sv - Adds the "staircase" delays in front of the array
// ============================================================================
// Each clock cycle the top module presents one column of A (one value per row)
// and one row of B (one value per column). This module delays them:
//
//   A row i    is delayed by i cycles  (row 0: 0, row 1: 1, row 2: 2, ...)
//   B column j is delayed by j cycles  (col 0: 0, col 1: 1, col 2: 2, ...)
//
// Why? PE(i,j) needs A[i][k] and B[k][j] to arrive at the SAME time.
// A[i][k] has to travel j PEs to the right, and B[k][j] has to travel i PEs
// down. Delaying row i by i and column j by j makes both values arrive at
// PE(i,j) at cycle k + i + j. The delays look like a staircase:
//
//   time ->        t0      t1      t2      t3
//   row 0:       A00     A01     A02     A03
//   row 1:        -      A10     A11     A12     A13
//   row 2:        -       -      A20     A21     A22   ...
//
// A delay of d cycles is just a chain of d registers (a shift register).
// Lane 0 has no delay, so it is a plain wire.
//
// en    : shift only when 1 (same enable as the array, so they stay in step)
// clear : empty every shift register (fill with zeros)
// ============================================================================

module skew_feeder #(
    parameter int N      = 4,
    parameter int DATA_W = 8
) (
    input  logic                clk,
    input  logic                rst,
    input  logic                en,
    input  logic                clear,
    input  logic [N*DATA_W-1:0] a_in,    // lane i = A[i][k] for this step k
    input  logic [N*DATA_W-1:0] b_in,    // lane j = B[k][j] for this step k
    output logic [N*DATA_W-1:0] a_out,   // lane i delayed by i cycles
    output logic [N*DATA_W-1:0] b_out    // lane j delayed by j cycles
);

    genvar lane;
    generate
        for (lane = 0; lane < N; lane++) begin : gen_lane
            if (lane == 0) begin : gen_no_delay
                // Lane 0: no delay needed.
                assign a_out[0 +: DATA_W] = a_in[0 +: DATA_W];
                assign b_out[0 +: DATA_W] = b_in[0 +: DATA_W];

            end else begin : gen_delay
                // Lane > 0: a shift register that is "lane" stages long.
                // a_sr[0] is the newest value, a_sr[lane-1] is the oldest.
                logic [DATA_W-1:0] a_sr [0:lane-1];
                logic [DATA_W-1:0] b_sr [0:lane-1];

                always_ff @(posedge clk) begin
                    if (rst || clear) begin
                        for (int s = 0; s < lane; s++) begin
                            a_sr[s] <= '0;
                            b_sr[s] <= '0;
                        end
                    end else if (en) begin
                        // New value goes in at stage 0, everything else
                        // moves one stage further along.
                        a_sr[0] <= a_in[lane*DATA_W +: DATA_W];
                        b_sr[0] <= b_in[lane*DATA_W +: DATA_W];
                        for (int s = 1; s < lane; s++) begin
                            a_sr[s] <= a_sr[s-1];
                            b_sr[s] <= b_sr[s-1];
                        end
                    end
                end

                // The output is the last stage of the chain.
                assign a_out[lane*DATA_W +: DATA_W] = a_sr[lane-1];
                assign b_out[lane*DATA_W +: DATA_W] = b_sr[lane-1];
            end
        end
    endgenerate

endmodule
