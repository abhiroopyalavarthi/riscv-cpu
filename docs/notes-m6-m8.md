# Milestones 6–8: performance counters, branch predictor, caches

Full tables: `docs/results.md` (regenerate with `make bench`).

## M6: performance baseline

### Counters (memory-mapped, read with `lw`)

| Address | Counter |
|---|---|
| `0x1000_0004` | cycles |
| `0x1000_000C` | instructions retired (WB of a valid instruction) |
| `0x1000_0010` | branches + jumps executed |
| `0x1000_0014` | redirects: flushes because the fetched path was wrong |
| `0x1000_0018 / 1C` | I-cache accesses / misses |
| `0x1000_0020 / 24` | D-cache reads / misses |

The counters are in `soc.sv`; the cores only output one-cycle event pulses (`retire`, `ctrl_exec`, `ctrl_redirect`). They only count while the pipeline advances, so a cache stall doesn't count the same instruction 10 times.

### Benchmarks (`sw/c/`)

| Benchmark | What it does | Why it's interesting | Self-check |
|---|---|---|---|
| `sort` | insertion sort, 256 ints | data-dependent branches | sorted + sum unchanged |
| `matmul` | 16×16 int multiply | every `*` is a call to software `__mulsi3`: tons of short loops | C·1 = A·(B·1) (row sums, different order of operations) |
| `crc32` | table CRC-32 over 4 KB | streams through 5 KB of data (buffer + table) | known answer for "123456789" (0xCBF43926); I also checked the 4 KB result against Python's `zlib.crc32` |

Each benchmark reads all counters before and after the kernel only, and prints one `bench: name key=value ...` line. `scripts/bench.py` runs every benchmark on every config and writes the tables.

### Result: single-cycle vs pipeline

| Config | sort | matmul | crc32 |
|---|---|---|---|
| single-cycle | 1.000 | 1.000 | 1.000 |
| pipeline, predict not-taken | 1.335 | 1.390 | 1.300 |

The pipeline has *higher* CPI, but that's not the whole story. The single-cycle clock has to fit fetch + decode + ALU + memory + writeback in one period. The pipeline's clock only has to fit the slowest stage, roughly 3–5× faster in a real implementation. So even at CPI 1.3 it's much faster in wall-clock time. I don't synthesize, so I report CPI and state that assumption instead of claiming MHz.

Where the extra 0.3–0.4 CPI comes from: **taken branches** (2 cycles each, e.g. sort has 15,767 of them in 94k instructions) plus **load-use stalls** (1 cycle each). That's what M7 goes after.

## M7: branch predictor

`BP=1` in `core_pipe.sv`: a 64-entry **BTB** (branch target buffer) with a **2-bit saturating counter** per entry.

- **IF:** index the BTB with PC[7:2] and compare the tag (PC[31:8]). On a hit with counter ≥ 2 (weakly/strongly taken), fetch from the stored target next; otherwise fetch PC+4. The guess (`pred_next`) travels down the pipeline with the instruction.
- **EX:** compute the real next PC. If it differs from `pred_next`, redirect (same flush as before). Train the entry: counter +1 if taken, −1 if not; update the target.
- **Allocate only on taken.** A branch that's never taken predicts fine without an entry, so it doesn't evict anything.
- **JAL and JALR use the same BTB.** JAL always hits once trained. JALR (function return) is predicted with the last target seen. That's wrong when a function is called from different places, and it's why matmul (which calls `__mulsi3` from several spots) has the lowest accuracy. A return address stack would fix it; that's the obvious next step.

Correctness doesn't depend on the predictor. EX always checks the actual next PC, so a bad prediction only costs cycles. I checked this: when I broke the target check, fib and hello failed.

| Benchmark | branches+jumps | redirects, no BP | redirects, BP | accuracy | CPI no BP → BP |
|---|---|---|---|---|---|
| sort | 31,270 | 15,767 | 267 | 99.1% | 1.335 → 1.006 |
| matmul | 174,898 | 99,409 | 18,892 | 89.2% | 1.390 → 1.074 |
| crc32 | 4,100 | 4,099 | 5 | 99.9% | 1.300 → 1.100 |

matmul's 89% comes from the `if (b & 1)` inside the software multiply: the bits of random numbers are close to a coin flip, and no 2-bit counter can predict that. crc32 is left at CPI 1.10 because of load-use stalls (`table[...]` is used right after it's loaded), not branches.

## M8: caches

`rtl/cache.sv`, one module instantiated twice (I-cache and D-cache).

- Direct-mapped, 16-byte lines, size and miss penalty are parameters.
- Read miss: `ready` goes low, the whole pipeline freezes for `MISS_PENALTY` (10) cycles, then the line is filled from RAM and the access hits.
- Write-through, no write-allocate: every store goes to RAM, and if the line is cached it's updated too. Stores never stall. That's the simplest policy that's always correct (no dirty lines, no write-back).
- I/O addresses (0x1000_xxxx) bypass the D-cache: you don't want the UART or the cycle counter cached.
- FENCE.I invalidates the whole I-cache, which is what makes the `fence_i` test (self-modifying code) pass with caches on.

### Results (BP on, 10-cycle miss penalty)

| Config | CPI sort | CPI matmul | CPI crc32 | D$ hit sort | D$ hit matmul | D$ hit crc32 |
|---|---|---|---|---|---|---|
| no cache (1-cycle RAM) | 1.006 | 1.074 | 1.100 | - | - | - |
| 256 B | 1.275 | 1.166 | 2.003 | 84.0% | 43.4% | 54.9% |
| 1 KB | 1.014 | 1.088 | 1.268 | 99.6% | 91.5% | 91.7% |
| 4 KB | 1.014 | 1.077 | 1.200 | 99.6% | 98.4% | 95.1% |

How to read it:
- "No cache" isn't a real option. It assumes single-cycle RAM, which is the ideal the caches try to get close to. With a 10-cycle memory and *no* cache, every access would pay 10 cycles.
- **sort** touches 1 KB of data, so 1 KB is enough and 4 KB adds nothing.
- **matmul** walks B by column (stride 64 bytes). At 256 B the rows of A, B and C keep evicting each other (43% hit rate).
- **crc32** streams 4 KB once, so even an infinite cache misses once per 16-byte line (1 in 16 byte loads). At 4 KB the buffer also conflicts with the lookup table in a direct-mapped cache, which is why it tops out at 95%. A 2-way cache would help here.
- The I-cache hit rate is ~100% in all cases. The kernels are small loops, and the only misses are the first pass.

## Interview questions

- *Why does the pipeline have higher CPI than single-cycle? Isn't that worse?* CPI isn't performance. Time = instructions × CPI × clock period, and pipelining cuts the period a lot more than it raises CPI.
- *Explain the 2-bit counter.* The states are 00/01 predict not-taken and 10/11 predict taken. It takes two wrong guesses in a row to flip the prediction, so a loop branch mispredicts only once at the exit, not twice (exit plus re-entry) like a 1-bit scheme would.
- *Why is matmul's accuracy low?* Most of its branches are inside the software multiply and depend on random data bits. And JALR returns from `__mulsi3` go back to different call sites. A return address stack would fix that part.
- *Write-through vs write-back?* Write-through is simpler: no dirty bits, and RAM is always up to date. The cost is memory traffic on every store; I don't model write bandwidth, so it's free here. Write-back is what you'd do with a real slow memory.
- *Why does a miss stall the whole pipeline?* It's simple and always correct. A non-blocking cache (hit under miss) would let other instructions continue but needs a lot more logic.
