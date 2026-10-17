#!/usr/bin/env python3
"""Score how plausible a region is as PowerPC code in BE vs LE byte order.
Counts 32-bit words that decode to common opcodes (blr, mflr/mtlr, stwu r1,
lwz/stw with r1 base, addi/li, bl/b, ori/oris, rlwinm, cmpwi).
usage: python3 -I endian_score.py IMAGE [start end]"""
import sys, struct
d = open(sys.argv[1], 'rb').read()
s = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0
e = int(sys.argv[3], 0) if len(sys.argv) > 3 else len(d)
def score(fmt):
    c = dict(blr=0, mflr=0, mtlr=0, stwu_r1=0, r1_ldst=0, branch=0, addi=0, ori=0, rlwinm=0, cmp=0)
    for (w,) in struct.iter_unpack(fmt, d[s:e - (e - s) % 4]):
        op = w >> 26; ra = (w >> 16) & 31
        if w == 0x4e800020: c['blr'] += 1
        elif w == 0x7c0802a6: c['mflr'] += 1
        elif w == 0x7c0803a6: c['mtlr'] += 1
        elif op == 37 and ra == 1: c['stwu_r1'] += 1
        elif op in (32, 36) and ra == 1: c['r1_ldst'] += 1
        elif op == 18: c['branch'] += 1
        elif op in (14, 15): c['addi'] += 1
        elif op in (24, 25): c['ori'] += 1
        elif op == 21: c['rlwinm'] += 1
        elif op in (10, 11): c['cmp'] += 1
    return c
for name, fmt in (('big-endian', '>I'), ('little-endian', '<I')):
    c = score(fmt); print(f'{name:14} total={sum(c.values()):7}  ' + ' '.join(f'{k}={v}' for k, v in c.items()))
