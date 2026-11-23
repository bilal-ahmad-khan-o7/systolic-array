`timescale 1ns/1ps
// ============================================================================
// systolic_mm.sv - Top level: C = A x B using a 4x4 systolic array
// ============================================================================
// How to use it:
//   1. Put A and B on a_flat / b_flat and pulse start for one cycle.
//      (A and B are copied into internal registers on that clock edge, so the
//      inputs are free to change afterwards.)
//   2. busy goes high while the array works.
//   3. done pulses high for exactly one cycle when c_flat holds the answer.
//      c_flat keeps its value until the next run starts clearing the array.
//   start is ignored while busy. If start is high during the DONE cycle, a new
//   run begins immediately (back-to-back runs with no gap).
//
// Flat bus layout (row-major, same for A, B and C):
//   A[i][k] is a_flat[(i*N + k)*DATA_W +: DATA_W]
//   B[k][j] is b_flat[(k*N + j)*DATA_W +: DATA_W]
//   C[i][j] is c_flat[(i*N + j)*ACC_W  +: ACC_W ]
//
// The FSM:
//
//   IDLE --start--> CLEAR --> COMPUTE (3N-2 cycles) --> DONE --> IDLE
//                     ^                                   |
//                     +--------------start----------------+
//
//   IDLE    : wait for start. On start, copy A and B into a_reg / b_reg.
//   CLEAR   : one cycle with clear = 1, zeroing every accumulator and
//             pipeline register in the array and feeder.
//   COMPUTE : en = 1 for 3N-2 cycles. During steps 0..N-1 we feed column k of
//             A and row k of B into the skew feeder. After that we feed zeros
//             while the last values ripple through to PE(N-1,N-1).
//   DONE    : done = 1 for one cycle.
//
// Latency (start sampled -> done high) = 1 (CLEAR) + (3N-2) (COMPUTE) + 1 = 3N
// cycles, i.e. 12 cycles for N = 4. See docs/NOTES.md for the full breakdown.
// ============================================================================

module systolic_mm #(
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

    // Number of cycles the array must run: the last PE, PE(N-1,N-1), receives
    // its first pair at cycle 2(N-1) and its last pair N-1 cycles later,
    // at cycle 3N-3. Counting from cycle 0, that is 3N-2 cycles.
    localparam int COMPUTE_CYCLES = 3*N - 2;
    localparam int STEP_W         = $clog2(COMPUTE_CYCLES);

    // ------------------------------------------------------------------
    // FSM state and registers
    // ------------------------------------------------------------------
    typedef enum logic [1:0] {IDLE, CLEAR, COMPUTE, DONE} state_t;
    state_t state;

    logic [STEP_W-1:0]     step;   // which COMPUTE cycle we are in (0 .. 3N-3)
    logic [N*N*DATA_W-1:0] a_reg;  // private copy of A, taken at start
    logic [N*N*DATA_W-1:0] b_reg;  // private copy of B, taken at start

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            step  <= '0;
            a_reg <= '0;
            b_reg <= '0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        a_reg <= a_flat;
                        b_reg <= b_flat;
                        state <= CLEAR;
                    end
                end

                CLEAR: begin
                    step  <= '0;
                    state <= COMPUTE;
                end

                COMPUTE: begin
                    if (step == COMPUTE_CYCLES - 1) state <= DONE;
                    else                            step  <= step + 1'b1;
                end

                DONE: begin
                    if (start) begin           // back-to-back: go again
                        a_reg <= a_flat;
                        b_reg <= b_flat;
                        state <= CLEAR;
                    end else begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Control outputs (pure decode of the state, no extra registers)
    // ------------------------------------------------------------------
    logic array_en, array_clear;

    assign array_clear = (state == CLEAR);
    assign array_en    = (state == COMPUTE);
    assign busy        = (state == CLEAR) || (state == COMPUTE);
    assign done        = (state == DONE);

    // ------------------------------------------------------------------
    // Feed one column of A and one row of B per cycle
    //   step k < N : lane r of feed_a = A[r][k],  lane c of feed_b = B[k][c]
    //   step k >= N: zeros (so the array just finishes what is in flight)
    // ------------------------------------------------------------------
    logic [N*DATA_W-1:0] feed_a, feed_b;

    always_comb begin
        feed_a = '0;
        feed_b = '0;
        if (state == COMPUTE && step < N) begin
            for (int r = 0; r < N; r++) begin
                feed_a[r*DATA_W +: DATA_W] = a_reg[(r*N + step)*DATA_W +: DATA_W];
                feed_b[r*DATA_W +: DATA_W] = b_reg[(step*N + r)*DATA_W +: DATA_W];
            end
        end
    end

    // ------------------------------------------------------------------
    // Skew feeder -> systolic array
    // ------------------------------------------------------------------
    logic [N*DATA_W-1:0] a_skewed, b_skewed;

    skew_feeder #(.N(N), .DATA_W(DATA_W)) u_feeder (
        .clk   (clk),
        .rst   (rst),
        .en    (array_en),
        .clear (array_clear),
        .a_in  (feed_a),
        .b_in  (feed_b),
        .a_out (a_skewed),
        .b_out (b_skewed)
    );

    systolic_array #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) u_array (
        .clk    (clk),
        .rst    (rst),
        .en     (array_en),
        .clear  (array_clear),
        .a_left (a_skewed),
        .b_top  (b_skewed),
        .c_flat (c_flat)
    );

endmodule
