import numpy as np
from pathlib import Path

DATA_DIR = Path("/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/DATA/BQPGKA")

def load_qubo(filepath):
    with open(filepath) as f:
        lines = [l.strip() for l in f if l.strip()]
    n, _ = map(int, lines[0].split())
    Q = np.zeros((n, n))
    for line in lines[1:]:
        i, j, v = map(int, line.split())
        i -= 1; j -= 1
        Q[i, j] = -v
    Q = (Q + Q.T) / 2
    return Q

Q = load_qubo(DATA_DIR / "bqpgka20_1.txt")
n = Q.shape[0]

def cost(bitstring):
    z = np.array(list(bitstring), dtype=int)
    return float(z.T @ Q @ z)

zeros = "0"*n
ones = "1"*n
gpu_result = "10111100111111101101"

print("all-zeros:", cost(zeros))
print("all-ones :", cost(ones))
print("GPU found:", cost(gpu_result), gpu_result, len(gpu_result))

best_bs, best_c = None, None
worst_bs, worst_c = None, None
for i in range(2**n):
    bs = np.binary_repr(i, n)
    c = cost(bs)
    if best_c is None or c < best_c:
        best_bs, best_c = bs, c
    if worst_c is None or c > worst_c:
        worst_bs, worst_c = bs, c

print("TRUE OPTIMUM (min):", best_c, best_bs)
print("TRUE WORST   (max):", worst_c, worst_bs)
