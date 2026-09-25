#!/usr/bin/env bash
# Run every rv32ui test on one simulator build.
#   scripts/run_rv32ui.sh build/sim_pipe/Vsoc build/rv32ui
# Prints PASS/FAIL per test and a total; exits nonzero if anything failed.
SIM=$1
HEXDIR=$2
TRACE_DIR=${3:-}       # optional: write a trace per test here

# ma_data needs misaligned-access traps (CSRs), which this core doesn't have.
SKIP="ma_data"

pass=0; fail=0; failed=()
for hex in "$HEXDIR"/*.hex; do
    t=$(basename "$hex" .hex)
    if [[ " $SKIP " == *" $t "* ]]; then
        printf "  %-10s SKIP\n" "$t"
        continue
    fi
    args=(+hex="$hex")
    [ -n "$TRACE_DIR" ] && args+=(+trace="$TRACE_DIR/$t.trace" +det-counters)
    out=$("$SIM" "${args[@]}" 2>&1 | tail -1)
    if [[ $out == PASS* ]]; then
        pass=$((pass + 1))
        printf "  %-10s %s\n" "$t" "$out"
    else
        fail=$((fail + 1)); failed+=("$t")
        printf "  %-10s %s   <-----\n" "$t" "$out"
    fi
done

echo "rv32ui on $SIM: $pass passed, $fail failed, skipped: $SKIP"
[ $fail -eq 0 ] || { echo "failed: ${failed[*]}"; exit 1; }
