#!/usr/bin/env bash
# Run programs on one CPU config, keep a trace of each, stop at the first failure.
#   scripts/run_progs.sh pipe build/sw/sum.hex build/sw/fib.hex ...
cfg=$1; shift
mkdir -p build/trace/$cfg
for h in "$@"; do
    n=$(basename "$h" .hex)
    printf "  %-7s %-8s " "$cfg" "$n"
    out=$(build/sim_$cfg/Vsoc +hex="$h" +trace=build/trace/$cfg/$n.trace +det-counters | tail -1)
    echo "$out"
    case "$out" in PASS*) ;; *) exit 1 ;; esac
done
