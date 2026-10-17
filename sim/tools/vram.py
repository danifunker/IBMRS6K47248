#!/usr/bin/env python3
"""vram.py: the bench's S3 VRAM dump (--vram) as a picture (PPM, which most
viewers open): 8 bits a pixel, the palette index as grey until the palette
can be dumped too.

  vram.py VRAM.bin OUT.ppm [--width 640] [--height 480] [--pitch 640] [--start 0]"""
import sys

def main():
    a = sys.argv[1:]
    if len(a) < 2: print(__doc__); return
    src, out = a[0], a[1]
    w, h, pitch, start = 640, 480, None, 0
    i = 2
    while i < len(a):
        if a[i] == '--width': w = int(a[i + 1])
        elif a[i] == '--height': h = int(a[i + 1])
        elif a[i] == '--pitch': pitch = int(a[i + 1])
        elif a[i] == '--start': start = int(a[i + 1], 0)
        i += 2
    pitch = pitch or w
    d = open(src, 'rb').read()
    rows = []
    for y in range(h):
        row = d[start + y * pitch: start + y * pitch + w]
        rows.append(bytes(b for p in row for b in (p, p, p)))
    with open(out, 'wb') as f:
        f.write(b'P6\n%d %d\n255\n' % (w, h))
        f.write(b''.join(rows))
    nz = sum(1 for b in d[start:start + pitch * h] if b)
    print('%s: %d x %d, %d non-zero bytes' % (out, w, h, nz))

main()
