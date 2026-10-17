#!/usr/bin/env python3
"""vcdq: query a VCD: the changes of signals whose full names match the given
patterns (regular expressions), within a time window.

  vcdq.py FILE.vcd [--from T] [--to T] [--list] PATTERN...

--list prints the matching names only. Values print in hex. Times are the
VCD's (the bench dumps two per clock: clock N's rising edge is at 2N + 1)."""
import re, sys

def main():
    a = sys.argv[1:]
    if not a: print(__doc__); return
    path = a.pop(0)
    t0, t1, lst, pats = 0, None, False, []
    while a:
        x = a.pop(0)
        if x == '--from': t0 = int(a.pop(0))
        elif x == '--to': t1 = int(a.pop(0))
        elif x == '--list': lst = True
        else: pats.append(re.compile(x))
    scope, codes, names = [], {}, {}
    with open(path) as f:
        for line in f:
            w = line.split()
            if not w: continue
            if w[0] == '$scope': scope.append(w[2])
            elif w[0] == '$upscope': scope.pop()
            elif w[0] == '$var':
                name = '.'.join(scope + [w[4]])
                if any(p.search(name) for p in pats):
                    codes.setdefault(w[3], []).append(name)
                    names[name] = w[3]
            elif w[0] == '$enddefinitions': break
        if lst:
            for n in sorted(names): print(n)
            return
        t = 0
        for line in f:
            c = line[0]
            if c == '#':
                t = int(line[1:])
                if t1 is not None and t > t1: break
                continue
            if t < t0: continue
            if c == 'b':
                v, code = line[1:].split()
            elif c in '01xz':
                v, code = c, line[1:].strip()
            else:
                continue
            if code in codes:
                try: hv = '%X' % int(v, 2)
                except ValueError: hv = v
                for n in codes[code]: print('%10d  %-60s %s' % (t, n[-60:], hv))

main()
