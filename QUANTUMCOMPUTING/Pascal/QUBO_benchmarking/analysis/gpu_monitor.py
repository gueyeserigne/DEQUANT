"""
Polls GPU stats every N seconds and writes to a CSV.
Designed to run as a background process alongside training.

Usage (launched automatically by run_poc_1h.sh):
    python my_experiments/gpu_monitor.py --output execution_logs/gpu_run.csv --interval 5

Columns: timestamp, memory_used_MiB, memory_free_MiB, memory_total_MiB, gpu_util_pct, temp_C
"""

import argparse
import csv
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path


QUERY = "index,timestamp,memory.used,memory.free,memory.total,utilization.gpu,temperature.gpu"
HEADERS = ["gpu_id", "timestamp", "memory_used_MiB", "memory_free_MiB", "memory_total_MiB", "gpu_util_pct", "temp_C"]


def poll_gpus():
    """Returns one row per GPU."""
    result = subprocess.run(
        ["nvidia-smi", f"--query-gpu={QUERY}", "--format=csv,noheader,nounits"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        return []
    rows = []
    for line in result.stdout.strip().split("\n"):
        if line.strip():
            rows.append([v.strip() for v in line.split(",")])
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output",   required=True, help="Path to output CSV file")
    parser.add_argument("--interval", type=float, default=10.0, help="Polling interval in seconds")
    args = parser.parse_args()

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"[gpu_monitor] Logging to {out_path} every {args.interval}s — kill with Ctrl+C or SIGTERM")

    with open(out_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(HEADERS)
        f.flush()

        try:
            while True:
                rows = poll_gpus()
                for row in rows:
                    writer.writerow(row)
                if rows:
                    f.flush()
                time.sleep(args.interval)
        except (KeyboardInterrupt, SystemExit):
            print(f"[gpu_monitor] Stopped. {out_path}")
            sys.exit(0)


if __name__ == "__main__":
    main()
