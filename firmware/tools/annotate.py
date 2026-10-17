#!/usr/bin/env python3
"""annotate.py - objdump a raw BE PowerPC image and insert function labels
(from tbtab.py output) and symbolic branch targets.  Streams; low memory.
usage: python3 -I annotate.py IMAGE VMA SYMS OUT [start end]"""
import re, subprocess, sys
img, vma, symf, out = sys.argv[1], int(sys.argv[2], 0), sys.argv[3], sys.argv[4]
st = int(sys.argv[5], 0) if len(sys.argv) > 5 else vma
en = int(sys.argv[6], 0) if len(sys.argv) > 6 else None
syms = {}
for l in open(symf):
    f = l.split()
    if len(f) == 3 and f[0] != '????????': syms.setdefault(int(f[0], 16), f[2])
cmd = ['powerpc-linux-gnu-objdump', '-D', '-b', 'binary', '-m', 'powerpc:604', '-EB',
       f'--adjust-vma={vma:#x}', f'--start-address={st:#x}', img]
if en: cmd.append(f'--stop-address={en:#x}')
p = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True)
L = re.compile(r'^\s*([0-9a-f]+):\t((?:[0-9a-f]{2} ){4})\t?(.*)$')
with open(out, 'w') as o:
    for l in p.stdout:
        m = L.match(l)
        if not m: continue
        a = int(m.group(1), 16)
        if a in syms: o.write(f'\n{a:08x} <{syms[a]}>:\n')
        ins = m.group(3).expandtabs(8)
        t = re.search(r'0x([0-9a-f]+)$', ins)
        if t and ins.split()[0].startswith('b'):
            ta = int(t.group(1), 16)
            if ta in syms: ins += f'  <{syms[ta]}>'
        o.write(f'{a:08x}:  {m.group(2)} {ins}\n')
p.wait()
