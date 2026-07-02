"""
QAA (Quantum Adiabatic Algorithm) to solve a QUBO problem via Pulser.

Converted from pascal_QAA_to_solve_a_QUBO_problem.ipynb — minimal modifications:
plots are saved to outputs/ instead of shown interactively.
"""
import os
from pathlib import Path

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pulser
# import pulser_simulation # Old import : this uses the CPU
from scipy.optimize import minimize
from scipy.spatial.distance import pdist, squareform

#Imports pour le backend de simulation GPU
from emu_sv import SVBackend, SVConfig
from pulser.backend import BitStrings

# When launched by a Slurm script (run_qaa_qubo_test.sh), BENCHMARK_DAY/
# BENCHMARK_RUN_ID are exported so outputs land in the same DD-MM/NNN folder as
# the matching slurm_logs entry. Falls back to a flat outputs/qaa_qubo_problem/
# layout when run standalone (interactively, no Slurm).
_day = os.environ.get("BENCHMARK_DAY")
_run_id = os.environ.get("BENCHMARK_RUN_ID")
if _day and _run_id:
    OUTPUT_DIR = Path(__file__).resolve().parent / "outputs" / _day / _run_id / "qaa_qubo_problem"
else:
    OUTPUT_DIR = Path(__file__).resolve().parent / "outputs" / "qaa_qubo_problem"
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

print(len(Q))

bitstrings = [np.binary_repr(i, len(Q)) for i in range(2 ** len(Q))]
costs = []

for b in bitstrings:
    z = np.array(list(b), dtype=int)
    cost = z.T @ Q @ z
    costs.append(cost)
zipped = zip(bitstrings, costs)
sort_zipped = sorted(zipped, key=lambda x: x[1])
print(sort_zipped[:3])

device = pulser.DigitalAnalogDevice
device.print_specs()


def evaluate_mapping(
        new_coords: np.ndarray, Q: np.ndarray, device: pulser.devices.Device
):
    """ Cost function to minimize """
    new_coords = np.reshape(new_coords, (len(Q), 2))
    new_Q = squareform(device.interaction_coeff / pdist(new_coords) ** 6)
    return np.linalg.norm(new_Q - Q)


costs = []
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

qubits = {f"q{i}": coord for (i, coord) in enumerate(coords)}
reg = pulser.Register(qubits)
reg.draw(
    blockade_radius=device.rydberg_blockade_radius(1.0),
    draw_graph=False,
    draw_half_radius=True,
    fig_name=str(OUTPUT_DIR / "register.png"),
    show=False,
)

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
sequence.draw(fig_name=str(OUTPUT_DIR / "sequence.png"), show=False)

# Old Code - CPU backend
# simul = pulser_simulation.QutipBackendV2(sequence)
# results = simul.run()
# count_dict = results.final_bitstrings

# New Code - GPU backend
config = SVConfig(gpu=True, observables=[BitStrings()])
simul = SVBackend(sequence, config=config)
results = simul.run()
count_dict = results.final_bitstrings

count_dict = dict(
    sorted(count_dict.items(), key=lambda item: item[1], reverse=True)
)

indexes = ["01011", "00111"]  # QUBO solution
color_dict = {key: "r" if key in indexes else "g" for key in count_dict}

plt.figure(figsize=(12, 6))
plt.xlabel("bitstrings")
plt.ylabel("counts")
plt.bar(
    count_dict.keys(),
    count_dict.values(),
    width=0.5,
    color=color_dict.values(),
)
plt.xticks(rotation="vertical")
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "distribution.png")
plt.close()

# The bitstrings 01011 and 00111 (in red) correspond to the two optimal solutions
# (calculated at the beginning of the notebook). See how fast and performant this
# method is! In only a few micro-seconds, we find an excellent solution.


# How does the time evolution affect the quality of the results?
def get_cost_colouring(bitstring, Q):
    z = np.array(list(bitstring), dtype=int)
    cost = z.T @ Q @ z
    return cost


def get_cost(counter, Q):
    cost = sum(counter[key] * get_cost_colouring(key, Q) for key in counter)
    return cost / sum(counter.values())


cost = []
for T in 1000 * np.linspace(1, 10, 10):
    seq = pulser.Sequence(reg, pulser.DigitalAnalogDevice)
    seq.declare_channel("ising", "rydberg_global")
    adiabatic_pulse = pulser.Pulse(
        pulser.InterpolatedWaveform(T, [1e-9, Omega, 1e-9]),
        pulser.InterpolatedWaveform(T, [delta_0, 0, delta_f]),
        0
    )
    seq.add(adiabatic_pulse, "ising")

    # CPU backend
    # simul = pulser_simulation.QutipBackendV2(seq)
    # results = simul.run()
    
    #GPU backend
    config = SVConfig(gpu=True, observables=[BitStrings()])
    simul = SVBackend(seq, config=config)
    results = simul.run()
    
    count_dict = results.final_bitstrings
    cost.append(get_cost(count_dict, Q) / 3)  # Pq / 3 ici : Juste pour ramené le min à -9 plutôt que -27 ? ...

plt.figure(figsize=(12, 6))
plt.plot(range(1, 11), np.array(cost), "--o")
plt.xlabel("total time evolution (µs)", fontsize=14)
plt.ylabel("cost", fontsize=14)
plt.savefig(OUTPUT_DIR / "cost_vs_time.png")
plt.close()

# We see why this approach is called "Adiabatic": the quality of the solution
# increases (the cost decreases) if the time taken for the evolution is longer.

print(f"Outputs saved to {OUTPUT_DIR}")
