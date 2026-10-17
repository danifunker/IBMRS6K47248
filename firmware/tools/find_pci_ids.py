#!/usr/bin/env python3
"""find_pci_ids.py - find 32-bit (device<<16 | vendor) constants built with
lis rA,hi ; addi/addic/ori rB,rA,lo  (or li/lis + oris) in an annotated listing
(annotate.py output) and report those whose low half is a known PCI vendor.
usage: python3 -I find_pci_ids.py LISTING"""
import re, sys, collections
V = {0x1014: 'IBM', 0x1057: 'Motorola', 0x1000: 'NCR/Symbios', 0x5333: 'S3', 0x1022: 'AMD',
     0x100e: 'Weitek', 0x8086: 'Intel', 0x1013: 'Cirrus', 0x10e8: 'AMCC', 0x1011: 'DEC',
     0x102b: 'Matrox', 0x1002: 'ATI', 0x104c: 'TI', 0x3d3d: '3Dlabs', 0x10b7: '3Com',
     0x1023: 'Trident', 0x100b: 'National', 0x9004: 'Adaptec', 0x1095: 'CMD', 0x1045: 'OPTi',
     0x1077: 'QLogic', 0x10b9: 'ALi', 0x1106: 'VIA', 0x1039: 'SiS', 0x108e: 'Sun', 0x1048: 'Elsa',
     0x102c: 'C&T', 0x1092: 'Diamond', 0x105d: 'Number Nine', 0x10ec: 'Realtek', 0x1101: 'Initio'}
fn = None; hi = {}; out = collections.OrderedDict()
for l in open(sys.argv[1]):
    m = re.match(r'^([0-9a-f]{8}) <(.*)>:', l)
    if m: fn = m.group(2); hi = {}; continue
    m = re.match(r'^([0-9a-f]{8}):\s+(?:[0-9a-f]{2} ){4}\s*(\S+)\s+(.*)', l)
    if not m: continue
    a, mn, ops = m.group(1), m.group(2), m.group(3)
    o = [x.strip() for x in ops.split(',')]
    try:
        if mn == 'lis': hi[o[0]] = (int(o[1]) & 0xffff) << 16; continue
        if mn in ('addi', 'addic', 'ori') and o[1] in hi and o[1] != 'r0' or (mn == 'addi' and o[1] in hi):
            lo = int(o[2])
            v = (hi[o[1]] + lo) & 0xffffffff if mn != 'ori' else hi[o[1]] | (lo & 0xffff)
            ven, dev = v & 0xffff, v >> 16
            if ven in V and dev not in (0, 0xffff):
                out.setdefault((dev, ven), []).append((a, fn))
            continue
        if mn == 'li' and o[0] in hi: hi.pop(o[0], None)
    except (ValueError, IndexError):
        pass
for (dev, ven), where in sorted(out.items(), key=lambda kv: (kv[0][1], kv[0][0])):
    fns = collections.Counter(w[1] for w in where)
    print(f'{ven:04x}:{dev:04x}  {V[ven]:12} n={len(where):2}  ' + ', '.join(f'{f}' for f in fns) + f'  (first @{where[0][0]})')
