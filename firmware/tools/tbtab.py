#!/usr/bin/env python3
"""
tbtab.py - recover function names from XCOFF/PowerOpen traceback tables
embedded after compiled functions (IBM xlc output).

Traceback table layout (after the function's final blr):
  u32 0x00000000                 marker
  u8 version, u8 lang, u8 flags1, u8 flags2, u8 flags3, u8 flags4,
  u8 fixedparms, u8 flags5(floatparms<<1 | parmsonstack)
  [u32 parminfo]  if fixedparms or floatparms
  [u32 tb_offset] if flags1 & 0x20 (has_tboff): offset from function start
  ... (int handler / ctl info skipped for these images)
  [u16 name_len, name] if flags2 & 0x40 (name_present)

usage: python3 -I tbtab.py IMAGE VMA [START END]
prints:  func_start  tb_addr  name
"""
import re, sys

def scan(d, vma, lo=0, hi=None):
    hi = hi or len(d)
    out = []
    for m in re.finditer(rb'\x4e\x80\x00\x20\x00\x00\x00\x00', d[lo:hi]):
        p = lo + m.start() + 8
        if p + 12 > len(d): continue
        ver, lang, f1, f2, f3, f4, fixp, f5 = d[p:p+8]
        if ver != 0 or lang > 0x0f: continue
        q = p + 8
        floatp = f5 >> 1
        if fixp or floatp: q += 4
        tboff = None
        if f1 & 0x20:
            tboff = int.from_bytes(d[q:q+4], 'big'); q += 4
        if f1 & 0x08:  # int_hndl
            q += 4
        if f1 & 0x02:  # has_ctl
            n = int.from_bytes(d[q:q+4], 'big'); q += 4 + 4 * n
        name = None
        if f2 & 0x40:
            ln = int.from_bytes(d[q:q+2], 'big')
            raw = d[q+2:q+2+ln]
            if 0 < ln < 80 and re.fullmatch(rb'[A-Za-z_.$][A-Za-z0-9_.$]*', raw):
                name = raw.decode()
        if name is None: continue
        start = (p - 4 - tboff) if tboff else None   # tboff = bytes from fn start to tb marker
        out.append((start, p - 4, name))
    return out

def main():
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(1)
    d = open(sys.argv[1], 'rb').read(); vma = int(sys.argv[2], 0)
    lo = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0
    hi = int(sys.argv[4], 0) if len(sys.argv) > 4 else None
    for s, tb, n in scan(d, vma, lo, hi):
        ss = f'{s + vma:08x}' if s is not None else '????????'
        print(f'{ss}  tb@{tb + vma:08x}  {n}')

if __name__ == '__main__':
    main()
