# unix compress (.Z) decoder: unz.py IN OFFSET OUT
import sys
data=open(sys.argv[1],'rb').read()[int(sys.argv[2],0):]
assert data[:2]==b'\x1f\x9d'
maxbits=data[2]&0x1f; block=bool(data[2]&0x80)
pos=3*8; n=9; free=257 if block else 256
tab={i:bytes([i]) for i in range(256)}
out=bytearray(); prev=None
bitlen=len(data)*8
group_start=pos   # codes come in groups of n bytes (8 codes) at width n
while True:
    if pos+n>bitlen: break
    b=pos>>3; w=int.from_bytes(data[b:b+4].ljust(4,b'\0'),'little')
    code=(w>>(pos&7))&((1<<n)-1); pos+=n
    if block and code==256:
        # skip to the end of this group of 8 codes
        used=(pos-group_start)
        grp=n*8
        pos=group_start+((used+grp-1)//grp)*grp
        n=9; free=257; prev=None; group_start=pos   # (compress: the first code after a CLEAR fills a dummy 256)
        tab={i:bytes([i]) for i in range(256)}
        continue
    if code in tab: e=tab[code]
    elif code==free and prev is not None: e=prev+prev[:1]
    else: print('bad code',code,'at',len(out)); break
    out+=e
    if prev is not None and free<(1<<maxbits):
        tab[free]=prev+e[:1]; free+=1
    prev=e
    if free>=(1<<n) and n<maxbits:
        used=pos-group_start; grp=n*8
        pos=group_start+((used+grp-1)//grp)*grp
        n+=1; group_start=pos
open(sys.argv[3],'wb').write(out); print(len(out),'bytes')
