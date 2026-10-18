# a whole-image disassembly with capstone, labelled from a tbtab.py symbol list, branch targets named
# usage: capdis.py IMAGE VMA SYMS OUT
import sys, re, bisect, capstone
img=open(sys.argv[1],'rb').read(); vma=int(sys.argv[2],0)
syms={}
for l in open(sys.argv[3]):
    f=l.split()
    if len(f)==3 and f[0]!='????????': syms.setdefault(int(f[0],16),f[2])
keys=sorted(syms)
def nm(a):
    if a in syms: return syms[a]
    i=bisect.bisect_right(keys,a)-1
    return '%s+%x'%(syms[keys[i]],a-keys[i]) if i>=0 and a-keys[i]<0x10000 else None
md=capstone.Cs(capstone.CS_ARCH_PPC, capstone.CS_MODE_32|capstone.CS_MODE_BIG_ENDIAN)
with open(sys.argv[4],'w') as o:
    for off in range(0,len(img)-3,4):
        a=vma+off
        if a in syms: o.write('\n%08x <%s>:\n'%(a,syms[a]))
        w=img[off:off+4]
        ins=list(md.disasm(w,a))
        if ins:
            t='%s %s'%(ins[0].mnemonic,ins[0].op_str)
            m=re.search(r'0x([0-9a-f]+)$',t)
            if m and ins[0].mnemonic.startswith('b'):
                n=nm(int(m.group(1),16))
                if n: t+='  <%s>'%n
        else: t='.long 0x%s'%w.hex()
        o.write('%08x:  %s  %s\n'%(a,w.hex(),t))
