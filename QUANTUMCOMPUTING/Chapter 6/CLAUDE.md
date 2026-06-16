# Chapter 6 — Quantum Algorithms: Deutsch-Jozsa & Grover

## Project overview

This chapter implements three quantum algorithms in Qiskit and documents them in
LaTeX. All simulation runs on `qiskit-aer`; one cell also submits to a real IBM
quantum computer via `qiskit-ibm-runtime`.

---

## Files

| File | Purpose |
|---|---|
| `Code/Deutsch-Jozsa.ipynb` | Deutsch-Jozsa algorithm — classifies oracles as constant or balanced |
| `Code/groove_algo.ipynb` | Grover search + Dürr-Høyer minimum search with ERS |
| `random_qc_circtuits.tex` | LaTeX quantum circuit diagrams (quantikz) |
| `exercices_quantique_chapter_6.tex` | Chapter exercises (QFT phase arithmetic, polynomial circuits) |
| `Rapport_Algo_DJ_et_Grover.tex` | Main report: DJ, Grover search, Dürr-Høyer, BBHT proof |

---

## Deutsch-Jozsa (`Deutsch-Jozsa.ipynb`)

### What it does
Determines in a single query whether a boolean function f: {0,1}^n → {0,1} is
**constant** (same output for all inputs) or **balanced** (half 0, half 1).

### Key implementation points
- Qiskit 2.x: first run triggers a Rust cache build — the kernel appears stuck for
  ~30–60s, this is normal.
- `categorize_function(n, counts)` receives a Qiskit measurement dict
  `{'000': 1024}`, not a list of bits. It checks:
  - All shots on all-zeros → **constant**
  - Zero shots on all-zeros → **balanced**
  - Mixed → **other**
- `N_MAX = 3` (not 4) to avoid exponential blowup (4^n oracles per n).

---

## Grover search (`groove_algo.ipynb` — first half)

### What it does
Finds the index of a target value in an unordered list of N = 2^n entries using
~√N Grover iterations instead of the classical O(N).

### Circuit structure (4 registers)

```
idx       — n index qubits      — measured at the end
val       — n_val value qubits  — loaded with classical data, then unloaded
anc       — n_val ancilla qubits — used by the NOT-XOR oracle, uncomputed
tgt_phase — 1 qubit             — prepared in |−⟩ for phase kickback
```

### Algorithm flow (one Grover iteration)
1. **Setup**: H on `idx`, X+H on `tgt_phase`
2. **encode_index_to_value**: loads df values into `val` register using MCX gates
3. **oracle**: compares `val` to target bit-by-bit → phase kickback via MCX on `anc` → `tgt_phase`; then uncomputes `anc`
4. **encode_index_to_value (reverse)**: unloads `val` register
5. **diffuser_on_a_register**: Grover diffuser on `idx` only

### Iteration count
```python
iterations = floor(π/4 · √(N / num_targets))
```

### Key bugs found and fixed

**`ctrl_state` endianness in `encode_index_to_value`:**
- `ctrl_state` is parsed by Qiskit as `int(string, 2)` — standard MSB-first binary.
- Passing `row["Index_Binary"]` directly is correct; reversing it swaps
  non-palindromic index pairs (e.g. 3↔6 for n=3).
- `value_bin_qiskit` still needs reversal because it iterates directly over qubit
  positions (little-endian register indexing).

