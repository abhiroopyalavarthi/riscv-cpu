// matmul.c - 16x16 integer matrix multiply. RV32I has no multiply, so each
// a*b is a call to __mulsi3 (shift-and-add loop): lots of short loops.
#include "bench.h"

#define N 16

static int A[N][N], B[N][N], C[N][N];

static void matmul(void)
{
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++) {
            int s = 0;
            for (int k = 0; k < N; k++)
                s += A[i][k] * B[k][j];
            C[i][j] = s;
        }
}

int main(void)
{
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++) {
            A[i][j] = (int)(lcg() % 201) - 100;
            B[i][j] = (int)(lcg() % 201) - 100;
        }

    perf_t a, b;
    perf_read(&a);
    matmul();
    perf_read(&b);

    // check without redoing the same multiply: C * 1 must equal A * (B * 1)
    // (row sums), which uses a different order of operations
    for (int i = 0; i < N; i++) {
        int lhs = 0, rhs = 0;
        for (int j = 0; j < N; j++)
            lhs += C[i][j];
        for (int k = 0; k < N; k++) {
            int brow = 0;
            for (int j = 0; j < N; j++)
                brow += B[k][j];
            rhs += A[i][k] * brow;
        }
        if (lhs != rhs)
            return 1;
    }

    uint32_t chk = 0;
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++)
            chk = (chk << 1 | chk >> 31) ^ (uint32_t)C[i][j];
    puts_("matmul: 16x16, checksum=0x"); print_hex(chk); putchar_('\n');
    perf_report("matmul", &a, &b);
    return 0;
}
