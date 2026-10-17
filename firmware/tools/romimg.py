#!/usr/bin/env python3
"""
romimg.py - parse IBM Carolina / Sandalfoot PReP flash images (512 KiB, mapped
at 0xFFF00000) and optionally rebuild the RAM image of the main block.

Image layout (as reverse-engineered from 7248 v1.12, see docs/firmware_analysis.md):
  each "block" (recovery @0x00000, main @0x10000) starts with
    +0x000  ASCII header "<partno> <title> - Property of IBM ... Corp."  NUL
    +0x0E8  u32 (block checksum / id word, see doc)
    +0x100  b <entry>   (reset vector when the block is at 0xFFF00000)
    +0x104  b <entry+4>
    +0x108  "MMDDYYYY HHMMSS" build stamp
    +0xFF0  u32 offset of the block descriptor (relative to block start)
  block descriptor:
    +0x00 u32 1   +0x04 u32 0x3C (size)  +0x08 u32 ptr  +0x0C u32 compressed flag
    +0x10 u32 offset of next block (recovery: 0x10000) / block length
    +0x14 u32 0x108 (stamp)  +0x18 u32 0x117  +0x1C u32 0x100 (entry)
    +0x20 u32 end of stored data      (rel. to block start)
    +0x24 u32 start of LZW stream / end of uncompressed stub
    +0x28 u32 end of RAM image        (RAM image is linked at 0x00000000)
    +0x2C u32 TOC (r2) of RAM image
    +0x34 u32 0xEC, +0x38 0x100, +0x3C 0x10, +0x40.. planar IDs (0xF0..)

usage:
  python3 -I romimg.py IMAGE                 # print summary of both blocks
  python3 -I romimg.py IMAGE --ram OUT       # write main-block RAM image (load at 0)
"""
import struct, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from unlzw_rom import unlzw   # noqa: E402  (our own module in tools/)

def u32(d, o): return struct.unpack_from('>I', d, o)[0]

def block_info(d, base):
    hdr = d[base:base + 0xE8].split(b'\0')[0].decode('latin-1')
    stamp = d[base + 0x108:base + 0x118].split(b'\0')[0].decode('latin-1')
    dpos = u32(d, base + 0xFF0)
    desc = [u32(d, base + dpos + 4 * i) for i in range(16)]
    br = u32(d, base + 0x100)
    entry = base + 0x100 + ((br & 0x03fffffc) ^ 0x02000000) - 0x02000000 if br >> 26 == 18 else None
    return dict(base=base, header=hdr, stamp=stamp, word_e8=u32(d, base + 0xE8), desc_off=dpos,
                desc=desc, entry=entry)

def main():
    a = sys.argv[1:]
    if not a: print(__doc__); sys.exit(1)
    d = open(a[0], 'rb').read()
    blocks = [block_info(d, 0)]
    nxt = blocks[0]['desc'][4]
    if 0 < nxt < len(d) and d[nxt + 0x100:nxt + 0x101] == b'\x48':
        blocks.append(block_info(d, nxt))
    for b in blocks:
        print(f"block @{b['base']:#07x} header='{b['header'][:60]}'")
        print(f"   stamp={b['stamp']}  word@E8={b['word_e8']:#010x}  reset-branch-> file {b['entry']:#x}" if b['entry'] is not None else '   (no branch at +0x100)')
        print(f"   descriptor @+{b['desc_off']:#x}: " + ' '.join(f'{x:08x}' for x in b['desc']))
    if '--ram' in a:
        m = blocks[-1]; base = m['base']; dsc = m['desc']
        end, lzw, ramend, toc = dsc[8], dsc[9], dsc[10], dsc[11]
        stub = d[base:base + lzw]
        payload = unlzw(d[base + lzw:base + end]) if dsc[3] else d[base + lzw:base + end]
        img = stub + payload
        print(f'RAM image: stub {len(stub):#x} + payload {len(payload):#x} = {len(img):#x} (descriptor says {ramend:#x}); TOC {toc:#x}')
        open(a[a.index('--ram') + 1], 'wb').write(img)

if __name__ == '__main__':
    main()
