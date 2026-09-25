// crc32.c - standard CRC-32 (same as zlib) over 4 KB, table-driven.
// The 4 KB buffer + 1 KB table is what makes the D-cache sweep interesting.
#include "bench.h"

#define LEN 4096

static uint8_t  buf[LEN];
static uint32_t table[256];

static void make_table(void)
{
    for (uint32_t n = 0; n < 256; n++) {
        uint32_t c = n;
        for (int k = 0; k < 8; k++)
            c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
        table[n] = c;
    }
}

static uint32_t crc32(const uint8_t *p, int len)
{
    uint32_t c = 0xFFFFFFFFu;
    for (int i = 0; i < len; i++)
        c = table[(c ^ p[i]) & 0xFF] ^ (c >> 8);
    return c ^ 0xFFFFFFFFu;
}

int main(void)
{
    for (int i = 0; i < LEN; i++)
        buf[i] = (uint8_t)lcg();
    make_table();

    // known answer first: CRC-32 of "123456789" is 0xCBF43926
    if (crc32((const uint8_t *)"123456789", 9) != 0xCBF43926u)
        return 1;

    perf_t a, b;
    perf_read(&a);
    uint32_t c = crc32(buf, LEN);
    perf_read(&b);

    puts_("crc32: 4 KB, crc=0x"); print_hex(c); putchar_('\n');
    perf_report("crc32", &a, &b);
    return 0;
}
