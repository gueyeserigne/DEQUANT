"""
QUBO benchmarking on BQPGKA instances via Pulser (Rydberg atom adiabatic pulse).

Converted from scratch/pascal_qubo_benchmarking_BQPGKA.ipynb — same pipeline:
load a BQPGKA instance -> QUBO matrix -> optimize atom coordinates to match
the interaction matrix -> build a detuning-mapped adiabatic sequence ->
simulate -> save the final bitstring distribution.

Usage:
    python benchmark_bqpgka.py --files bqpgka20_1.txt
    python benchmark_bqpgka.py --files bqpgka20_1.txt bqpgka30_1.txt bqpgka50_1.txt
"""
import argparse
import os
import time
from pathlib import Path

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pulser
from emu_sv import SVBackend, SVConfig
from pulser.backend import BitStrings
from scipy.optimize import minimize
from scipy.spatial.distance import pdist, squareform, euclidean

DATA_DIR = Path("/Quantum_workspace/DATA/BQPGKA")

# When launched by a Slurm script (run_bqpgka_benchmark.sh etc.), BENCHMARK_DAY/
# BENCHMARK_RUN_ID are exported so outputs land in the same DD-MM/NNN folder as
# the matching slurm_logs entry. Falls back to a flat outputs/<tag>/ layout when
# run standalone (interactively, no Slurm).
_day = os.environ.get("BENCHMARK_DAY")
_run_id = os.environ.get("BENCHMARK_RUN_ID")
if _day and _run_id:
    OUTPUT_DIR = Path(__file__).resolve().parent / "outputs" / _day / _run_id
else:
    OUTPUT_DIR = Path(__file__).resolve().parent / "outputs"


def load_qubo(filepath: Path) -> np.ndarray:
    """
    Load a BQPGKA file and return Q in standard QUBO form (diag < 0, off-diag > 0).

    The file stores an upper-triangular matrix with negated values.
    The symmetric QUBO matrix is recovered as Q_sym = (Q_upper + Q_upper.T) / 2,
    which halves the off-diagonal entries — consistent with x^T Q x where Q is symmetric.
    """
    with open(filepath) as f:
        lines = [l.strip() for l in f if l.strip()]
    n, _ = map(int, lines[0].split())
    Q = np.zeros((n, n))
    for line in lines[1:]:
        i, j, v = map(int, line.split())
        i -= 1  # 1-indexed -> 0-indexed
        j -= 1
        if i == j:
            Q[i, j] = v  # diag stored as-is
        else :
            Q[j, i] = Q[i, j] = v  # negate stored values
    
    # Vieu code
    #Q = (Q + Q.T) / 2  # symmetrise upper triangle -> full symmetric QUBO
    
    return Q


def evaluate_mapping(new_coords: np.ndarray, Q: np.ndarray, device: pulser.devices.Device) -> float:
    """Cost function to minimize: distance between target Q and Q induced by atom placement.

    Facteur de normalisation /4 : Compense le fait que la matrice Q théorique utilise
    des couplages unitaires (1). Diviser par 4 tasse globalement l'échelle d'énergie,
    ce qui force l'optimiseur à rapprocher les atomes (~10.5 µm au lieu de ~13.2 µm).
    Grâce à la loi en 1/R^6, ce léger rapprochement multiplie par 4 la force réelle
    des interactions physiques, améliorant la robustesse au bruit de la machine.
    """
    new_coords = np.reshape(new_coords, (len(Q), 2))
    new_Q = squareform(device.interaction_coeff / pdist(new_coords) ** 6) / 4
    return np.linalg.norm(new_Q - Q)


def plot_distribution(counts: dict, save_path: Path):
    counts = dict(sorted(counts.items(), key=lambda item: item[1], reverse=True))
    plt.figure(figsize=(12, 6))
    plt.xlabel("bitstrings")
    plt.ylabel("counts")
    plt.bar(counts.keys(), counts.values(), width=0.5, color="g")
    plt.xticks(rotation="vertical")
    plt.tight_layout()
    plt.savefig(save_path)
    plt.close()


