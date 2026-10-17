#!/usr/bin/env python3
"""
ppctrace.py - light-weight constant-propagating tracer over objdump output
for big-endian PowerPC firmware images.

It does NOT emulate control flow.  It sweeps the disassembly linearly,
tracking registers that are loaded with constants (li/lis/ori/oris/addi/
addis/xor rX,rX,rX/mr/rlwinm/slwi/...) and, for every load/store whose
effective address is known, prints the access.  Register state is dropped
after unconditional branches / blr / rfi and at branch targets (so constants
do not leak across basic blocks), and volatile regs r0,r3-r12 are dropped
after bl (r13-r31 are kept: the early asm code uses r13-r21 as scratch
without calling).

usage:
  python3 -I ppctrace.py IMAGE VMA START END [--all] [--csv]
     IMAGE  raw binary
     VMA    load address of offset 0 (e.g. 0xfff00000)
     START/END  address range to sweep
  Output: one line per memory access with a known EA.
"""
import re, subprocess, sys

def u32(x): return x & 0xffffffff
def sext16(x): return x - 0x10000 if x & 0x8000 else x
def bswap32(v): return int.from_bytes(u32(v).to_bytes(4, 'big'), 'little')
def bswap16(v): return int.from_bytes((v & 0xffff).to_bytes(2, 'big'), 'little')

def mask(mb, me):
    m = 0
    if mb <= me:
        for b in range(mb, me + 1): m |= 1 << (31 - b)
    else:
        for b in range(0, me + 1): m |= 1 << (31 - b)
        for b in range(mb, 32): m |= 1 << (31 - b)
    return m

def rotl(v, n): n &= 31; return u32((v << n) | (v >> (32 - n))) if n else v

LINE = re.compile(r'^\s*([0-9a-f]+):\s+((?:[0-9a-f]{2} ){4})\s*(\S+)?\s*(.*)$')

def disasm(image, vma, start, end):
    out = subprocess.run(['powerpc-linux-gnu-objdump', '-D', '-b', 'binary',
                          '-m', 'powerpc:604', '-EB', f'--adjust-vma={vma:#x}',
                          f'--start-address={start:#x}', f'--stop-address={end:#x}',
                          image], capture_output=True, text=True, check=True).stdout
    ins = []
    for l in out.splitlines():
        m = LINE.match(l)
        if not m: continue
        a = int(m.group(1), 16); mn = m.group(3) or ''; ops = m.group(4).split('#')[0].strip()
        ins.append((a, m.group(2).strip(), mn, ops))
    return ins

def reg(s):
    s = s.strip()
    if re.fullmatch(r'r\d+', s): return int(s[1:])
    return None

def imm(s):
    s = s.strip()
    try: return int(s, 0)
    except ValueError: return None

MEM = re.compile(r'^(-?\w+)\((r\d+)\)$')
SIZE = {'b': 1, 'h': 2, 'w': 4}

def region(ea):
    if 0x80000000 <= ea < 0x80800000: return 'ISA/PCI-IO port %#06x' % (ea - 0x80000000)
    if 0x80800000 <= ea < 0x81000000: return 'PCI cfg direct'
    if 0xbffffff0 <= ea <= 0xbfffffff: return 'PCI INTACK'
    if 0xc0000000 <= ea < 0xff000000: return 'PCI mem'
    if 0xff000000 <= ea: return 'ROM/sys'
    if ea < 0x80000000: return 'RAM'
    return '?'

