#!/usr/bin/env python3
"""Turn a flat binary (objcopy -O binary) into a $readmemh file:
one 32-bit little-endian word per line, starting at address 0.

I do this instead of objcopy -O verilog because the word width/byte order
options in objcopy changed between binutils versions, and the Mac and
Linux toolchains don't agree.
"""
import sys

RAM_BYTES = 64 * 1024

def main():
    if len(sys.argv) != 3:
        sys.exit("usage: bin2hex.py in.bin out.hex")
    data = open(sys.argv[1], "rb").read()
    if len(data) > RAM_BYTES:
        sys.exit(f"bin2hex: program is {len(data)} bytes, RAM is only {RAM_BYTES}")
    data += b"\x00" * (-len(data) % 4)
    with open(sys.argv[2], "w") as f:
        for i in range(0, len(data), 4):
            f.write(f"{int.from_bytes(data[i:i+4], 'little'):08x}\n")

if __name__ == "__main__":
    main()
