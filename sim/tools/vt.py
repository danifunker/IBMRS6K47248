#!/usr/bin/env python3
"""vt.py: the screen a VT100 terminal shows after a stream of bytes (the
bench's --com1 capture). Handles what the firmware sends: printable text, CR,
LF, BS, ESC [ r;c H (and f), ESC [ n A/B/C/D, ESC [ J / 2J, ESC [ K, ESC [ m
(attributes ignored), ESC ( / ) character sets (ignored).

  vt.py FILE [--rows 25] [--cols 80]"""
import re, sys

def main():
    a = sys.argv[1:]
    if not a: print(__doc__); return
    path = a.pop(0); rows, cols = 25, 80
    while a:
        x = a.pop(0)
        if x == '--rows': rows = int(a.pop(0))
        elif x == '--cols': cols = int(a.pop(0))
    data = open(path, 'rb').read()
    scr = [[' '] * cols for _ in range(rows)]
    r = c = 0
    i = 0
    def scroll():
        scr.pop(0); scr.append([' '] * cols)
    while i < len(data):
        b = data[i]; i += 1
        if b == 0x1B and i < len(data):
            if data[i] == ord('['):
                m = re.match(rb'\[([0-9;?]*)([A-Za-z])', data[i:])
                if not m: continue
                i += m.end()
                args = [int(x) if x.isdigit() else 0 for x in m.group(1).replace(b'?', b'').split(b';')] if m.group(1) else []
                f = m.group(2)
                n = args[0] if args and args[0] else 1
                if f in (b'H', b'f'):
                    r = (args[0] - 1 if len(args) > 0 and args[0] else 0)
                    c = (args[1] - 1 if len(args) > 1 and args[1] else 0)
                elif f == b'A': r = max(0, r - n)
                elif f == b'B': r = min(rows - 1, r + n)
                elif f == b'C': c = min(cols - 1, c + n)
                elif f == b'D': c = max(0, c - n)
                elif f == b'J':
                    if args and args[0] == 2:
                        scr = [[' '] * cols for _ in range(rows)]
                    else:
                        for cc in range(c, cols): scr[r][cc] = ' '
                        for rr in range(r + 1, rows): scr[rr] = [' '] * cols
                elif f == b'K':
                    for cc in range(c, cols): scr[r][cc] = ' '
                r = min(max(r, 0), rows - 1); c = min(max(c, 0), cols - 1)
            elif data[i] in b'()':
                i += 2
            else:
                i += 1
        elif b == 0x0D: c = 0
        elif b == 0x0A:
            r += 1
            if r == rows: scroll(); r = rows - 1
        elif b == 0x08: c = max(0, c - 1)
        elif 32 <= b < 127 or b >= 0xA0:
            scr[r][c] = chr(b) if b < 127 else '#'
            c += 1
            if c == cols: c = 0; r += 1
            if r == rows: scroll(); r = rows - 1
    print('+' + '-' * cols + '+')
    for row in scr: print('|' + ''.join(row) + '|')
    print('+' + '-' * cols + '+')

main()
