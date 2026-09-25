// print.c - enough printing to get numbers out of the CPU.
// No printf: it would pull in a lot of code, and RV32I has no divide
// instruction, so every division goes through __udivsi3 anyway.
#include "io.h"

void putchar_(char c)
{
    MMIO(UART_TX) = (uint8_t)c;
}

void puts_(const char *s)
{
    while (*s)
        putchar_(*s++);
}

void print_hex(uint32_t v)
{
    const char *digits = "0123456789abcdef";
    for (int shift = 28; shift >= 0; shift -= 4)
        putchar_(digits[(v >> shift) & 0xF]);
}

void print_udec(uint32_t v)
{
    char buf[10];
    int n = 0;
    do {
        buf[n++] = '0' + (v % 10);
        v /= 10;
    } while (v);
    while (n)
        putchar_(buf[--n]);
}

void print_dec(int32_t v)
{
    if (v < 0) {
        putchar_('-');
        print_udec(-(uint32_t)v);
    } else {
        print_udec((uint32_t)v);
    }
}
