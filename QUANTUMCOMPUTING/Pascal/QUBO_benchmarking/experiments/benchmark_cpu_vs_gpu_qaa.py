"""
CPU (QutipBackendV2) vs GPU (emu-sv SVBackend) timing comparison on the same
QAA-QUBO problem/pipeline as pascal_qaa_to_solve_a_qubo_problem.py.

Atom placement (the Nelder-Mead coordinate optimization) is computed once and
shared by both backends, since it's backend-independent — only the sequence
simulation itself is timed per-backend.
"""
import time
from pathlib import Path

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pulser
import pulser_simulation
from emu_sv import SVBackend, SVConfig
from pulser.backend import BitStrings
from scipy.optimize import minimize
from scipy.spatial.distance import pdist, squareform

OUTPUT_DIR = Path(__file__).resolve().parent / "outputs" / "cpu_vs_gpu_qaa"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

Q = np.array(
    [
        [-10.0, 19.7365809, 19.7365809, 5.42015853, 5.42015853],
        [19.7365809, -10.0, 20.67626392, 0.17675796, 0.85604541],
        [19.7365809, 20.67626392, -10.0, 0.85604541, 0.17675796],
        [5.42015853, 0.17675796, 0.85604541, -10.0, 0.32306662],
        [5.42015853, 0.85604541, 0.17675796, 0.32306662, -10.0],
    ]
)

device = pulser.DigitalAnalogDevice


def evaluate_mapping(new_coords: np.ndarray, Q: np.ndarray, device: pulser.devices.Device):
    """ Cost function to minimize """
    new_coords = np.reshape(new_coords, (len(Q), 2))
    new_Q = squareform(device.interaction_coeff / pdist(new_coords) ** 6)
    return np.linalg.norm(new_Q - Q)


timings = {}

# --- Shared: atom placement (backend-independent) ---
t0 = time.perf_counter()
np.random.seed(0)
x0 = np.random.random(len(Q) * 2)
res = minimize(
    evaluate_mapping,
    x0,
    args=(Q, device),
    method="Nelder-Mead",
    tol=1e-6,
    options={"maxiter": 200000, "maxfev": None},
)
coords = np.reshape(res.x, (len(Q), 2))
timings["atom_placement"] = time.perf_counter() - t0
print(f"[timing] atom placement (Nelder-Mead mapping): {timings['atom_placement']:.4f} s")

qubits = {f"q{i}": coord for (i, coord) in enumerate(coords)}
reg = pulser.Register(qubits)

# --- Shared: sequence construction (backend-independent) ---
t0 = time.perf_counter()
sequence = pulser.Sequence(reg, device)
sequence.declare_channel("rydberg_global", "rydberg_global")

Omega = np.median(Q[Q > 0].flatten())  # On ignore là où la matrice est nulle
delta_0 = -5  # just has to be negative
delta_f = -delta_0
T = 4000  # Assez de temps

adiabatic_pulse = pulser.Pulse(
    pulser.InterpolatedWaveform(T, [1e-9, Omega, 1e-9]),
    pulser.InterpolatedWaveform(T, [delta_0, 0, delta_f]),
    0,
)
sequence.add(adiabatic_pulse, "rydberg_global")
timings["sequence_build"] = time.perf_counter() - t0
print(f"[timing] sequence construction: {timings['sequence_build']:.4f} s")

# --- CPU backend: QutipBackendV2 ---
t0 = time.perf_counter()
simul_cpu = pulser_simulation.QutipBackendV2(sequence)
results_cpu = simul_cpu.run()
count_dict_cpu = results_cpu.final_bitstrings
timings["cpu_simulation"] = time.perf_counter() - t0
print(f"[timing] CPU (QutipBackendV2) simulation: {timings['cpu_simulation']:.4f} s")

# --- GPU backend: emu-sv SVBackend ---
t0 = time.perf_counter()
config = SVConfig(gpu=True, observables=[BitStrings()])
simul_gpu = SVBackend(sequence, config=config)
results_gpu = simul_gpu.run()
count_dict_gpu = results_gpu.final_bitstrings
timings["gpu_simulation"] = time.perf_counter() - t0
print(f"[timing] GPU (emu-sv SVBackend) simulation: {timings['gpu_simulation']:.4f} s")

speedup = timings["cpu_simulation"] / timings["gpu_simulation"]
print(f"[timing] GPU speedup over CPU: {speedup:.2f}x")

# --- Sanity check: do the two backends agree on the top bitstrings? ---
top_cpu = sorted(count_dict_cpu.items(), key=lambda kv: kv[1], reverse=True)[:3]
top_gpu = sorted(count_dict_gpu.items(), key=lambda kv: kv[1], reverse=True)[:3]
print(f"[check] CPU top-3 bitstrings: {top_cpu}")
print(f"[check] GPU top-3 bitstrings: {top_gpu}")

# --- Plot: side-by-side timing bar chart ---
plt.figure(figsize=(8, 5))
labels = ["atom_placement", "sequence_build", "cpu_simulation", "gpu_simulation"]
values = [timings[k] for k in labels]
colors = ["gray", "gray", "tab:blue", "tab:green"]
plt.bar(labels, values, color=colors)
plt.ylabel("time (s)")
plt.title(f"CPU vs GPU timing (GPU speedup: {speedup:.2f}x on simulation step)")
plt.xticks(rotation=20)
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "timing_comparison.png")
plt.close()

print(f"Timings: {timings}")
print(f"Outputs saved to {OUTPUT_DIR}")
