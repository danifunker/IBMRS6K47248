#!/usr/bin/env python3
"""
unlzw_rom.py - decompress the LZW payload of IBM Carolina / Sandalfoot PReP
firmware images.

The ROM's decompress()/getcode() routines (named by their XCOFF traceback
tables, e.g. 7248 v1.12 at 0xFFF17670 / 0xFFF1789C) are a straight port of
Unix compress(1) 4.x: LSB-first variable-width codes 9..16 bits, block mode
(code 256 = CLEAR, first free code 257), codes read in groups of n_bits bytes
(a group is abandoned whenever the code width changes or on CLEAR).  There is
NO 0x1F9D magic header in the ROM stream.

usage: python3 -I unlzw_rom.py IMAGE START END OUT [maxbits]
   START/END: file offsets of the compressed stream (END exclusive)
"""
import sys

def unlzw(data, maxbits=16):
    maxmaxcode = 1 << maxbits
    pos = 0                      # byte position in data
    n_bits = 9; maxcode = (1 << n_bits) - 1
    free_ent = 257; clear_flg = 0
    buf = b''; offset = 0; size = 0
    prefix = [0] * maxmaxcode; suffix = bytearray(maxmaxcode)
    for i in range(256): suffix[i] = i
    out = bytearray()

    def getcode():
        nonlocal pos, n_bits, maxcode, clear_flg, buf, offset, size
        if clear_flg > 0 or offset >= size or free_ent > maxcode:
            if free_ent > maxcode:
                n_bits += 1
                maxcode = maxmaxcode if n_bits == maxbits else (1 << n_bits) - 1
            if clear_flg > 0:
                n_bits = 9; maxcode = (1 << n_bits) - 1; clear_flg = 0
            buf = data[pos:pos + n_bits]; pos += len(buf)
            if not buf: return -1
            offset = 0; size = (len(buf) << 3) - (n_bits - 1)
            if size <= 0: return -1
        v = int.from_bytes(buf, 'little') >> offset
        offset += n_bits
        return v & ((1 << n_bits) - 1)

    oldcode = getcode()
    if oldcode < 0: return out
    finchar = oldcode; out.append(finchar)
    while True:
        code = getcode()
        if code < 0: break
        if code == 256:
            clear_flg = 1; free_ent = 256
            code = getcode()
            if code < 0: break
        incode = code
        stack = bytearray()
        if code >= free_ent:
            if code > free_ent:
                raise ValueError(f'bad code {code} free_ent {free_ent} at input byte {pos}, output {len(out)}')
            stack.append(finchar); code = oldcode
        while code >= 256:
            stack.append(suffix[code]); code = prefix[code]
        finchar = suffix[code]; stack.append(finchar)
        stack.reverse(); out += stack
        if free_ent < maxmaxcode:
            prefix[free_ent] = oldcode; suffix[free_ent] = finchar; free_ent += 1
        oldcode = incode
    return out

def main():
    if len(sys.argv) < 5:
        print(__doc__); sys.exit(1)
    d = open(sys.argv[1], 'rb').read()
    s, e = int(sys.argv[2], 0), int(sys.argv[3], 0)
    mb = int(sys.argv[5]) if len(sys.argv) > 5 else 16
    out = unlzw(d[s:e], mb)
    open(sys.argv[4], 'wb').write(out)
    print(f'{len(out)} bytes ({len(out):#x}) written to {sys.argv[4]}')

if __name__ == '__main__':
    main()
