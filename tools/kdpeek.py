#!/usr/bin/env python3
# kdpeek.py: a minimal NT 4 kernel-debugger (KD) client for the 7248 core's COM1, run on the MiSTer
# (python3, standard library only). It acknowledges the kernel's state-change packet, then sends
# small manipulate-state requests (GetVersion, ReadVirtualMemory) and prints the replies. Kept to
# small replies on purpose: the board's ttyS1 loses bytes in bursts longer than ~190 bytes.
#
#   stty -F /dev/ttyS1 19200 raw -echo
#   python3 kdpeek.py version
#   python3 kdpeek.py read 800C4CD0 20 [read ADDR LEN ...]
import os, select, struct, sys, time

DEV = os.environ.get('KDDEV', '/dev/ttyS1')
LEAD_DATA, LEAD_CTRL = 0x30303030, 0x69696969
T_STATE, T_MANIP, T_DEBUGIO, T_ACK, T_RESEND, T_RESET = 1, 2, 3, 4, 5, 6
API_READ, API_GETVER = 0x3130, 0x3146
MHDR = int(os.environ.get('KDMHDR', '56'))      # bytes sent as DBGKD_MANIPULATE_STATE

fd = os.open(DEV, os.O_RDWR | os.O_NOCTTY)
buf = bytearray()

def fill(t):
	r, _, _ = select.select([fd], [], [], t)
	if r: buf.extend(os.read(fd, 4096))

def packet(timeout, body=True):
	"""the next packet: (leader, type, pid, data or None, ok); body False: the header alone for data packets"""
	end = time.time() + timeout
	while time.time() < end:
		for lead in (b'0000', b'iiii'):
			i = buf.find(lead)
			if i >= 0 and len(buf) >= i + 16:
				ld, ty, n, pid, ck = struct.unpack_from('<IHHII', buf, i)
				if ld == LEAD_CTRL:
					del buf[:i + 16]
					return ld, ty, pid, None, True
				if n > 4096:
					del buf[:i + 4]; continue
				if not body:
					del buf[:i + 16]
					return ld, ty, pid, None, False
				while len(buf) < i + 16 + n + 1 and time.time() < end: fill(0.05)
				d = bytes(buf[i + 16:i + 16 + n])
				del buf[:i + 16 + n]
				return ld, ty, pid, d, (sum(d) & 0xffffffff) == ck and len(d) == n
		fill(0.05)
	return None

def quiet(gap=0.15, limit=3):
	"""wait until nothing has arrived for gap seconds (the kernel has finished sending: ttyS1 hands bytes over in 64-byte lumps up to ~110 ms apart)"""
	end = time.time() + limit
	while time.time() < end:
		r, _, _ = select.select([fd], [], [], gap)
		if not r: return
		buf.extend(os.read(fd, 4096))

def ctrl(ty, pid):
	os.write(fd, struct.pack('<IHHII', LEAD_CTRL, ty, 0, pid, 0))

def data(ty, pid, d):
	os.write(fd, struct.pack('<IHHII', LEAD_DATA, ty, len(d), pid, sum(d) & 0xffffffff) + d + b'\xaa')

# 1. reset the protocol (the kernel resends its state change, ids from the start), catch it, acknowledge it
ctrl(T_RESET, 0)
pid_rx = None
while pid_rx is None:
	p = packet(10, False)
	if p is None: sys.exit('no packet from the kernel')
	ld, ty, pid, d, ok = p
	print('kernel: lead %08x type %d id %08x ok %s' % (ld, ty, pid, ok))
	if ld == LEAD_DATA and ty == T_STATE:
		pid_rx = pid
quiet()
buf.clear()
ctrl(T_ACK, pid_rx)
time.sleep(0.2)

# 2. the requests
next_id = 0x80800000
def request(api, body):
	global next_id
	msg = struct.pack('<IHHI', api, 0, 0, 0) + body
	msg = msg + bytes(MHDR - len(msg))
	data(T_MANIP, next_id, msg)
	resends = 0
	while resends < 8:
		p = packet(4)
		if p is None:
			# (our request lost: the kernel asks for nothing, so send it again; a duplicate id is acked and ignored)
			print('  silence, sending the request again'); data(T_MANIP, next_id, msg); resends += 1; continue
		ld, ty, pid, d, ok = p
		if ld == LEAD_CTRL:
			print('  ctrl type %d id %08x' % (ty, pid))
			if ty == T_RESEND: data(T_MANIP, next_id, msg)
			continue
		quiet(); buf.clear()
		if ty == T_MANIP and ok:
			ctrl(T_ACK, pid)
			next_id ^= 1
			return d
		if ty == T_MANIP:
			# a damaged reply: not acknowledged, the kernel sends it again
			print('  reply damaged (%d bytes: %s), resend' % (len(d), d.hex(' ', 4)))
			ctrl(T_RESEND, 0); resends += 1
			continue
		print('  other packet type %d id %08x (acked)' % (ty, pid))
		ctrl(T_ACK, pid)
	sys.exit('no reply')

args = sys.argv[1:]
while args:
	a = args.pop(0)
	if a == 'version':
		d = request(API_GETVER, b'')
		print('reply %d bytes: %s' % (len(d), d.hex(' ', 4)))
		mj, mn, pv, fl, kb, plm, mt = struct.unpack_from('<HHHHIIH', d, 12)
		print('version %d.%d protocol %d flags %x kernbase %08x PsLoadedModuleList %08x machine %x' % (mj, mn, pv, fl, kb, plm, mt))
	elif a == 'mods':
		# PsLoadedModuleList (from GetVersion), each LDR_DATA_TABLE_ENTRY: links, DllBase 18, SizeOfImage 20,
		# BaseDllName 2C
		d = request(API_GETVER, b'')
		head = struct.unpack_from('<I', d, 24)[0]
		def rd(addr, n):
			r = request(API_READ, struct.pack('<III', addr, n, 0))
			got = struct.unpack_from('<I', r, 20)[0]
			return r[len(r) - got:]
		e = struct.unpack_from('<I', rd(head, 4), 0)[0]
		while e != head:
			ent = rd(e, 0x34)
			base, size = struct.unpack_from('<II', ent, 0x18)
			ln, mx, nb = struct.unpack_from('<HHI', ent, 0x2C)
			name = rd(nb, min(ln, 64)).decode('utf-16le', 'replace')
			print('  %08x %08x %s' % (base, size, name))
			e = struct.unpack_from('<I', ent, 0)[0]
	elif a == 'read':
		addr = int(args.pop(0), 16); n = int(args.pop(0), 0)
		d = request(API_READ, struct.pack('<III', addr, n, 0))
		st, = struct.unpack_from('<I', d, 8)
		got, = struct.unpack_from('<I', d, 20)
		body = d[len(d) - got:] if got else b''
		print('read %08x: status %08x, %d bytes (reply header %d)' % (addr, st, got, len(d) - got))
		for o in range(0, len(body), 16):
			print('  %08x %s' % (addr + o, ' '.join('%08x' % w for w in struct.unpack_from('<%dI' % (min(16, len(body) - o) // 4), body, o))))
