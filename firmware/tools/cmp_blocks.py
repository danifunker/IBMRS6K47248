#!/usr/bin/env python3
"""Compare two images in fixed blocks; print identical / differing blocks and byte-diff counts.
usage: python3 -I cmp_blocks.py A B [blocksize]"""
import sys
a = open(sys.argv[1], 'rb').read(); b = open(sys.argv[2], 'rb').read()
bs = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x10000
for o in range(0, max(len(a), len(b)), bs):
    x, y = a[o:o+bs], b[o:o+bs]
    nd = sum(1 for i in range(min(len(x), len(y))) if x[i] != y[i]) + abs(len(x)-len(y))
    print(f"{o:06x} {'SAME' if nd == 0 else 'diff %6d bytes' % nd}")
