import struct,sys,re
R='/home/dani/repos/IBMRS6K42p/firmware/'
B=open(R+'images/7248_v1.12_main_ram_image_at_00000000.bin','rb').read()
w=lambda a: struct.unpack('>I',B[a:a+4])[0]
syms={}
for l in open(R+'disasm/symbols_v1.12_ram.txt'):
    p=l.split()
    if len(p)>=3: syms[int(p[0],16)]=p[2]
svc={}
for off in range(0,0x400,4):
    p=w(0xf83d8+off)
    if 0<p<len(B)-4: svc[off]=syms.get(w(p),'svc%d'%off)
MB=int(sys.argv[1],16); TOC=int(sys.argv[2],16); lo=int(sys.argv[3],16); hi=int(sys.argv[4],16)
def tocref(n):
    v=w(TOC+n); a=MB+v
    s=''
    if a<len(B):
        bs=B[a:a+40]; t=bs.split(b'\0')[0]
        if len(t)>=3 and all(32<=c<127 for c in t): s=' "%s"'%t.decode()
    return 'TOC+%d -> D_%05x%s'%(n,a,s)
const={}
sv={}
lines=open(R+'disasm/v1.12_ram_image_00000000.annotated.s').read().split('\n')
pend=None
for l in lines:
    m=re.match(r'^([0-9a-f]{8}):\s+(?:[0-9a-f]{2} ){4}\s*(\S+)\s*(.*)$',l)
    if not m:
        if re.match(r'^[0-9a-f]{8} <',l): const={}; sv.clear()
        print(l); continue
    a=int(m.group(1),16)
    if a<lo or a>=hi: continue
    op,args=m.group(2),m.group(3)
    note=''
    ar=[x.strip() for x in args.split(',')]
    def setc(r,v):
        if v is None: const.pop(r,None)
        else: const[r]=v&0xffffffff
    def imm(s):
        try: return int(s,0)
        except: return None
    mm=re.match(r'(-?\d+)\((r\d+)\)',ar[-1]) if ar else None
    if op in('addi','mr') and ar[1] in sv and (op=='mr' or ar[2]=='0'): sv[ar[0]]=sv[ar[1]]
    if op=='li': setc(ar[0],imm(ar[1]))
    elif op=='lis': setc(ar[0],(imm(ar[1]) or 0)<<16)
    elif op in('addi','addic','addic.') and ar[1] in const: setc(ar[0],const[ar[1]]+imm(ar[2]))
    elif op in('ori','oris') and ar[1] in const: setc(ar[0],const[ar[1]]|(imm(ar[2])<<(16 if op=='oris' else 0)))
    elif op=='mr' and ar[1] in const: setc(ar[0],const[ar[1]])
    elif op=='lwz' and mm and mm.group(2)=='r2':
        note=tocref(int(mm.group(1))); setc(ar[0],None)
    elif op=='lwzu' and mm and int(mm.group(1)) in svc:
        pend=svc[int(mm.group(1))]; sv[ar[0]]=pend; setc(ar[0],None)
    elif op=='bl':
        t=int(ar[0].split()[0],16)
        if t==0x59490 or (pend and t<hi and t>=lo and w(t)==0x800b0000):
            argsd=[('%s=%s'%(r,hex(const[r])) if r in const else r+'=?') for r in('r3','r4','r5')]
            note='SVC %s(%s)'%(sv.get('r11',pend),', '.join(argsd)); pend=None
        else:
            argsd=[('%s=%s'%(r,hex(const[r])) if r in const else r+'=?') for r in('r3','r4','r5','r6')]
            note='call %s(%s)'%(syms.get(t,hex(t)),', '.join(argsd))
        for r in ['r0']+['r%d'%i for i in range(3,13)]: const.pop(r,None); sv.pop(r,None)
    else:
        if ar and re.match(r'r\d+$',ar[0]) and not op.startswith(('st','cmp','b','mt')): setc(ar[0],None)
    print(l[:90]+(('   ; '+note) if note else ''))
