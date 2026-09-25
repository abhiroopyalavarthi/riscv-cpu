// muldiv.c - software multiply/divide.
// RV32I has no mul/div instructions, so GCC turns a * b into a call to
// __mulsi3, a / b into __divsi3, and so on. Normally these come from
// libgcc, but I don't link libgcc (the Homebrew toolchain may not ship an
// rv32i build of it), so here they are. Plain shift-and-add / shift-and-
// subtract, one bit per loop iteration.
//
// Careful: nothing in this file may use * / or %, or GCC would call the
// function from inside itself.
#include <stdint.h>

uint32_t __mulsi3(uint32_t a, uint32_t b)
{
    uint32_t r = 0;
    while (b) {
        if (b & 1)
            r += a;
        a <<= 1;
        b >>= 1;
    }
    return r;
}

// restoring division, returns quotient, remainder through *rem
static uint32_t udivmod(uint32_t n, uint32_t d, uint32_t *rem)
{
    if (d == 0) {                 // RISC-V spec: x/0 = all ones, x%0 = x
        *rem = n;
        return 0xFFFFFFFFu;
    }
    uint32_t q = 0, r = 0;
    for (int i = 31; i >= 0; i--) {
        r = (r << 1) | ((n >> i) & 1);
        if (r >= d) {
            r -= d;
            q |= 1u << i;
        }
    }
    *rem = r;
    return q;
}

uint32_t __udivsi3(uint32_t n, uint32_t d) { uint32_t r; return udivmod(n, d, &r); }
uint32_t __umodsi3(uint32_t n, uint32_t d) { uint32_t r; udivmod(n, d, &r); return r; }

int32_t __divsi3(int32_t n, int32_t d)
{
    uint32_t r;
    int neg = (n < 0) ^ (d < 0);
    uint32_t q = udivmod(n < 0 ? -(uint32_t)n : (uint32_t)n,
                         d < 0 ? -(uint32_t)d : (uint32_t)d, &r);
    if (d == 0)
        return -1;
    return neg ? -(int32_t)q : (int32_t)q;
}

int32_t __modsi3(int32_t n, int32_t d)
{
    uint32_t r;
    udivmod(n < 0 ? -(uint32_t)n : (uint32_t)n,
            d < 0 ? -(uint32_t)d : (uint32_t)d, &r);
    if (d == 0)
        return n;
    return n < 0 ? -(int32_t)r : (int32_t)r;
}
