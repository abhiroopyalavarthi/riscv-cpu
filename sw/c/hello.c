// hello.c - first C program on the CPU.
#include "io.h"

// volatile so GCC can't do the math at compile time - these have to go
// through the software mul/div on the CPU
static volatile int ten = 10, big = 1000000, seven = 7, neg = -12345;

static int fact(int n) { return n <= 1 ? 1 : n * fact(n - 1); }

int main(void)
{
    puts_("Hello from my CPU\n");

    int f = fact(ten);
    int q = big / seven, r = big % seven;
    int nq = neg / ten, nr = neg % ten;

    puts_("10! = ");            print_dec(f);
    puts_("\n1000000 / 7 = ");  print_dec(q);
    puts_(" rem ");             print_dec(r);
    puts_("\n-12345 / 10 = ");  print_dec(nq);
    puts_(" rem ");             print_dec(nr);
    puts_("\n0xdeadbeef = ");   print_hex(0xdeadbeef);
    puts_("\ncycles so far: "); print_udec(read_cycles());
    puts_("\n");

    // self-check, so a wrong answer fails the test instead of just printing
    if (f != 3628800) return 1;
    if (q != 142857 || r != 1) return 2;
    if (nq != -1234 || nr != -5) return 3;
    return 0;
}