**`diffuser_on_a_register` (user's original version was wrong):**
- Missing H wrap around MCX target: need `H → MCX → H` to implement MCZ
  (phase flip), not a bit flip.
- Wrong closing order: must be `X → H`, not `H → X`.

### Endianness reference

| Argument | Convention | Example for index 6 |
|---|---|---|
| `control_qubits` | list of qubit refs, index 0 = LSB | `[q0, q1, q2]` |
| `ctrl_state` | standard binary string, parsed via `int(s,2)` | `"110"` |

Same 3 bits, written in opposite directions in the same function call — this is a
known Qiskit API inconsistency.

### Running on real IBM hardware
```python
best_bin, counts = run_grover_circuit(
    n_idx, qr_index, qr_value, qr_ancilla, qr_target, cr_measure,
    df, target_bin, hw_backend=ibm_backend   # omit for AerSimulator
)
```
IBM credentials are saved from Chapter 2 (`QiskitRuntimeService.save_account`).
Available backends as of 2026-05: `ibm_kingston`, `ibm_marrakesh`, `ibm_fez`
(all 156 qubits).

**Why the real hardware gives uniform (wrong) results:**
The data-loading oracle requires O(N) MCX gates, each decomposing to ~20–30 CX
gates. At n=3 the transpiled circuit depth reaches hundreds of gates — beyond the
coherence time of current NISQ hardware. This is not an implementation bug; it is
a fundamental NISQ-era limitation. Grover for generic database search requires
QRAM, which does not exist in practical form today.

---

## Dürr-Høyer minimum search (`groove_algo.ipynb` — second half)

### What it does
Finds the minimum of a binary quadratic function g(x) = xᵀGx, x ∈ {0,1}^n,
without knowing the number of solutions in advance. Uses the BBHT
Exponential Random Scaling (ERS) strategy.

### Problem setup
- n variables total; x₀ = 1 always fixed → n-1 free variables, search space N = 2^(n-1)
- G is upper-triangular (generated with `generate_quadratic_problem`)
- K = max(|pos_sum|, |neg_sum|) → m qubits needed for two's complement encoding

### Circuit structure (4 registers)

```
x      — (n-1) qubits  — candidate in superposition, measured at end
y      — (n-1) qubits  — current best point (encoded classically via X gates)
scalar — m qubits       — QFT phase register for computing g(x)-g(y)
anc    — 1 qubit        — prepared in |−⟩, used for phase kickback (MSB of scalar)
```

### Oracle `apply_DH_oracle(qc, y_bitstring, g_matrix, m_qubits)`
1. Encode y classically into `y` register
2. H wall on `scalar` → phase basis
3. `g_comparator`: add g(x) - g(y) as phase rotations (P and MCP gates)
   - Controlled on `x` and `y` registers
   - Rotation angle at qubit k: `2π·coeff / 2^(m-k)` (Qiskit little-endian: k=0 is LSB)
4. Inverse QFT on `scalar` → computational basis (two's complement of g(x)-g(y))
5. CX(scalar[m-1], anc) — MSB = sign bit; flips anc iff g(x) < g(y)
6. Forward QFT + reverse comparator + H wall → restore `scalar` to |0⟩
7. Decode y (undo step 1)

### ERS loop in `GAS_solve_quadratic`
```python
while not_converged:
    j = randint(0, floor(m_RES) + 1)   # uniform in {0,...,floor(m)}
    # build fresh qc, apply j Grover iterations, measure x register
    if g(x_candidate) < g(y):
        y = x_candidate; m_RES = 1.0   # success: reset
    else:
        m_RES = min(λ · m_RES, sqrt(N))
        if m_RES >= sqrt(N): break      # cap reached → stop
```
- λ = 1.2 (= 6/5, optimal BBHT value)
- Fresh `QuantumCircuit` built every iteration (y and j both change)
- Bitstring from Qiskit is little-endian → reverse before passing to `compute_g_de_x`
- Classical register has `num_x_qubits` bits (measures `x`, not `scalar`)

### QFT import (Qiskit 2.1+)
`QFT` circuit class is deprecated. Use `QFTGate` instead:
```python
from qiskit.circuit.library import QFTGate
qc.append(QFTGate(m_qubits).inverse(), qr_scalar)  # inverse QFT
qc.append(QFTGate(m_qubits), qr_scalar)             # forward QFT
# QFTGate takes only num_qubits — no do_swaps or swaps argument
```

### Stochastic non-convergence
With small N and an unlucky y₀, the algorithm can exhaust its budget (m reaching
√N) without finding a better point. This is not a bug: with t solutions out of N,
P(failure per round) ≥ 3/4, so P(k consecutive failures) = (3/4)^k ≈ 5.6% for k=10.
Fix: restart with a new random y₀ when m hits √N (Dürr-Høyer recommend this).

### Output plots
Saved to `Code/plots/quadratic_landscape/quadratic_landscape_n{n}_seed{seed}.png`.
- n=3 (N=4): 3D scatter plot
- n≥4 (N≥8): 2D landscape with GAS path overlaid in red

---

## LaTeX circuits (`random_qc_circtuits.tex`)

Four circuits compiled with LuaLaTeX + quantikz2:

1. **NOT XOR gate** — definition and expansion into X/CNOT/Toffoli gates
2. **NOT XOR for 2-bit strings** — two NOT XOR blocks + Toffoli
3. **NOT XOR for n-bit strings** — same with `\vdots` and MCX
4. **Complete Grover iteration** — 4 registers (idx, val, tgt, anc), 5 stages
   inside a dashed `\gategroup` box

### quantikz2 rules to remember
- Multi-wire gates: `\gate[wires=n]{label}` (not `\gate[n]{label}`)
- Math in gate labels: `\ensuremath{...}` not `$...$` (LuaLaTeX is stricter)
- No trailing `&` at end of rows
- All rows in a circuit must have the same number of `&`-separated columns
- Upward control lines: `\ctrl{-k}` (negative offset)
- Multiline labels: `\shortstack{Line1\\Line2}`

---

## Environment

- Python 3.11.9 — kernel registered as "Python 3.11.9" via `ipykernel install --user --name python311`
- Qiskit 2.4.1 (Rust-based transpiler; first run builds cache, appears stuck — normal)
- qiskit-aer (separate package from Qiskit 1.0+)
- qiskit-ibm-runtime (`job.status()` returns a plain string, not an object with `.name`)
- LuaLaTeX (stricter than pdfLaTeX about `$...$` inside TikZ node arguments)
- Multiple Python versions installed (3.10, 3.11, 3.13) — always use the named kernel "Python 3.11.9"