def trace(image, vma, start, end, show_all=False, syms=None, calls=None):
    """syms: {addr: name} of helpers whose constant args (r3..r6) are logged into calls"""
    syms = syms or {}
    ins = disasm(image, vma, start, end)
    targets = set()
    for a, raw, mn, ops in ins:
        if mn.startswith('b') and not mn.startswith('bl') or mn in ('bl', 'bla'):
            pass
        m = re.search(r'0x([0-9a-f]+)$', ops)
        if mn.startswith('b') and m: targets.add(int(m.group(1), 16))
    R = {}
    cf8 = None
    rows = []
    for a, raw, mn, ops in ins:
        if a in targets: R = {}
        o = [x.strip() for x in ops.split(',')] if ops else []
        base = mn.rstrip('.')
        try:
            if base == 'li': R[reg(o[0])] = u32(imm(o[1]))
            elif base == 'lis': R[reg(o[0])] = u32(imm(o[1]) << 16)
            elif base in ('addi', 'addis', 'addic'):
                d, s, i = reg(o[0]), reg(o[1]), imm(o[2])
                sh = 16 if base == 'addis' else 0
                if base != 'addic' and s == 0: R[d] = u32(i << sh)   # (rA|0)
                elif s in R: R[d] = u32(R[s] + (i << sh))
                else: R.pop(d, None)
            elif base in ('ori', 'oris', 'xori', 'xoris', 'andi', 'andis'):
                d, s, i = reg(o[0]), reg(o[1]), imm(o[2])
                if base.endswith('s'): i <<= 16
                if s in R:
                    v = R[s]
                    R[d] = u32(v | i if base.startswith('or') else v ^ i if base.startswith('xor') else v & i)
                else: R.pop(d, None)
            elif base in ('xor', 'or', 'and', 'add', 'subf', 'nor', 'andc') and len(o) == 3:
                d, s, t = reg(o[0]), reg(o[1]), reg(o[2])
                if base == 'xor' and s == t: R[d] = 0
                elif s in R and t in R:
                    x, y = R[s], R[t]
                    R[d] = u32({'xor': x ^ y, 'or': x | y, 'and': x & y, 'add': x + y,
                                'subf': y - x, 'nor': ~(x | y), 'andc': x & ~y}[base])
                else: R.pop(d, None)
            elif base == 'mr':
                d, s = reg(o[0]), reg(o[1])
                if s in R: R[d] = R[s]
                else: R.pop(d, None)
            elif base in ('slwi', 'srwi', 'clrlwi', 'clrrwi', 'rotlwi'):
                d, s, n = reg(o[0]), reg(o[1]), imm(o[2])
                if s in R:
                    v = R[s]
                    R[d] = u32({'slwi': v << n, 'srwi': v >> n, 'clrlwi': v & (0xffffffff >> n),
                                'clrrwi': v & u32(0xffffffff << n), 'rotlwi': rotl(v, n)}[base])
                else: R.pop(d, None)
            elif base == 'rlwinm':
                d, s, sh, mb, me = reg(o[0]), reg(o[1]), imm(o[2]), imm(o[3]), imm(o[4])
                if s in R: R[d] = rotl(R[s], sh) & mask(mb, me)
                else: R.pop(d, None)
            elif base == 'rlwimi':
                d, s, sh, mb, me = reg(o[0]), reg(o[1]), imm(o[2]), imm(o[3]), imm(o[4])
                if s in R and d in R:
                    m_ = mask(mb, me); R[d] = (rotl(R[s], sh) & m_) | (R[d] & ~m_ & 0xffffffff)
                else: R.pop(d, None)
            elif re.fullmatch(r'(l|st)(bz|b|hz|h|ha|wz|w|hbr|wbr)(u)?(x)?', base):
                m = re.fullmatch(r'(l|st)(bz|b|hz|h|ha|wz|w|hbr|wbr)(u)?(x)?', base)
                ld = m.group(1) == 'l'; kind = m.group(2); upd = m.group(3); idx = m.group(4)
                sz = SIZE[kind[0]]
                if kind in ('hbr',): sz = 2
                if kind in ('wbr',): sz = 4
                rs = reg(o[0])
                if idx:
                    ra, rb = reg(o[1]), reg(o[2])
                    av = 0 if ra == 0 else R.get(ra)
                    ea = u32(av + R[rb]) if av is not None and rb in R else None
                else:
                    mm = MEM.match(o[1]); d = imm(mm.group(1)); ra = reg(mm.group(2))
                    av = 0 if ra == 0 else R.get(ra)
                    ea = u32(av + d) if av is not None else None
                val = None
                if not ld and rs in R:
                    val = R[rs]
                    if sz == 1: val &= 0xff
                    if sz == 2: val &= 0xffff
                if ea is not None and (show_all or ea >= 0x80000000):
                    note = ''
                    # data as seen on the little-endian PCI/ISA bus (byte lanes):
                    le = None
                    if val is not None:
                        if kind == 'wbr' or kind == 'hbr': le = val
                        elif sz == 4: le = bswap32(val)
                        elif sz == 2: le = bswap16(val)
                        else: le = val
                    if ea == 0x80000cf8 and not ld and le is not None:
                        cf8 = le
                        note = 'CF8<=%08x (bus %d dev %d fn %d reg %#04x)' % (le, (le >> 16) & 0xff, (le >> 11) & 31, (le >> 8) & 7, le & 0xfc)
                    elif 0x80000cfc <= ea <= 0x80000cff and cf8 is not None:
                        note = 'cfg dev %d fn %d reg %#04x' % ((cf8 >> 11) & 31, (cf8 >> 8) & 7, (cf8 & 0xfc) + (ea - 0x80000cfc))
                    elif 0x80800000 <= ea < 0x81000000:
                        off = ea - 0x80800000
                        # direct-map: address bit (11+dev) selects IDSEL
                        bits = off >> 11; dev = bits.bit_length() + 10 if bits else None
                        note = 'direct cfg idsel-bit %s fn %d reg %#04x' % (dev, (off >> 8) & 7, off & 0xff)
                    rows.append((a, mn, ops, ea, sz, 'R' if ld else 'W', val, le, region(ea), note))
                if upd and ea is not None: R[ra] = ea
                elif upd: R.pop(reg(o[1]) if idx else reg(MEM.match(o[1]).group(2)), None)
                if ld: R.pop(rs, None)
            elif base in ('lmw',):
                R = {k: v for k, v in R.items() if k < reg(o[0])}
            elif mn in ('bl', 'bla', 'blrl', 'bctrl'):
                m_ = re.search(r'0x([0-9a-f]+)$', ops)
                if m_ and calls is not None and int(m_.group(1), 16) in syms:
                    calls.append((a, syms[int(m_.group(1), 16)], [R.get(k) for k in (3, 4, 5, 6)]))
                for k in [0] + list(range(3, 13)): R.pop(k, None)
            elif mn in ('b', 'blr', 'bctr', 'rfi', 'ba'):
                R = {}
            elif mn.startswith('mf') or mn.startswith('lwarx'):
                if o and reg(o[0]) is not None: R.pop(reg(o[0]), None)
            elif o and reg(o[0]) is not None and not mn.startswith(('cmp', 'st', 'mt', 'b', 'tw', 'dcb', 'icb')):
                R.pop(reg(o[0]), None)
        except (TypeError, AttributeError, IndexError, KeyError):
            if o and reg(o[0]) is not None: R.pop(reg(o[0]), None)
    return rows

