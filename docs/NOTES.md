# Design Notes

Plain-English notes written while building the project, one section per step.
Each section ends with a few interview-style questions and answers.

---

## Step 1 — Processing Element (`rtl/pe.sv`)

**What it does.** A PE is one cell of the grid. Every clock cycle (while `en`
is high) it multiplies the `a` value coming from the left by the `b` value
coming from the top, adds the product to its accumulator, and passes `a` to the
right and `b` downward through registers.

**Why it's built this way.**
- *Registered pass-through.* Putting a register on `a_out` and `b_out` means
  data moves exactly one PE per cycle. Every wire is short (only to the
  neighbour), so the clock can be fast no matter how big the grid gets.
- *16-bit product, 32-bit accumulator.* Two signed 8-bit numbers multiply to at
  most `-128 × -128 = 16384`, which needs 16 bits. A 4-element dot product is at
  most `4 × 16384 = 65536`, so 32 bits is far more than enough (it leaves room
  for much larger N).
- *`signed` everywhere.* In Verilog a multiply is only signed if **both**
  operands are signed. If one side were unsigned, `-1` would be treated as
  `255` and the answer would be wrong. (The testbench was checked against a
  deliberately broken unsigned copy and correctly reported FAIL.)
- *`clear` also zeroes the pass-through registers.* The spec only needs the
  accumulator cleared, but also wiping `a_out`/`b_out` means a new run never
  depends on what was left in the pipeline from the last one.
- *Synchronous reset.* Xilinx FPGAs prefer synchronous resets — they map
  cleanly onto the flip-flops and DSP blocks.

**Test (`tb/tb_pe.sv`).** The testbench keeps its own model of what `acc`,
`a_out` and `b_out` should be, and compares after every clock. It covers reset,
`en = 0` freezing, clear, priority (reset > clear > en), the signed edge cases
(`-128 × -128`, `-128 × 127`, `127 × 127`), 2000 random cycles, and 1000
back-to-back `-128 × -128` MACs to prove the accumulator isn't secretly 16 bits.
Result: **3019 checks, 0 errors — PASS.**

**Interview questions**

1. *Why is the product 16 bits and not 8?*
   Multiplying an m-bit by an n-bit number needs m+n bits. 8+8 = 16. The worst
   case, `-128 × -128 = +16384`, really does need all 16 bits.

2. *What happens if you forget `signed` on one input?*
   Verilog treats the whole expression as unsigned, so negative numbers become
   large positive ones (`-1` becomes `255`) and the result is wrong. It still
   compiles without any error, which is why it's a common bug.

3. *Why does the PE register its outputs instead of just wiring `a_in` to `a_out`?*
   If it were just a wire, a value would race across the whole row in one cycle
   and every PE would see the same value at the same time. The register is what
   creates the one-cycle-per-PE "wave", and it keeps the critical path short
   (one multiply + one add) no matter how large N is.

---

## Step 2 — The grid (`rtl/systolic_array.sv`)

**What it does.** Builds an N×N grid of PEs with two nested `generate` loops and
wires each PE's `a_out` to its right neighbour and `b_out` to the neighbour
below. Row `i` of the left edge feeds `a_left[i]`; column `j` of the top edge
feeds `b_top[j]`. Every PE's accumulator is exposed on the flat `c_flat` bus.

**Why it's built this way.**
- *`generate` loops* mean the same code works for any `N` — change one
  parameter and you get a 2×2 or 8×8 array.
- *Wire arrays with one extra column/row* (`a_wire[i][0..N]`,
  `b_wire[0..N][j]`) make the indexing uniform: PE(i,j) always reads
  `[i][j]` and writes `[i][j+1]` / `[i+1][j]`. The extra entries are what
  "falls off" the edge and are simply unused (synthesis removes them).
- *No skewing here.* Keeping the delay logic in a separate module keeps this
  one pure wiring, which is easier to read and test.

**Check.** A throwaway 2×2 smoke test with hand-skewed inputs
(A = [[1,2],[3,4]], B = [[5,6],[7,8]]) produced C = [[19,22],[43,50]] — correct.
Full verification happens at the top level (step 4).

**Interview questions**

