#!/bin/bash
# Reads a plain-text list of BQPGKA instance filenames (one per line, '#'
# comments allowed) and submits one run_bqpgka_benchmark.sh job per file via
# sbatch_sequential.sh, so the whole batch runs sequentially without racing
# for NNN log IDs.
#
# Usage:
#   bash sbatch_from_filelist.sh instances.txt                       # each job gets its own NNN
#   bash sbatch_from_filelist.sh --group instances.txt                # all jobs share one NNN
#   bash sbatch_from_filelist.sh --group instances.txt -m "full sweep"  # + shared note
#
# instances.txt example:
#   bqpgka20_1.txt
#   bqpgka30_1.txt
#   # bqpgka40_1.txt   <- commented out, skipped
#   bqpgka50_1.txt

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

GROUP_FLAG=""
NOTE_ARG=""
FILELIST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --group)
      GROUP_FLAG="--group"
      shift
      ;;
    -m)
      NOTE_ARG=" -m '$2'"
      shift 2
      ;;
    *)
      FILELIST="$1"
      shift
      ;;
  esac
done

if [ -z "$FILELIST" ] || [ ! -f "$FILELIST" ]; then
  echo "ERROR: pass a valid file list path, e.g. bash sbatch_from_filelist.sh instances.txt" >&2
  exit 1
fi

CMDS=()
first=1
while IFS= read -r line; do
  line="$(echo "$line" | sed 's/#.*//' | xargs)"   # strip comments, trim whitespace
  [ -z "$line" ] && continue
  if [ "$GROUP_FLAG" = "--group" ]; then
    # Shared folder: only the first job needs -m, run_bqpgka_benchmark.sh
    # dedups the write so later jobs don't need it re-passed.
    if [ "$first" = "1" ]; then
      CMDS+=("sbatch $SCRIPT_DIR/run_bqpgka_benchmark.sh --full $line$NOTE_ARG")
      first=0
    else
      CMDS+=("sbatch $SCRIPT_DIR/run_bqpgka_benchmark.sh --full $line")
    fi
  else
    # Separate folders: every job needs its own copy of the note to see it.
    CMDS+=("sbatch $SCRIPT_DIR/run_bqpgka_benchmark.sh --full $line$NOTE_ARG")
  fi
done < "$FILELIST"

if [ "${#CMDS[@]}" -eq 0 ]; then
  echo "ERROR: no filenames found in $FILELIST" >&2
  exit 1
fi

echo "=== Submitting ${#CMDS[@]} job(s) from $FILELIST ==="
bash "$SCRIPT_DIR/sbatch_sequential.sh" $GROUP_FLAG "${CMDS[@]}"
