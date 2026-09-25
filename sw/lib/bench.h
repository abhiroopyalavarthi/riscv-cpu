// bench.h - read every performance counter before and after a kernel and
// print the difference as one "key=value" line that scripts/bench.py parses.
#ifndef BENCH_H
#define BENCH_H

#include "io.h"

typedef struct {
    uint32_t cycles, instret, ctrl, redirect, ic_acc, ic_miss, dc_acc, dc_miss;
} perf_t;

static inline void perf_read(perf_t *p)
{
    p->cycles   = MMIO(PERF_CYCLES);
    p->instret  = MMIO(PERF_INSTRET);
    p->ctrl     = MMIO(PERF_CTRL);
    p->redirect = MMIO(PERF_REDIR);
    p->ic_acc   = MMIO(PERF_IC_ACC);
    p->ic_miss  = MMIO(PERF_IC_MISS);
    p->dc_acc   = MMIO(PERF_DC_ACC);
    p->dc_miss  = MMIO(PERF_DC_MISS);
}

static void kv(const char *key, uint32_t v)
{
    putchar_(' ');
    puts_(key);
    putchar_('=');
    print_udec(v);
}

static void perf_report(const char *name, const perf_t *a, const perf_t *b)
{
    puts_("bench: ");
    puts_(name);
    kv("cycles",   b->cycles   - a->cycles);
    kv("instret",  b->instret  - a->instret);
    kv("ctrl",     b->ctrl     - a->ctrl);
    kv("redirect", b->redirect - a->redirect);
    kv("ic_acc",   b->ic_acc   - a->ic_acc);
    kv("ic_miss",  b->ic_miss  - a->ic_miss);
    kv("dc_acc",   b->dc_acc   - a->dc_acc);
    kv("dc_miss",  b->dc_miss  - a->dc_miss);
    putchar_('\n');
}

// small deterministic pseudo-random generator (same numbers on every run)
static uint32_t lcg_state = 12345;
static inline uint32_t lcg(void)
{
    lcg_state = lcg_state * 1103515245u + 12345u;   // becomes __mulsi3
    return lcg_state >> 8;
}

#endif
