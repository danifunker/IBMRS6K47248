#!/usr/bin/env python3
"""Print a per-block entropy / fill map of a binary image.
usage: python3 -I entropy_map.py IMAGE [blocksize]"""
import sys, math, collections
d = open(sys.argv[1], 'rb').read()
bs = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0x2000
for o in range(0, len(d), bs):
    b = d[o:o+bs]
    c = collections.Counter(b)
    e = -sum(v/len(b)*math.log2(v/len(b)) for v in c.values())
    top, n = c.most_common(1)[0]
    print(f"{o:06x}  H={e:4.2f}  top={top:02x}x{n*100//len(b):3d}%  {'#'*int(e*4)}")
