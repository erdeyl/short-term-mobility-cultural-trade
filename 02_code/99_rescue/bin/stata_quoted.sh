#!/bin/bash
# stata_quoted.sh -- Stata launcher shim for macOS and Linux (set by run_all.py as STATA_EXE for the chapter build).
# The chapter runners start Stata with an argument list:  <exe> -b do <dofile> [arg ...]
# (02_code/03_Mobility/chapter_runtime.py, stata_command; 02_code/03_Mobility/02_empirical_analysis/01_core/run_core.py).
# Stata for macOS/Unix rebuilds its command line by joining the arguments with spaces, so a path that contains a space
# is cut at the space. On Windows, Python's subprocess puts double quotes around every argument with a space.
# This shim does the same: every argument after the first literal "do" that contains a space or a tab, or is empty,
# is wrapped in double quotes; "-q" is added after "-b" (no licence banner in the batch logs); then the real Stata
# executable named in STATA_REAL_EXE is executed and its exit code is returned unchanged.
set -u
REAL="${STATA_REAL_EXE:-}"
if [ -z "$REAL" ] || [ ! -x "$REAL" ]; then
  echo "stata_quoted.sh: STATA_REAL_EXE is not set to an executable Stata (run_all.py sets it)" >&2
  exit 97
fi
out=()
after_do=0
for a in "$@"; do
  if [ "$after_do" -eq 1 ] && { [ -z "$a" ] || [[ "$a" == *[$' \t']* ]]; }; then
    case "$a" in
      *\"*) echo "stata_quoted.sh: argument contains a double quote; refusing: $a" >&2; exit 98 ;;
    esac
    out+=("\"$a\"")
  else
    out+=("$a")
  fi
  if [ "$after_do" -eq 0 ] && [ "$a" = "-b" ]; then out+=("-q"); fi
  if [ "$after_do" -eq 0 ] && [ "$a" = "do" ]; then after_do=1; fi
done
exec "$REAL" "${out[@]}"
