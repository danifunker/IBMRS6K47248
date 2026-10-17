import struct
B=open('/home/dani/repos/IBMRS6K42p/firmware/images/7248_v1.12_main_ram_image_at_00000000.bin','rb').read()
MB=0x58f1c; S=0x5f014
w=lambda a: struct.unpack('>I',B[a:a+4])[0]
hx=lambda a,n: ' '.join('%02x'%c for c in B[a:a+n])
idx=[]; a=S+271
while B[a]: idx.append(B[a]); a+=1
print('ext CR index list:',' '.join('%02x'%i for i in idx))
def sdac(m,n):
    return 14.31818*((m&0x7f)+2)/(((n&0x1f)+2)*(1<<((n>>5)&3)))
for name,off in [('0x201',760),('0x205',1528),('0x211',932),('0x107',2660),('0x274',3392),('0x117',1808),('0x220',1104),('0x222',1980),('0x21a',2940),('0x21b',3004),('0x275',3456)]:
    d=S+off; P=MB+w(d+4)
    print('== mode %s desc@%x hdr=%s P@%x: H=%d W=%d misc=%s SR1-4=%s AR10-14=%s GR0-8=%s'%(name,d,hx(d,16),P,
          struct.unpack('>H',B[P:P+2])[0],struct.unpack('>H',B[P+2:P+4])[0],hx(P+8,4),hx(P+20,4),hx(P+40,5),hx(P+45,9)))
    seen={}
    for mon in range(4):
        tp=d+48+mon*4; T=MB+w(tp)
        crt=MB+w(T); ext=MB+w(T+4); lst=MB+w(T+8)
        lb=[]; a=lst
        while B[a]!=0 and len(lb)<40: lb.append('CR%02x=%02x'%(B[a],B[a+1])); a+=2
        key=(T)
        if key in seen: print('   mon%d same as mon%d'%(mon,seen[key])); continue
        seen[key]=mon
        e=' '.join('CR%02x=%02x'%(i,B[ext+k]) for k,i in enumerate(idx))
        dac=B[T+12:T+15]
        print('   mon%d T@%x CR00-18: %s\n      ext: %s\n      list: %s\n      SDAC cmd=%02x M=%02x N=%02x -> %.2f MHz'%(mon,T,hx(crt,25),e,' '.join(lb),dac[0],dac[1],dac[2],sdac(dac[1],dac[2])))
print('monitor map table @%x:'%(S+3524)); 
for r in range(16): print('  xor=%x:'%r, hx(S+3524+16*r,16))