1. *Why "output-stationary"? What are the alternatives?*
   The output C[i][j] stays put in one PE while A and B flow past it. In
   *weight-stationary* (used by Google's TPU) the B/weight values are preloaded
   into the PEs and stay put while A flows through and partial sums flow down.
   In *input-stationary* the A values stay put. Output-stationary is the
   simplest to understand because each PE just accumulates one dot product.

2. *How many multipliers does an N×N array use, and how many MACs does it do per cycle?*
   N² multipliers (16 for N=4). When the pipeline is full, all N² do useful
   work each cycle, versus 1 for a single MAC unit.

3. *Why don't long wires appear as N grows?*
   Each PE only talks to its immediate neighbours, so wire length doesn't grow
   with N. The control signals (`en`, `clear`) do fan out to every PE, but they
   are slow-changing and easy to pipeline if needed.

---

## Step 3 — Skew feeder (`rtl/skew_feeder.sv`)

**What it does.** Delays lane `i` of A by `i` cycles and lane `j` of B by `j`
cycles using shift registers. Lane 0 is a plain wire. The result is the
"staircase" (diagonal wavefront) that a systolic array needs.

**Why it's built this way.**
- *Why skew at all?* PE(i,j) needs `A[i][k]` and `B[k][j]` at the same moment.
  `A[i][k]` takes `j` cycles to travel right to column `j`; `B[k][j]` takes `i`
  cycles to travel down to row `i`. If row `i` starts `i` cycles late and
  column `j` starts `j` cycles late, both arrive at cycle `k + i + j`. Without
  the skew, PE(i,j) would multiply mismatched pairs like `A[i][k] × B[k+1][j]`.
- *Shift registers, not counters.* A delay of `d` cycles is exactly `d`
  flip-flops in a chain. Total storage: `0+1+2+3 = 6` registers per side for
  N=4, i.e. `N(N-1)/2`.
- *Same `en` and `clear` as the array* so the feeder and grid always stay in
  step, and a new run starts from empty shift registers.

**Check.** A throwaway smoke test fed lane value `10·lane + step` and printed
the outputs: lane 0 showed 1,2,3,4 at t0–t3, lane 1 showed 11–14 at t1–t4,
lane 3 showed 31–34 at t3–t6 — the expected staircase.

**Interview questions**

1. *What goes wrong if you remove the skew?*
   Every PE in a row would see the same A value at the same time, but the B
   values reach lower rows later, so PE(i,j) would multiply `A[i][k]` with the
   wrong row of B. The result is silently wrong, not an error.

2. *How many registers does the skew cost, and how does it scale?*
   `N(N-1)/2` per input matrix, so `N(N-1)` total. That's O(N²), the same order
   as the PE grid itself, so it's a small overhead.

3. *Could you avoid the skew registers?*
   Yes — if the memory that supplies A and B can output the data already
   staggered (e.g. each row's read starts one cycle later), the delays are
   "free". Here a separate module is clearer and keeps the top simple.

---

## Step 4 — Top level and FSM (`rtl/systolic_mm.sv`)

**What it does.** Takes A and B as flat buses, copies them into internal
registers on `start`, and runs a 4-state FSM:

| State   | Cycles | What happens |
|---------|--------|--------------|
| IDLE    | —      | Wait for `start`. On `start`, copy A and B into `a_reg`/`b_reg`. |
| CLEAR   | 1      | `clear = 1`: zero every accumulator and pipeline register. |
| COMPUTE | 3N−2   | `en = 1`. Steps 0..N−1 feed column k of A and row k of B; later steps feed zeros. |
| DONE    | 1      | `done = 1`. If `start` is high here, go straight to CLEAR (back-to-back). |

**Measured latency: 12 cycles from `start` to `done`** (start is high in cycle
0, done is high in cycle 12). The testbench checks this exact number on every
one of its 1059 runs.

**Why 12 and not 10?** The theoretical 3N−2 = 10 cycles is only the time the
array itself spends computing:
- PE(i,j) gets its first pair at compute step `i+j` and its last at `i+j+N−1`.
- The last PE, PE(3,3), finishes at step `3+3+3 = 9`, so steps 0..9 = **10 cycles**.

The FSM adds **2 cycles** of overhead:
- **+1 for CLEAR**: the accumulators from the previous run must be zeroed
  before the new data arrives.
- **+1 for DONE**: the last accumulate happens on the clock edge that *ends*
  compute step 9, so the answer is only visible in the next cycle, which is
  where `done` is raised.

So `1 + 10 + 1 = 12 = 3N`. The same TB, re-run with N = 2, 3 and 8, measured
6, 9 and 24 cycles — exactly 3N every time.

*Could you save those 2 cycles?* Yes: you could clear the accumulators in the
same cycle that `start` is accepted, and raise `done` combinationally during
the last compute step. That makes the control logic harder to read and puts
the `done` signal on a longer path, so this design keeps the simple version.
Note that with back-to-back runs the throughput is one result every 12 cycles,
because the next run's CLEAR starts right after DONE.

**Why it's built this way.**
- *Copy A and B on start.* The caller can change `a_flat`/`b_flat` the very
  next cycle. The testbench checks this by putting random garbage on the
  inputs while the DUT is busy.
- *Ignore `start` while busy.* The testbench also toggles `start` randomly
  during every run; a correct design ignores it.
- *Feed zeros after the data.* After step N−1 there is nothing left to send,
  but values are still moving through the grid; feeding zeros means the extra
  cycles add `0 × 0` and don't disturb the answer.

**Test (`tb/tb_systolic_mm.sv` + shared `tb/mm_tests.svh`).** A golden-model
triple loop in the testbench, compared element by element. Tests: a
walkthrough run (dumped to VCD), all zeros, A×I, I×B, all +127, all −128,
−128×+127, a ±127/−128 checkerboard, small mixed signs, 1000 random matrices
(seed 2024) with random 0–3 cycle gaps, and 50 back-to-back runs with zero gap.
Only one reset at the very start. Result: **1059 runs, 0 errors — PASS.**

To make sure the tests can actually fail, seven deliberate bugs were tried
(no skew, one compute cycle short, no input copy, no back-to-back restart,
unsigned multiply, no clear, 16-bit accumulator). **Every one was caught.**

**Interview questions**

1. *Your array computes in 10 cycles but you report 12. Why?*
   10 cycles (3N−2) is the time from the first data entering PE(0,0) to the
   last accumulate in PE(3,3). One cycle before that is spent clearing the
   accumulators and one after is spent presenting the result with `done`. Both
   could be overlapped with more complex control, but they cost little.

2. *Why is the compute time 3N−2 and not N?*
   Each PE only needs N cycles of real work, but the skew means PE(i,j) starts
   `i+j` cycles late. The farthest PE starts `2(N−1)` cycles late and then needs
   N cycles: `2(N−1) + N = 3N−2`. This "fill and drain" time is why systolic
   arrays are most efficient when you stream many matrices through them.

3. *How would you make back-to-back runs faster?*
   Overlap them: start feeding the next A and B while the previous result is
   still draining, and copy each finished C into an output register so the
   accumulators can be reused. With full overlap you can start a new tile every
   N cycles instead of every 3N.

---

## Step 5 — Single-MAC baseline (`rtl/mac_baseline.sv`)

**What it does.** The same ports and the same answer as `systolic_mm`, but with
just **one** multiplier. Three counters `i, j, k` walk the textbook triple
loop, doing one multiply-accumulate per cycle. When `k` reaches N−1 the
finished dot product is written into `C[i][j]`.

**Measured latency: 65 cycles** (N³ = 64 compute cycles + 1 DONE cycle). It
has no CLEAR state because each dot product simply starts from 0 when `k = 0`.
Compared to the systolic array's 12 cycles, that's **5.4× faster** for the
array, using 16 multipliers instead of 1. (For N = 8: 513 vs 24 cycles, 21×.)

**A real bug found by the tests.** The first version had:

```systemverilog
assign sum = ((k == 0) ? '0 : acc) + product;
```

The baseline TB failed on 1056 of 1059 runs, with results like `65529` where
`-7` was expected. `'0` is an *unsigned* literal, and in Verilog one unsigned
operand makes the whole expression unsigned — so `product` was zero-extended
instead of sign-extended. The fix was to compute `acc_base = (k == 0) ? '0 : acc`
into its own `signed` signal and then do `sum = acc_base + product` with two
signed operands. The test was not changed.

**Why it's built this way.** It's deliberately the simplest correct design:
one multiplier, a few counters, no pipelining. It answers the question "what
does the systolic array actually buy you?" with real numbers.

**Interview questions**

1. *Systolic array: 12 cycles with 16 multipliers. Baseline: 65 cycles with 1. Is that a good trade?*
   Speedup is 65/12 ≈ 5.4×, not 16×, because of the fill/drain time (3N−2
   instead of N) and the 2 cycles of FSM overhead. If you stream many
   matrices through and overlap the runs, the array approaches one result every
   N cycles, i.e. 64/4 = 16× — the full benefit of 16 multipliers.

2. *What's the signedness rule that caused the bug?*
   An expression is only signed if *every* operand is signed. Unsized literals
   like `'0`, `'1` and plain part-selects like `bus[7:0]` are unsigned. Mixing
   one in silently turns the whole expression unsigned. Safe habits: put
   signed values in `logic signed` signals before doing maths, or use
   `$signed(...)`.

3. *Why does the baseline still need N² × 32 bits of output registers?*
   It produces the 16 results one at a time over 64 cycles, so it has to store
   them somewhere until the end. In the systolic array the accumulators *are*
   the storage, so no extra output registers are needed.
