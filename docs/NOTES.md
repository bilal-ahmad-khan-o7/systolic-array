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
