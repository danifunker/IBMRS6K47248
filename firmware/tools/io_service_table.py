import struct,sys
B=open('/home/dani/repos/IBMRS6K42p/firmware/images/7248_v1.12_main_ram_image_at_00000000.bin','rb').read()
syms={}
for l in open('/home/dani/repos/IBMRS6K42p/firmware/disasm/symbols_v1.12_ram.txt'):
    p=l.split()
    if len(p)>=3: syms[int(p[0],16)]=p[2]
w=lambda a: struct.unpack('>I',B[a:a+4])[0]
base=0xf83d8
for off in range(0,0x800,4):
    p=w(base+off)
    if p==0 or p>=len(B): 
        print(hex(off),off,hex(p)); continue
    e=w(p)
    print(off, hex(p), hex(e), syms.get(e,'?'))
