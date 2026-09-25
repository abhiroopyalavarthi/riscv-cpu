#!/usr/bin/env bash
# Run every rv32ui test on one simulator build.
#   scripts/run_rv32ui.sh build/sim_pipe/Vsoc build/rv32ui [trace_dir]
# Prints PASS/FAIL per test and a total; exits nonzero if anything failed.
SIM=$1
HEXDIR=$2
TRACE_DIR=${3:-}       # optional: write a trace per test here

# ma_data tests misaligned loads/stores. RISC-V lets a core either handle
# them in hardware or trap; this core traps (stops with a "misaligned
# access" fault). So ma_data is expected to end in that fault, and anything
# else - passing, a wrong value, a timeout - counts as a failure.
EXPECT_FAULT="ma_data"

pass=0; fail=0; faulted=0; failed=()
for hex in "$HEXDIR"/*.hex; do
    t=$(basename "$hex" .hex)
    args=(+hex="$hex")
    [ -n "$TRACE_DIR" ] && args+=(+trace="$TRACE_DIR/$t.trace" +det-counters)
    out=$("$SIM" "${args[@]}" 2>&1 | tail -1)
    if [[ " $EXPECT_FAULT " == *" $t "* ]]; then
        if [[ $out == *"misaligned access"* ]]; then
            faulted=$((faulted + 1))
            printf "  %-10s trapped as expected: %s\n" "$t" "${out#FAIL: }"
        else
            fail=$((fail + 1)); failed+=("$t")
            printf "  %-10s expected a misaligned fault, got: %s   <-----\n" "$t" "$out"
        fi
    elif [[ $out == PASS* ]]; then
        pass=$((pass + 1))
        printf "  %-10s %s\n" "$t" "$out"
    else
        fail=$((fail + 1)); failed+=("$t")
        printf "  %-10s %s   <-----\n" "$t" "$out"
    fi
done

echo "rv32ui on $SIM: $pass passed, $fail failed, $faulted trapped as expected ($EXPECT_FAULT)"
[ $fail -eq 0 ] || { echo "failed: ${failed[*]}"; exit 1; }
