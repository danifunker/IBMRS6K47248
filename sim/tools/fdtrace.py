# decode the bench's floppy controller log (machine_tb --io-range 800003F0:800003F7) into byte accesses:
# python3 sim/tools/fdtrace.py run_fd.txt [first [count]]  (runs of identical status reads collapsed; the caller as lr)
import sys, re
NAMES = {0x3F0: 'SRA', 0x3F1: 'SRB', 0x3F2: 'DOR', 0x3F3: 'TDR', 0x3F4: 'MSR/DSR', 0x3F5: 'FIFO', 0x3F7: 'DIR/CCR'}
rx = re.compile(r'io ([RW]) (800003F[0-7]) be ([0-9a-fA-F]+) ([0-9A-F]{8})\s+\(pc ([0-9A-F]+)(?: lr ([0-9A-F]+) instr (\d+))?\)')
ev = []
for line in open(sys.argv[1], encoding='latin1'):
    m = rx.search(line)
    if not m:
        if 'floppy' in line: ev.append(('#', line.strip()))
        continue
    rw, a, be, d, pc = m.group(1), int(m.group(2), 16), int(m.group(3), 16), int(m.group(4), 16), m.group(5)
    if m.group(6): pc = 'lr ' + m.group(6) + ' i' + m.group(7)
    for k in range(4):
        if be & (8 >> k):
            port = (a & 0xFFFF) + k
            ev.append((rw, port, (d >> (24 - 8 * k)) & 0xFF, pc))
first = int(sys.argv[2]) if len(sys.argv) > 2 else 0
count = int(sys.argv[3]) if len(sys.argv) > 3 else 400
# collapse runs of identical MSR polls
out, prev, n = [], None, 0
for e in ev[first:]:
    key = e[:3]
    if key == prev: n += 1; continue
    if prev is not None: out.append((prev, n, pc0))
    prev, n, pc0 = key, 1, e[3] if len(e) > 3 else ''
out.append((prev, n, pc0))
for (e, n, pc) in out[:count]:
    if e[0] == '#': print(e[1]); continue
    rw, port, v = e
    print(f"{rw} {port:03X} {NAMES.get(port, '?'):8s} {v:02X}" + (f"  x{n}" if n > 1 else "") + f"   pc {pc}")
print(len(ev), 'byte accesses,', len(out), 'after collapsing')
