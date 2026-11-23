// ============================================================================
// tb_pe.sv - Self-checking unit test for pe.sv
// ============================================================================
// How it works:
//   - The testbench keeps its own "model" of what the PE should contain
//     (model_acc, model_a_out, model_b_out).
//   - Every clock cycle we drive new inputs, let the clock tick, then compare
//     the real PE against the model.
//   - Inputs are changed on the FALLING edge of the clock so they are stable
//     well before the RISING edge, where the PE samples them. This avoids
//     simulation race conditions.
// At the end we print PASS or FAIL.
// ============================================================================

`timescale 1ns/1ps

module tb_pe;

    localparam int DATA_W = 8;
    localparam int ACC_W  = 32;

    // ---------------- DUT signals ----------------
    logic                     clk = 0;
    logic                     rst, en, clear;
    logic signed [DATA_W-1:0] a_in, b_in;
    logic signed [DATA_W-1:0] a_out, b_out;
    logic signed [ACC_W-1:0]  acc;

    pe #(.DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .clk(clk), .rst(rst), .en(en), .clear(clear),
        .a_in(a_in), .b_in(b_in),
        .a_out(a_out), .b_out(b_out), .acc(acc)
    );

    always #5 clk = ~clk;   // 10 ns clock period (100 MHz)

    // ---------------- Reference model ----------------
    int model_acc, model_a_out, model_b_out;
    int errors = 0;
    int checks = 0;
    int seed   = 12345;

    // Apply one cycle of inputs, tick the clock, update the model, compare.
    task automatic step(input logic r, input logic c, input logic e,
                        input int a, input int b);
        @(negedge clk);
        rst = r; clear = c; en = e; a_in = a; b_in = b;
        @(posedge clk);
        // Model the same priority as the RTL: rst > clear > en
        if (r || c) begin
            model_acc = 0; model_a_out = 0; model_b_out = 0;
        end else if (e) begin
            model_acc   = model_acc + int'(a_in) * int'(b_in);
            model_a_out = a_in;
            model_b_out = b_in;
        end
        #1; // let the register outputs settle before comparing
        checks++;
        if (acc !== model_acc || a_out !== model_a_out || b_out !== model_b_out) begin
            errors++;
            $display("  MISMATCH t=%0t: in a=%0d b=%0d rst=%b clr=%b en=%b | got acc=%0d a_out=%0d b_out=%0d | exp acc=%0d a_out=%0d b_out=%0d",
                     $time, a_in, b_in, r, c, e, acc, a_out, b_out,
                     model_acc, model_a_out, model_b_out);
        end
    endtask

    initial begin
        $display("=== tb_pe: PE unit test ===");
        rst = 1; clear = 0; en = 0; a_in = 0; b_in = 0;
        model_acc = 0; model_a_out = 0; model_b_out = 0;

        // 1) Reset puts everything at 0
        step(1, 0, 0, 0, 0);
        step(1, 0, 1, 55, 66);           // reset wins over en

        // 2) Simple positive accumulate: 2*3 + 4*5 = 26
        step(0, 0, 1, 2, 3);
        step(0, 0, 1, 4, 5);

        // 3) en = 0 must freeze everything (inputs are ignored)
        step(0, 0, 0, 100, 100);
        step(0, 0, 0, -7, 9);

        // 4) Synchronous clear wipes acc and pass-through registers
        step(0, 1, 1, 9, 9);             // clear wins over en

        // 5) Signed edge cases
        step(0, 0, 1, -128, -128);       // +16384 (largest product)
        step(0, 0, 1, -128, 127);        // -16256
        step(0, 0, 1, 127, 127);         // +16129
        step(0, 0, 1, -1, 1);            // -1
        step(0, 0, 1, -5, -6);           // +30
        step(0, 1, 0, 0, 0);             // clear

        // 6) Accumulate a large negative total: 4 x (-128*127)
        repeat (4) step(0, 0, 1, -128, 127);
        step(0, 1, 0, 0, 0);

        // 7) Random test: 2000 cycles of random inputs and controls
        repeat (2000) begin
            int r, c, e;
            r = ($random(seed) % 100 == 0);       // rare reset
            c = ($random(seed) % 20  == 0);       // occasional clear
            e = ($random(seed) % 4   != 0);       // mostly enabled
            // a and b get the low 8 bits of a random number: any value -128..127
            step(r, c, e, $random(seed), $random(seed));
        end

        // 8) Stress the accumulator: 1000 x (-128*-128) = 16,384,000
        //    (fits in 32 bits; checks there is no hidden 16-bit truncation)
        step(0, 1, 0, 0, 0);
        repeat (1000) step(0, 0, 1, -128, -128);

        $display("tb_pe: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("PASS: tb_pe");
        else             $display("FAIL: tb_pe");
        $finish;
    end

endmodule
