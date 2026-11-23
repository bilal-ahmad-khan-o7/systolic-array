// ============================================================================
// mm_tests.svh - Shared self-checking test program for matrix-multiply DUTs
// ============================================================================
// This file is `included INSIDE a testbench module (tb_systolic_mm.sv and
// tb_mac_baseline.sv). Both DUTs have identical ports, so they share the
// exact same tests. Before including this file the testbench must declare:
//
//   localparam int N, DATA_W, ACC_W, EXP_LATENCY
//   localparam string TB_NAME
//   logic clk, rst, start, busy, done
//   logic [N*N*DATA_W-1:0] a_flat, b_flat
//   logic [N*N*ACC_W-1:0]  c_flat
//   ...and instantiate the DUT as "dut".
//
// Timing rule used everywhere: the testbench changes inputs on the FALLING
// edge of the clock and the DUT samples on the RISING edge, so there are no
// races. A "cycle" is one clock period; the cycle in which start is high is
// cycle 0, and latency = the cycle number in which done is high.
// ============================================================================

    // ---------------- Matrices used by the tests ----------------
    int A    [0:N-1][0:N-1];
    int B    [0:N-1][0:N-1];
    int Cexp [0:N-1][0:N-1];   // golden (expected) answer

    int errors     = 0;        // total mismatches of any kind
    int runs       = 0;        // number of matrix multiplies checked
    int seed       = 2024;     // fixed seed -> the same "random" tests every time
    int last_latency;

    always #5 clk = ~clk;      // 10 ns period = 100 MHz

    // ---------------- Helpers ----------------

    // A random signed 8-bit value (-128 .. 127).
    function automatic int rand_int8();
        logic signed [7:0] v;
        v = $random(seed);
        return v;
    endfunction

    // Golden model: plain triple loop, C = A x B, using 32-bit ints.
    task automatic golden_mm();
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++) begin
                Cexp[i][j] = 0;
                for (int k = 0; k < N; k++)
                    Cexp[i][j] += A[i][k] * B[k][j];
            end
    endtask

    // Pack the A and B arrays into the DUT's flat input buses.
    task automatic drive_inputs();
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin
                a_flat[(r*N + c)*DATA_W +: DATA_W] = A[r][c];
                b_flat[(r*N + c)*DATA_W +: DATA_W] = B[r][c];
            end
    endtask

    // Compare every element of the DUT's C with the golden C.
    task automatic check_c(input string name);
        int bad = 0;
        logic signed [ACC_W-1:0] got;
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++) begin
                got = c_flat[(i*N + j)*ACC_W +: ACC_W];
                if (got !== Cexp[i][j]) begin
                    if (bad < 4)   // don't flood the log
                        $display("  [%s] C[%0d][%0d]: got %0d, expected %0d",
                                 name, i, j, got, Cexp[i][j]);
                    bad++;
                end
            end
        if (bad > 0) begin
            $display("  [%s] FAILED: %0d of %0d elements wrong", name, bad, N*N);
            errors++;
        end
    endtask

    // ------------------------------------------------------------------
    // One complete run. Call this at a falling edge.
    //   - Drives A/B and raises start (this is cycle 0).
    //   - While the DUT is busy, scribbles random garbage on a_flat / b_flat
    //     and randomly toggles start. A correct DUT ignores all of it because
    //     it copied A and B at start and ignores start while busy.
    //   - Checks busy is high and done is low until done arrives.
    //   - Checks the latency and the result.
    //   - Returns at the falling edge of the DONE cycle, so the caller can
    //     either start the next run immediately (back-to-back) or wait.
    // ------------------------------------------------------------------
    task automatic run_and_check(input string name);
        int cyc;
        golden_mm();
        drive_inputs();
        start = 1;                         // cycle 0
        cyc   = 0;
        @(negedge clk);                    // now in cycle 1
        cyc = 1;
        while (!done) begin
            if (!busy) begin
                $display("  [%s] busy is low in cycle %0d before done", name, cyc);
                errors++;
            end
            if (cyc > EXP_LATENCY + 20) begin
                $display("  [%s] TIMEOUT: done never arrived", name);
                $display("FAIL: %s", TB_NAME);
                $finish;
            end
            // Noise while busy. Never touch start in the cycle right before
            // the expected DONE (start sampled in DONE means "go again").
            a_flat = {N*N{$random(seed)}};
            b_flat = {N*N{$random(seed)}};
            start  = (cyc < EXP_LATENCY - 1) ? $random(seed) : 1'b0;
            @(negedge clk);
            cyc++;
        end
        start = 0;
        // We are now at the falling edge of the DONE cycle.
        last_latency = cyc;
        if (cyc != EXP_LATENCY) begin
            $display("  [%s] latency %0d cycles, expected %0d", name, cyc, EXP_LATENCY);
            errors++;
        end
        if (busy) begin
            $display("  [%s] busy still high while done is high", name);
            errors++;
        end
        check_c(name);
        runs++;
    endtask

    // After a run, go back to idle and make sure done was a 1-cycle pulse.
    task automatic idle_cycles(input int n);
        for (int c = 0; c < n; c++) begin
            @(negedge clk);
            if (done || busy) begin
                $display("  done/busy not low after the run (done=%b busy=%b)", done, busy);
                errors++;
            end
        end
    endtask

    // ---------------- Matrix fill helpers ----------------
    task automatic fill_const(input int va, input int vb);
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++) begin
                A[i][j] = va;
                B[i][j] = vb;
            end
    endtask

    task automatic fill_random();
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++) begin
                A[i][j] = rand_int8();
                B[i][j] = rand_int8();
            end
    endtask

    // ------------------------------------------------------------------
    // The test program
    // ------------------------------------------------------------------
    initial begin
        $display("=== %s: N=%0d, expected latency %0d cycles ===", TB_NAME, N, EXP_LATENCY);
        clk = 0; rst = 1; start = 0; a_flat = '0; b_flat = '0;
        repeat (3) @(negedge clk);
        rst = 0;                    // the ONLY reset in the whole test
        @(negedge clk);

        // ---- Walkthrough run (this is the one saved to the VCD) ----
        // A = 1..16 row by row, B = small distinct values, so the skewing
        // is easy to follow in GTKWave.
        $dumpfile({"build/", TB_NAME, ".vcd"});
        $dumpvars(0, dut);
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++) begin
                A[i][j] = i*N + j + 1;
                B[i][j] = (i == j) ? 2 : -(i + j);
            end
        run_and_check("walkthrough");
        idle_cycles(2);
        $dumpoff;
        $display("  latency start->done: %0d cycles", last_latency);

        // ---- Directed tests ----
        fill_const(0, 0);
        run_and_check("all zeros");          idle_cycles(1);

        fill_random();                       // B = identity -> C = A
        for (int i = 0; i < N; i++) for (int j = 0; j < N; j++) B[i][j] = (i == j);
        run_and_check("A x I");              idle_cycles(1);

        fill_random();                       // A = identity -> C = B
        for (int i = 0; i < N; i++) for (int j = 0; j < N; j++) A[i][j] = (i == j);
        run_and_check("I x B");              idle_cycles(1);

        fill_const(127, 127);                // every C = 4*127*127 = 64516
        run_and_check("all +127");           idle_cycles(1);

        fill_const(-128, -128);              // every C = 4*16384 = 65536
        run_and_check("all -128");           idle_cycles(1);

        fill_const(-128, 127);               // every C = 4*(-16256) = -65024
        run_and_check("-128 x +127");        idle_cycles(1);

        // Mixed signs: checkerboard of +127 / -128 in A, opposite in B
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++) begin
                A[i][j] = ((i + j) % 2) ? -128 : 127;
                B[i][j] = ((i + j) % 2) ? 127 : -128;
            end
        run_and_check("checkerboard");       idle_cycles(1);

        for (int i = 0; i < N; i++)          // small mixed signs
            for (int j = 0; j < N; j++) begin
                A[i][j] = (i - j) * 3;
                B[i][j] = (j % 2) ? -(i + 1) : (i + 1);
            end
        run_and_check("mixed signs");        idle_cycles(1);
        $display("  directed tests done, errors so far: %0d", errors);

        // ---- 1000 random matrices, random gap 0-3 idle cycles between runs ----
        for (int t = 0; t < 1000; t++) begin
            fill_random();
            run_and_check($sformatf("random #%0d", t));
            // gap 0 means start the next run in the DONE cycle (no gap at all)
            idle_cycles($unsigned($random(seed)) % 4);
        end
        $display("  random tests done, errors so far: %0d", errors);

        // ---- 50 back-to-back runs with zero idle cycles, no reset ----
        for (int t = 0; t < 50; t++) begin
            fill_random();
            run_and_check($sformatf("back-to-back #%0d", t));
        end
        idle_cycles(2);
        $display("  back-to-back tests done, errors so far: %0d", errors);

        $display("%s: %0d runs checked, %0d errors, latency %0d cycles",
                 TB_NAME, runs, errors, last_latency);
        if (errors == 0) $display("PASS: %s", TB_NAME);
        else             $display("FAIL: %s", TB_NAME);
        $finish;
    end
