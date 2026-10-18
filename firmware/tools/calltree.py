# the call tree of a bench --calls trace (sim/tb_main.cpp)
# a call tree from a --calls trace: calls nested by the returns, to a depth limit, repeated
# sibling calls collapsed (xN); the firmware's symbols for RAM, mod_XXXXXX for loaded code
# usage: calltree.py TRACE SYMBOLS [MAXDEPTH] [FROM_INSTR] [TO_INSTR]
import sys, re, bisect
syms={}
for l in open(sys.argv[2]):
    m=re.match(r"([0-9a-f]{8})\s+\S+\s+(\w+)", l)
    if m: syms[int(m.group(1),16)]=m.group(2)
keys=sorted(syms)
def name(pc):
    if pc in syms: return syms[pc]
    if pc>=0x1F0000 and pc<0x800000: return 'mod_%06X'%pc
    i=bisect.bisect_right(keys,pc)-1
    return (syms[keys[i]]+'+%X'%(pc-keys[i])) if i>=0 else '%08X'%pc
maxd=int(sys.argv[3]) if len(sys.argv)>3 else 6
lo=int(sys.argv[4]) if len(sys.argv)>4 else 0
hi=int(sys.argv[5]) if len(sys.argv)>5 else 1<<62
stack=[]   # return addresses
last=[None]*64; cnt=[0]*64
out=sys.stdout
def flush(d):
    if last[d] is not None and cnt[d]>1: out.write('%s  (x%d)\n'%('  '*d, cnt[d]))
for l in open(sys.argv[1]):
    if l[:2]=='C ':
        _,t,c,n=l.split(); t=int(t,16); c=int(c,16); n=int(n)
        d=len(stack)
        stack.append(c+4)
        if len(stack)>200: stack=stack[-100:]
        if n<lo or n>hi or d>maxd: continue
        nm=name(t)
        if last[d]==nm: cnt[d]+=1
        else:
            flush(d); last[d]=nm; cnt[d]=1
            out.write('%s%s  @%d from %s\n'%('  '*d, nm, n, name(c)))
        for k in range(d+1,64): last[k]=None
    elif l[:2]=='R ':
        r=int(l[2:10],16)
        # pop to the matching return address (longjmp-like returns pop several)
        if r in stack:
            while stack and stack[-1]!=r: stack.pop()
            if stack: stack.pop()
    elif l.startswith('  progress'):
        out.write('%s## %s\n'%('  '*len(stack), l.strip()))
