"""
Post-processing: parse a benchmark_bqpgka.py Slurm .out log, extract each
"best bitstring" result, reload the matching QUBO, and compute the QUBO cost
z^T Q z. For instances small enough to brute-force (qubits <= --brute-force-max),
also finds the true optimum and reports the gap.

Runnable directly from joyeux (no container needed) — DATA_DIR points at the
real host path, not the /Quantum_workspace container mount alias.

Usage:
    python score_bitstrings_from_log.py --log ../slurm_logs/22201_bqpgka_qubit_sweep.out
    python score_bitstrings_from_log.py --log ... --brute-force-max 20
"""
import argparse
import re
from pathlib import Path

import numpy as np

DATA_DIR = Path(
    "/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/DATA/BQPGKA"
)

RESULT_RE = re.compile(
    r"\[(?P<tag>[\w]+)\] done\. best bitstring: (?P<bitstring>[01]+) \(count=(?P<count>\d+)\)"
)


def load_qubo(filepath: Path) -> np.ndarray:
    """Same loader as benchmark_bqpgka.py — kept in sync with it."""
    with open(filepath) as f:
        lines = [l.strip() for l in f if l.strip()]
    n, _ = map(int, lines[0].split())
    Q = np.zeros((n, n))
    for line in lines[1:]:
        i, j, v = map(int, line.split())
        i -= 1
        j -= 1
        Q[i, j] = -v
    Q = (Q + Q.T) / 2
    return Q


def cost(bitstring: str, Q: np.ndarray) -> float:
    z = np.array(list(bitstring), dtype=int)
    return float(z.T @ Q @ z)


def brute_force_optimum(Q: np.ndarray) -> tuple[str, float]:
    """Exact minimum of z^T Q z over all 2^n bitstrings. Only feasible for small n."""
    n = Q.shape[0]
    best_bitstring, best_cost = None, None
    for i in range(2 ** n):
        bitstring = np.binary_repr(i, n)
        z = np.array(list(bitstring), dtype=int)
        c = float(z.T @ Q @ z)
        if best_cost is None or c < best_cost:
            best_bitstring, best_cost = bitstring, c
    return best_bitstring, best_cost


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", required=True, help="Path to a benchmark_bqpgka.py .out log")
    parser.add_argument(
        "--brute-force-max",
        type=int,
        default=24,
        help="Only brute-force the true optimum for instances with at most this many "
             "qubits (2^n grows fast — default 24, ~16M combinations, a few seconds on CPU)",
    )
    args = parser.parse_args()

    log_text = Path(args.log).read_text()
    matches = list(RESULT_RE.finditer(log_text))
    if not matches:
        print(f"No 'best bitstring' results found in {args.log}")
        return

    print(f"{'tag':<28} {'bitstring':<25} {'count':>7} {'qubits':>7} {'cost':>14} {'optimum':>14} {'gap':>10}")
    print("-" * 115)
    for m in matches:
        tag, bitstring, count = m["tag"], m["bitstring"], int(m["count"])
        if "_truncated" in tag:
            print(f"{tag:<28} SKIPPED — synthetic truncated instance, no matching data file")
            continue
        qubo_file = DATA_DIR / f"{tag}.txt"
        if not qubo_file.exists():
            print(f"{tag:<28} SKIPPED — no data file at {qubo_file}")
            continue
        Q = load_qubo(qubo_file)
        if len(bitstring) != Q.shape[0]:
            print(f"{tag:<28} SKIPPED — bitstring length {len(bitstring)} != Q size {Q.shape[0]}")
            continue
        c = cost(bitstring, Q)

        if Q.shape[0] <= args.brute_force_max:
            _, optimum = brute_force_optimum(Q)
            gap = f"{c - optimum:+.4f}"
            optimum_str = f"{optimum:.4f}"
        else:
            optimum_str = f"skipped (>{args.brute_force_max}q)"
            gap = "n/a"

        print(f"{tag:<28} {bitstring:<25} {count:>7} {Q.shape[0]:>7} {c:>14.4f} {optimum_str:>14} {gap:>10}")


if __name__ == "__main__":
    main()
