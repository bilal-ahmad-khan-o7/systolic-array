`timescale 1ns/1ps
// ============================================================================
// pe.sv - Processing Element (PE) for an output-stationary systolic array
// ============================================================================
// One PE does one job: multiply the two numbers it receives and add the result
// to its own running total (the "accumulator").
//
//   - "a" values come in from the LEFT and are passed on to the RIGHT.
//   - "b" values come in from the TOP and are passed on to the BOTTOM.
//   - Each pass-through goes through a register, so a value moves exactly one
//     PE per clock cycle. This is what makes the array "systolic": data pulses
//     through the grid in lock-step, like blood pumped by a heart.
//
// "Output-stationary" means the result C[i][j] stays inside PE(i,j) the whole
// time. Only the inputs move.
//
// Control signals (all synchronous = they only act on a rising clock edge):
//   rst   : active-high reset. Sets every register to 0.
//   clear : sets every register to 0 before a new matrix multiply starts
//           (the accumulator AND the pass-through registers, so no leftover
//           data from the previous run can leak into the new one).
//   en    : when 1, the PE does a multiply-accumulate and moves data along.
//           When 0, the PE freezes (all registers hold their value).
// Priority: rst > clear > en.
// ============================================================================

module pe #(
    parameter int DATA_W = 8,    // width of each input (signed INT8)
    parameter int ACC_W  = 32    // width of the accumulator (signed)
) (
    input  logic                     clk,
    input  logic                     rst,
    input  logic                     en,
    input  logic                     clear,

    input  logic signed [DATA_W-1:0] a_in,   // from the left neighbour
    input  logic signed [DATA_W-1:0] b_in,   // from the top neighbour

    output logic signed [DATA_W-1:0] a_out,  // to the right neighbour
    output logic signed [DATA_W-1:0] b_out,  // to the bottom neighbour
    output logic signed [ACC_W-1:0]  acc     // running sum = C[i][j]
);

    // The product of two signed 8-bit numbers needs 16 bits.
    // (-128 * -128 = +16384, which needs 16 bits including the sign bit.)
    // Because a_in and b_in are both declared "signed", this is a signed
    // multiply.
    logic signed [2*DATA_W-1:0] product;
    assign product = a_in * b_in;

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            acc   <= '0;
            a_out <= '0;
            b_out <= '0;
        end else if (en) begin
            // "product" is sign-extended to ACC_W bits before the add,
            // because both sides of the + are signed.
            acc   <= acc + product;
            a_out <= a_in;
            b_out <= b_in;
        end
        // else: en = 0, so every register keeps its old value.
    end

endmodule
