# ukey.py KEY [KEY...] (KEY*N repeated, KEY~N held N/10 s; m:dx,dy and click the mouse): press keys on the MiSTer through a uinput keyboard (instant, no Remote service); S-<key> holds Shift, C-<key> Ctrl, A-<key> Alt, W-<key> Win (W-f12: the MiSTer's menu)
import fcntl, os, struct, sys, time
CODES = {'esc':1,'enter':28,'up':103,'down':108,'left':105,'right':106,'space':57,'tab':15,'backspace':14,
         'minus':12,'period':52,'slash':53,'comma':51,'backslash':43,'semicolon':39,'equal':13,'quote':40,
         'lbracket':26,'rbracket':27,'grave':41,'pgup':104,'pgdn':109,'home':102,'delete':111,'end':107,'f11':87,'f12':88,
         **{'f%d' % i:58 + i for i in range(1, 11)},
         **{c:k for c,k in zip('qwertyuiop',range(16,26))}, **{c:k for c,k in zip('asdfghjkl',range(30,39))},
         **{c:k for c,k in zip('zxcvbnm',range(44,51))}, **{str(i):(i+1 if i else 11) for i in range(10)}}
fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
fcntl.ioctl(fd, 0x40045564, 1)                      # UI_SET_EVBIT EV_KEY
fcntl.ioctl(fd, 0x40045564, 2)                      # UI_SET_EVBIT EV_REL (the mouse: m:dx,dy and click)
for r in (0, 1): fcntl.ioctl(fd, 0x40045566, r)     # UI_SET_RELBIT REL_X, REL_Y
fcntl.ioctl(fd, 0x40045565, 272)                    # BTN_LEFT
for k in range(1, 128): fcntl.ioctl(fd, 0x40045565, k)  # UI_SET_KEYBIT (125: the left Win key)
os.write(fd, struct.pack('80sHHHHi', b'ukey', 3, 1, 1, 1, 0) + b'\0' * (64 * 4 * 4))
fcntl.ioctl(fd, 0x5501)                             # UI_DEV_CREATE
time.sleep(1.0)                                     # let Main open the new device
def ev(t, c, v): os.write(fd, struct.pack('llHHi', 0, 0, t, c, v))
for a in sys.argv[1:]:
    if a.startswith('m:'):                          # m:dx,dy: the mouse moved, in steps of at most 2
        dx, dy = (int(v) for v in a[2:].split(','))
        while dx or dy:
            sx, sy = max(-2, min(2, dx)), max(-2, min(2, dy))   # small steps: no pointer acceleration
            ev(2, 0, sx); ev(2, 1, sy); ev(0, 0, 0); dx -= sx; dy -= sy; time.sleep(0.01)
        time.sleep(0.2); continue
    if a == 'click':
        ev(1, 272, 1); ev(0, 0, 0); time.sleep(0.1); ev(1, 272, 0); ev(0, 0, 0); time.sleep(0.3); continue
    a, _, hold = a.partition('~')                   # key~N: held N tenths of a second (typematic tests)
    n, _, rep = a.partition('*')
    mods = []                                       # S-<key> Shift (S-2 is @), C-<key> Ctrl, A-<key> Alt, W-<key> Win (W-f12: the MiSTer's menu); stacked: C-A-delete
    while len(n) > 2 and n[:2] in ('S-', 'C-', 'A-', 'W-'):
        mods.append({'S-': 42, 'C-': 29, 'A-': 56, 'W-': 125}[n[:2]]); n = n[2:]
    for _ in range(int(rep or 1)):
        k = CODES[n.lower()]
        for m in mods: ev(1, m, 1); ev(0, 0, 0); time.sleep(0.03)
        ev(1, k, 1); ev(0, 0, 0); time.sleep(int(hold) / 10 if hold else 0.05); ev(1, k, 0); ev(0, 0, 0)
        for m in reversed(mods): time.sleep(0.03); ev(1, m, 0); ev(0, 0, 0)
        time.sleep(0.25)
time.sleep(0.3)
fcntl.ioctl(fd, 0x5502)                             # UI_DEV_DESTROY
