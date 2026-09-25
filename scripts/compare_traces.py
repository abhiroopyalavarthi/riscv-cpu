#!/usr/bin/env python3
"""Compare instruction traces from two CPU configs.

    compare_traces.py build/trace/single build/trace/pipe

Every trace in the first folder must have a twin in the second with exactly
the same lines: same PCs in the same order, same register writes, same
stores. The single-cycle core is the reference, so the first line that
differs is where the pipeline went wrong.
"""
import os
import sys


def main():
    ref_dir, dut_dir = sys.argv[1], sys.argv[2]
    names = sorted(f for f in os.listdir(ref_dir) if f.endswith(".trace"))
    bad = 0
    total_lines = 0
    for name in names:
        ref_path = os.path.join(ref_dir, name)
        dut_path = os.path.join(dut_dir, name)
        if not os.path.exists(dut_path):
            print(f"  {name}: missing in {dut_dir}")
            bad += 1
            continue
        ref = open(ref_path).read().splitlines()
        dut = open(dut_path).read().splitlines()
        total_lines += len(ref)
        for i in range(max(len(ref), len(dut))):
            r = ref[i] if i < len(ref) else "<end of trace>"
            d = dut[i] if i < len(dut) else "<end of trace>"
            if r != d:
                print(f"  {name}: first difference at instruction {i + 1}")
                print(f"    {os.path.basename(ref_dir):>8}: {r}")
                print(f"    {os.path.basename(dut_dir):>8}: {d}")
                bad += 1
                break

    label = f"{os.path.basename(dut_dir)} vs {os.path.basename(ref_dir)}"
    if bad:
        print(f"{label}: {bad} of {len(names)} traces differ")
        sys.exit(1)
    print(f"{label}: all {len(names)} traces identical ({total_lines} instructions)")


if __name__ == "__main__":
    main()
