// sort.c - insertion sort of 256 ints. Lots of data-dependent branches,
// so it's the interesting one for the branch predictor.
#include "bench.h"

#define N 256

static int data[N];

static void insertion_sort(int *a, int n)
{
    for (int i = 1; i < n; i++) {
        int key = a[i];
        int j = i - 1;
        while (j >= 0 && a[j] > key) {
            a[j + 1] = a[j];
            j--;
        }
        a[j + 1] = key;
    }
}

int main(void)
{
    uint32_t sum_before = 0, sum_after = 0;
    for (int i = 0; i < N; i++) {
        data[i] = (int)(lcg() & 0xFFFF) - 0x8000;   // negative numbers too
        sum_before += data[i];
    }

    perf_t a, b;
    perf_read(&a);
    insertion_sort(data, N);
    perf_read(&b);

    // check: sorted, and nothing lost or duplicated (sum unchanged)
    for (int i = 0; i < N; i++) {
        sum_after += data[i];
        if (i > 0 && data[i - 1] > data[i])
            return 1;
    }
    if (sum_before != sum_after)
        return 2;

    puts_("sort: 256 ints, min="); print_dec(data[0]);
    puts_(" max="); print_dec(data[N - 1]); putchar_('\n');
    perf_report("sort", &a, &b);
    return 0;
}
