# decode the board's debug stream's floppy events (the LITE trace build): python fdboard.py dbg.raw
import sys, re
d = open(sys.argv[1], 'rb').read().decode('latin1').replace('\r', ' ').replace('\n', ' ')
toks = [t for t in d.split(' ') if t]
DMA = {0x00:'ch0a',0x01:'ch0c',0x02:'ch1a',0x03:'ch1c',0x04:'ch2addr',0x05:'ch2cnt',0x06:'ch3a',0x07:'ch3c',0x08:'cmd',0x09:'req',0x0A:'mask',0x0B:'mode',0x0C:'clrff',0x0D:'mclr',0x0E:'clrmask',0x0F:'allmask',
       0x80:'p80',0x81:'page2',0x82:'page3',0x83:'page1',0x480:'p480',0x481:'hpage2',0x482:'hpage3',0x483:'hpage1'}
out = []
cmd = []
for t in toks:
    m = re.fullmatch(r'([WRwr])([0-9A-F])([0-9A-F]{2})=([0-9A-F]{8})', t)
    if not m:
        if t.startswith('.') or t.startswith('C8=') or t.startswith('cR=') or t.startswith('cW='): continue
        out.append(t); continue
    rw, be, off, v = m.group(1), int(m.group(2), 16), int(m.group(3), 16), int(m.group(4), 16)
    if off == 0xFD and be == 0:
        wr = v >> 31; n = ((v >> 13) & 0x3F) + 1; lba = v & 0x1FFF
        out.append(f"\n  SD {'write' if wr else 'read'} lba {lba} x{n}"); continue
    if off == 0xF4 and be == 4:
        b = (v >> 16) & 0xFF
        out.append(f"{'>' if rw == 'W' else '<'}{b:02X}"); continue
    base = 0x480 if off == 0x48 else off
    for k in range(4):
        if be & (8 >> k):
            port = base + k
            out.append(f"[{DMA.get(port, hex(port))}={(v >> (24 - 8*k)) & 0xFF:02X}]")
s = ' '.join(out)
s = re.sub(r'(P00007364-300 ?)+', '', s)
print(s)
