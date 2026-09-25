// io.h - memory-mapped I/O and the tiny print library.
#ifndef IO_H
#define IO_H

#include <stdint.h>

#define MMIO(addr) (*(volatile uint32_t *)(addr))

#define UART_TX      0x10000000
#define PERF_CYCLES  0x10000004
#define PERF_INSTRET 0x1000000C
#define PERF_CTRL    0x10000010   // branches + jumps executed
#define PERF_REDIR   0x10000014   // control-flow redirects (mispredicts / taken with no predictor)
#define PERF_IC_ACC  0x10000018
#define PERF_IC_MISS 0x1000001C
#define PERF_DC_ACC  0x10000020
#define PERF_DC_MISS 0x10000024

static inline uint32_t read_cycles(void)  { return MMIO(PERF_CYCLES); }
static inline uint32_t read_instret(void) { return MMIO(PERF_INSTRET); }

void putchar_(char c);
void puts_(const char *s);          // no newline added
void print_hex(uint32_t v);         // 8 hex digits
void print_udec(uint32_t v);
void print_dec(int32_t v);

#endif
