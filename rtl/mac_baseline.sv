`timescale 1ns/1ps
// ============================================================================
// mac_baseline.sv - The "slow but simple" reference: ONE multiply-accumulator
// ============================================================================
// Computes the same C = A x B as systolic_mm, with the same ports, but using
// a single multiplier. It walks through the classic triple loop, doing one
// multiply-accumulate per clock cycle:
//
//   for i in 0..N-1:          (row of C)
//     for j in 0..N-1:        (column of C)
//       acc = 0
//       for k in 0..N-1:
//         acc += A[i][k] * B[k][j]
//       C[i][j] = acc
//
// That is N*N*N = 64 cycles of work for N = 4. It exists only so we can
// compare cycle counts and FPGA resources against the systolic array.
//
// FSM:  IDLE --start--> COMPUTE (N^3 cycles) --> DONE --> IDLE
//                          ^                       |
//                          +--------start----------+   (back-to-back)
//
// Latency (start sampled -> done high) = N^3 + 1 = 65 cycles for N = 4.
// ============================================================================

module mac_baseline #(
    parameter int N      = 4,
    parameter int DATA_W = 8,
    parameter int ACC_W  = 32
) (
    input  logic                  clk,
    input  logic                  rst,       // active-high, synchronous
    input  logic                  start,
    input  logic [N*N*DATA_W-1:0] a_flat,
    input  logic [N*N*DATA_W-1:0] b_flat,
    output logic                  busy,
    output logic                  done,
    output logic [N*N*ACC_W-1:0]  c_flat
);

    localparam int IDX_W = (N > 1) ? $clog2(N) : 1;

    typedef enum logic [1:0] {IDLE, COMPUTE, DONE} state_t;
    state_t state;

    logic [IDX_W-1:0]        i, j, k;    // loop counters
    logic [N*N*DATA_W-1:0]   a_reg;      // private copy of A, taken at start
    logic [N*N*DATA_W-1:0]   b_reg;      // private copy of B, taken at start
    logic signed [ACC_W-1:0] acc;        // running sum for the current C[i][j]
    logic [N*N*ACC_W-1:0]    c_reg;      // finished results

    // ------------------------------------------------------------------
    // The single MAC: pick A[i][k] and B[k][j], multiply, add.
    // When k == 0 we start a new dot product, so add to 0 instead of acc.
    // ------------------------------------------------------------------
    logic signed [DATA_W-1:0]   a_val, b_val;
    logic signed [2*DATA_W-1:0] product;
    logic signed [ACC_W-1:0]    acc_base;   // what we add the product to
    logic signed [ACC_W-1:0]    sum;

    assign a_val    = a_reg[(i*N + k)*DATA_W +: DATA_W];   // A[i][k]
    assign b_val    = b_reg[(k*N + j)*DATA_W +: DATA_W];   // B[k][j]
    assign product  = a_val * b_val;                       // signed multiply
    assign acc_base = (k == 0) ? '0 : acc;
    // Keep this add on its own line with two SIGNED operands. Writing
    //   sum = ((k == 0) ? '0 : acc) + product;
    // looks the same but is WRONG: '0 is an unsigned literal, which makes the
    // whole expression unsigned, so "product" gets zero-extended instead of
    // sign-extended (-7 turns into +65529). The testbench caught exactly that.
    assign sum      = acc_base + product;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            i <= '0; j <= '0; k <= '0;
            acc   <= '0;
            a_reg <= '0;
            b_reg <= '0;
            c_reg <= '0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        a_reg <= a_flat;
                        b_reg <= b_flat;
                        i <= '0; j <= '0; k <= '0;
                        state <= COMPUTE;
                    end
                end

                COMPUTE: begin
                    acc <= sum;
                    if (k == N-1) begin
                        // Dot product finished: store C[i][j], move to the next one.
                        c_reg[(i*N + j)*ACC_W +: ACC_W] <= sum;
                        k <= '0;
                        if (j == N-1) begin
                            j <= '0;
                            if (i == N-1) state <= DONE;   // that was the last one
                            else          i <= i + 1'b1;
                        end else begin
                            j <= j + 1'b1;
                        end
                    end else begin
                        k <= k + 1'b1;
                    end
                end

                DONE: begin
                    if (start) begin           // back-to-back: go again
                        a_reg <= a_flat;
                        b_reg <= b_flat;
                        i <= '0; j <= '0; k <= '0;
                        state <= COMPUTE;
                    end else begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign busy   = (state == COMPUTE);
    assign done   = (state == DONE);
    assign c_flat = c_reg;

endmodule
