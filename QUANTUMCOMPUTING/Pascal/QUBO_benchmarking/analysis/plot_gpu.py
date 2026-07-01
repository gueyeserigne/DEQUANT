"""
Plot GPU usage from a gpu_monitor CSV file.
Supports multiple GPUs, each plotted in a different colour.

Usage:
    python my_experiments/plot_gpu.py --csv my_experiments/slurm_logs/gpu_*.csv
    python my_experiments/plot_gpu.py --csv my_experiments/slurm_logs/gpu_22064.csv
"""

import argparse
import glob
import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path

COLORS = ["steelblue", "darkorange", "seagreen", "crimson", "purple", "gold"]


def plot_gpu(csv_path: str):
    df = pd.read_csv(csv_path)

    # Support old single-GPU format (no gpu_id column)
    if "gpu_id" not in df.columns:
        df.insert(0, "gpu_id", 0)

    df["timestamp"] = pd.to_datetime(df["timestamp"])
    t0 = df["timestamp"].min()
    df["elapsed_min"] = (df["timestamp"] - t0).dt.total_seconds() / 60

    gpu_ids = sorted(df["gpu_id"].unique())
    n_gpus = len(gpu_ids)
    total_vram = df["memory_total_MiB"].iloc[0]

    fig, axes = plt.subplots(3, 1, figsize=(13, 9), sharex=True)
    fig.suptitle(f"GPU Usage — {Path(csv_path).stem}  ({n_gpus} GPU{'s' if n_gpus > 1 else ''})", fontsize=13)

    for i, gpu_id in enumerate(gpu_ids):
        g = df[df["gpu_id"] == gpu_id].copy()
        color = COLORS[i % len(COLORS)]
        label = f"GPU {gpu_id}"

        axes[0].plot(g["elapsed_min"], g["memory_used_MiB"],
                     color=color, linewidth=1.5, label=label)
        axes[1].plot(g["elapsed_min"], g["gpu_util_pct"],
                     color=color, linewidth=1.5, label=label)
        axes[2].plot(g["elapsed_min"], g["temp_C"],
                     color=color, linewidth=1.5, label=label)

    axes[0].axhline(total_vram, color="red", linestyle="--", linewidth=1,
                    label=f"Max VRAM ({total_vram} MiB)")
    axes[0].set_ylabel("VRAM used (MiB)")
    axes[0].set_ylim(0, total_vram * 1.05)
    axes[0].legend(fontsize=8)
    axes[0].grid(True, alpha=0.4)

    axes[1].set_ylabel("GPU util (%)")
    axes[1].set_ylim(0, 105)
    axes[1].legend(fontsize=8)
    axes[1].grid(True, alpha=0.4)

    axes[2].set_ylabel("Temp (°C)")
    axes[2].set_xlabel("Elapsed time (min)")
    axes[2].legend(fontsize=8)
    axes[2].grid(True, alpha=0.4)

    plt.tight_layout()

    out_path = Path(csv_path).with_suffix(".png")
    plt.savefig(out_path, dpi=150)
    plt.close()
    print(f"Saved → {out_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv", required=True, help="Path to gpu_monitor CSV (glob patterns ok)")
    args = parser.parse_args()

    files = glob.glob(args.csv)
    if not files:
        print(f"No files found: {args.csv}")
    for f in sorted(files):
        plot_gpu(f)
