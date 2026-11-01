#!/usr/bin/env python3
# on .92, UART mode None: read the core's debug stream (ttyS1, 115200) and answer OS/2's loader prompts on
# COM1 (its receive line still on ttyS1, at 9600). The DBG_COM1TX build puts COM1's transmitted bytes in the
# stream with bit 7 set: they are split off into LOGFILE.com1, and the prompts are answered from that text,
# as com1auto.py does in Console mode: Enter at "Press ENTER for manual boot", then each "[...]" prompt once
# the line is quiet, with the first rule whose key is in the prompt, else Enter. Everything read goes raw to
# LOGFILE.  dbgauto.py SECONDS LOGFILE [KEY=>REPLY ...]
import os, select, sys, termios, time
fd = os.open('/dev/ttyS1', os.O_RDWR | os.O_NOCTTY)
def speed(b):
    a = termios.tcgetattr(fd)
    a[0] = 0; a[1] = 0; a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL; a[3] = 0
    a[4] = a[5] = b
    a[6][termios.VMIN] = 0; a[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, a)
speed(termios.B115200)
end = time.time() + float(sys.argv[1])
log = open(sys.argv[2], 'ab')
txt = open(sys.argv[2] + '.com1', 'ab')
txt2 = open(sys.argv[2] + '.com2', 'ab')
com2 = False
# a rule FILE@KEY=>REPLY applies only while the last [PN_FILE_NAME="..."] prompt seen named FILE
# the single argument PASSIVE: log only, answer nothing (an unattended boot's test)
passive = sys.argv[3:] == ['PASSIVE']
rules = [] if passive else [a.split('=>', 1) for a in sys.argv[3:]]
# a REPLY of the form A|B|C answers the prompt's first, second, third... occurrence with each in turn (the loader
# asks again after "Unknown device"), the last one from then on
used = {}
lastfile = ''
def say(s):
    speed(termios.B9600); os.write(fd, s.encode()); termios.tcdrain(fd); speed(termios.B115200)
    log.write(('\n<< %r\n' % s).encode()); log.flush()
    print('%s << %r' % (time.strftime('%H:%M:%S'), s), flush=True)
tbuf = b''
last = time.time()
manual = False
nans = 0
while time.time() < end:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        d = os.read(fd, 512)
        log.write(d); log.flush()
        # bit 7 set: COM1's text; a 0x80 byte marks the next such byte as COM2's (LOGFILE.com2)
        t = b''; t2 = b''
        for b in d:
            if b == 0x80: com2 = True
            elif b & 0x80:
                if com2: t2 += bytes([b & 0x7F]); com2 = False
                else: t += bytes([b & 0x7F])
        if t2: txt2.write(t2); txt2.flush()
        if t:
            txt.write(t); txt.flush()
            tbuf = (tbuf + t)[-300:]
            last = time.time()
            if not passive and not manual and b'Press ENTER for manual boot' in tbuf:
                say('\r'); manual = True; tbuf = b''
    elif not passive and tbuf.rstrip().endswith(b']') and time.time() - last > 0.8:
        prompt = tbuf[tbuf.rfind(b'['):].decode('latin1')
        if 'PN_FILE_NAME=' in prompt and not prompt.startswith('[#'): lastfile = prompt
        reply = ''
        for k, v in rules:
            f, _, kk = k.rpartition('@')
            if kk in prompt and (not f or f in lastfile):
                opts = v.split('|')
                reply = opts[min(used.get(k, 0), len(opts) - 1)]
                used[k] = used.get(k, 0) + 1
                break
        say(reply + '\r')
        nans += 1
        tbuf = b''
print('== %d answers' % nans)