def main():
    a = sys.argv[1:]
    if len(a) < 4:
        print(__doc__); sys.exit(1)
    image, vma, start, end = a[0], int(a[1], 0), int(a[2], 0), int(a[3], 0)
    show_all = '--all' in a; csv = '--csv' in a
    syms = {}; calls = None
    if '--syms' in a:
        # --syms FILE (tbtab.py output) [--calls REGEX]: log constant args of calls to matching functions
        rx = re.compile(a[a.index('--calls') + 1]) if '--calls' in a else re.compile(r'^(in|out)(8|16|32)(le)?$')
        for l in open(a[a.index('--syms') + 1]):
            f = l.split()
            if len(f) == 3 and f[0] != '????????' and rx.search(f[2]): syms[int(f[0], 16)] = f[2]
        calls = []
    rows = trace(image, vma, start, end, show_all, syms, calls)
    if calls is not None:
        for a_, n, args in calls:
            print(f'{a_:08x}  CALL {n:24} ' + ' '.join('-' if v is None else f'{v:#x}' for v in args))
        return
    for r in rows:
        a_, mn, ops, ea, sz, rw, val, le, reg_, note = r
        vs = '' if val is None else ('%0*x' % (sz * 2, val))
        ls = '' if le is None else ('%0*x' % (sz * 2, le))
        if csv:
            print(f'{a_:08x},{rw},{sz},{ea:08x},{vs},{ls},{reg_},{note},{mn} {ops}')
        else:
            print(f'{a_:08x}  {rw}{sz}  {ea:08x}  be={vs:8} le={ls:8} {reg_:28} {note:46} | {mn} {ops}')

if __name__ == '__main__':
    main()