def run_instance(filename: str, truncate: int | None = None):
    filepath = DATA_DIR / filename
    tag = filepath.stem
    if truncate is not None:
        tag = f"{tag}_truncated{truncate}"
    out_dir = OUTPUT_DIR / tag
    out_dir.mkdir(parents=True, exist_ok=True)

    timings = {}

    print(f"[{tag}] loading QUBO from {filepath}")
    Q = load_qubo(filepath)
    if truncate is not None:
        print(f"[{tag}] truncating {Q.shape[0]}x{Q.shape[0]} QUBO to top-left {truncate}x{truncate} submatrix"
              " (synthetic sub-problem for timing purposes only, not a real benchmark instance)")
        Q = Q[:truncate, :truncate]

    device = pulser.MockDevice

    print(f"[{tag}] optimizing atom coordinates to match Q ({Q.shape[0]} atoms)")
    t0 = time.perf_counter()
    np.random.seed(0)
    x0 = np.random.random(len(Q) * 2)
    res = minimize(
        evaluate_mapping,
        x0,
        args=(~np.eye(Q.shape[0], dtype=bool) * Q, device),
        method="Nelder-Mead",
        tol=1e-6,
        options={"maxiter": 200000, "maxfev": None},
    )
    coords = np.reshape(res.x, (len(Q), 2))
    timings["atom_placement"] = time.perf_counter() - t0
    print(f"[{tag}] mapping cost: {res.fun:.4f}")
    print(f"[{tag}] timing: atom placement took {timings['atom_placement']:.4f} s")

    qubits = {f"q{i}": coord for (i, coord) in enumerate(coords)}
    reg = pulser.Register(qubits)
    reg.draw(
        blockade_radius=device.rydberg_blockade_radius(1.0),
        draw_graph=True,
        draw_half_radius=True,
        fig_name=str(out_dir / "register.png"),
        show=False,
    )

    sequence = pulser.Sequence(reg, device)
    sequence.declare_channel("rydberg_global", "rydberg_global")

    # Applciation du det map pour le QUBO
    # Ici je veux favoriser l'activation des atomes dont le coeff diag est le plut petit
    node_weights = np.diag(Q)
    a = np.min(node_weights)
    b = np.max(node_weights)
    alpha = 0.8  # facteur de sécurité pour s'assurer que le Delta tot à la fin de la séquence soit > 0 pour tous les atomes

    if b - a != 0:
        det_map_weights = alpha * (node_weights - a) / (b - a)
    else:
        det_map_weights = np.zeros_like(node_weights)

    det_map = reg.define_detuning_map(
        {f"q{i}": det_map_weights[i] for i in range(len(det_map_weights))}
    )
    det_map.draw(labels=reg.qubit_ids, fig_name=str(out_dir / "detuning_map.png"), show=False)

    sequence.config_detuning_map(det_map, "dmm_0")

    distances = []
    for i in range(1, Q.shape[0]):
        for j in range(i - 1):
            distances.append(euclidean(reg.qubits[f"q{i}"], reg.qubits[f"q{j}"]))

    Omega = device.interaction_coeff / np.min(distances) ** 6
    delta_0 = -Omega  # Just need a <0 real
    delta_f = -delta_0  # Just needs to be >0 real
    T = 40000  # Time in ns: long enough to ensure information propagation (<=> adiabatic)

    print(f"[{tag}] Omega={Omega:.4f} delta_0={delta_0:.4f} delta_f={delta_f:.4f}")

    adiabatic_pulse = pulser.Pulse(
        pulser.InterpolatedWaveform(T, [1e-9, Omega, 1e-9]),
        pulser.InterpolatedWaveform(T, [delta_0, 0, delta_f]),
        0,
    )
    sequence.add(adiabatic_pulse, "rydberg_global")
    sequence.add_dmm_detuning(pulser.ConstantWaveform(T, -delta_f), "dmm_0")

    sequence.draw(
        draw_detuning_maps=True,
        draw_qubit_det=True,
        draw_qubit_amp=True,
        fig_name=str(out_dir / "sequence.png"),
        show=False,
    )

    print(f"[{tag}] running simulation on GPU ({Q.shape[0]} qubits)")
    t0 = time.perf_counter()
    config = SVConfig(gpu=True, observables=[BitStrings()])
    simul = SVBackend(sequence, config=config)
    results = simul.run()
    count_dict = results.final_bitstrings
    timings["gpu_simulation"] = time.perf_counter() - t0
    print(f"[{tag}] timing: GPU simulation took {timings['gpu_simulation']:.4f} s")

    plot_distribution(count_dict, out_dir / "distribution.png")

    best_bitstring = max(count_dict, key=count_dict.get)
    print(f"[{tag}] done. best bitstring: {best_bitstring} (count={count_dict[best_bitstring]})")
    print(f"[{tag}] timings: {timings}")
    print(f"[{tag}] outputs saved to {out_dir}")
    return timings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--files",
        nargs="+",
        default=["bqpgka20_1.txt"],
        help="BQPGKA filenames (relative to DATA_DIR) to benchmark, e.g. --files bqpgka20_1.txt bqpgka30_1.txt",
    )
    parser.add_argument(
        "--qubit-sweep",
        nargs="+",
        type=int,
        default=None,
        help="Run --files[0] truncated to each of these qubit counts, to get a GPU timing "
             "curve (e.g. --qubit-sweep 10 15 20). Truncated runs use a synthetic top-left "
             "submatrix of the real QUBO — for timing only, not a real benchmark result.",
    )
    parser.add_argument(
        "--full",
        action="store_true",
        help="Run all --files at their real, untruncated size (the actual benchmark). "
             "Bypasses --qubit-sweep — use this once you already know timing is fine "
             "and just want the real result.",
    )
    args = parser.parse_args()

    if args.full:
        for filename in args.files:
            run_instance(filename)
    elif args.qubit_sweep:
        base_file = args.files[0]
        full_n = load_qubo(DATA_DIR / base_file).shape[0]
        all_timings = {}
        for n in args.qubit_sweep:
            truncate = None if n >= full_n else n
            timings = run_instance(base_file, truncate=truncate)
            all_timings[n] = timings
        print("=== qubit sweep summary ===")
        for n, timings in all_timings.items():
            print(f"  {n:>4} qubits: {timings}")
    else:
        for filename in args.files:
            run_instance(filename)


if __name__ == "__main__":
    main()
