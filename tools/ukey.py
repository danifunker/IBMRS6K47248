# ukey.py KEY [KEY...]: press keys on the MiSTer through a uinput keyboard (instant, no Remote service); S-<key> holds Shift, C-<key> Ctrl
import fcntl, os, struct, sys, time
CODES = {'esc':1,'enter':28,'up':103,'down':108,'left':105,'right':106,'space':57,'tab':15,'backspace':14,
         'minus':12,'period':52,'slash':53,'comma':51,'backslash':43,'semicolon':39,'equal':13,'quote':40,
         'lbracket':26,'rbracket':27,'grave':41,'pgup':104,'pgdn':109,'home':102,'end':107,'f11':87,'f12':88,
         **{'f%d' % i:58 + i for i in range(1, 11)},
         **{c:k for c,k in zip('qwertyuiop',range(16,26))}, **{c:k for c,k in zip('asdfghjkl',range(30,39))},
         **{c:k for c,k in zip('zxcvbnm',range(44,51))}, **{str(i):(i+1 if i else 11) for i in range(10)}}
fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
fcntl.ioctl(fd, 0x40045564, 1)                      # UI_SET_EVBIT EV_KEY
for k in range(1, 120): fcntl.ioctl(fd, 0x40045565, k)  # UI_SET_KEYBIT
os.write(fd, struct.pack('80sHHHHi', b'ukey', 3, 1, 1, 1, 0) + b'\0' * (64 * 4 * 4))
fcntl.ioctl(fd, 0x5501)                             # UI_DEV_CREATE
time.sleep(1.0)                                     # let Main open the new device
def ev(t, c, v): os.write(fd, struct.pack('llHHi', 0, 0, t, c, v))
for a in sys.argv[1:]:
    n, _, rep = a.partition('*')
    mod = 42 if n.startswith('S-') else 29 if n.startswith('C-') else 0   # S-<key> Shift (S-2 is @), C-<key> Ctrl
    sh = mod and len(n) > 2
    if sh: n = n[2:]
    for _ in range(int(rep or 1)):
        k = CODES[n.lower()]
        if sh: ev(1, mod, 1); ev(0, 0, 0); time.sleep(0.03)
        ev(1, k, 1); ev(0, 0, 0); time.sleep(0.05); ev(1, k, 0); ev(0, 0, 0)
        if sh: time.sleep(0.03); ev(1, mod, 0); ev(0, 0, 0)
        time.sleep(0.25)
time.sleep(0.3)
fcntl.ioctl(fd, 0x5502)                             # UI_DEV_DESTROY
