# the CMOS image the firmware's init_cmos leaves (with the "CMOS was reset" bit 0x20 of 1F clear),
# with valid CRCs over 20-2D (at 2E-2F) and 30-3D (at 3E-3F): the firmware's crcgen, emulated
M=0xFFFFFFFF
rotl=lambda x,n: ((x<<n)|(x>>(32-n)))&M
def crcgen(r3,b):
    r0=b&0xff; r4=rotl(r3,8)&0xFF00; r3=r3>>8; r3^=r0
    r5=((r3<<8)&M)>>12; r6=(r3<<12)&M; r5=(r6|r5)&0xF00F
    r4=r3|r4; r5=r4^r5
    r0=rotl(r3,1)&0x1E0; r4=rotl(r3,5)&0x1FE0; r4^=r5
    r3=rotl(r3,8)&0xF000; return r4^r3^r0
def crc(c,lo,hi):
    v=0xFFFF
    for a in range(lo,hi+1): v=crcgen(v,c[a])
    return v
c=[0]*128
c[0x1A]=0x19                      # init_cmos: the century
for lo,hi,dst in ((0x20,0x2D,0x2E),(0x30,0x3D,0x3E)):
    v=crc(c,lo,hi); c[dst]=v>>8; c[dst+1]=v&0xFF
    assert crc(c,lo,hi+2)==0, hex(crc(c,lo,hi+2))
print(' '.join('%02X'%x for x in c[0x0E:0x40]))
print('2E-2F %02X%02X  3E-3F %02X%02X'%(c[0x2E],c[0x2F],c[0x3E],c[0x3F]))
