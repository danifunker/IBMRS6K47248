# disassemble a firmware module (.6XE/.6XS from the VDISK), functions named from their traceback tables
# disassemble a firmware module file (.6XE/.6XS): functions named from their traceback tables
import sys, re, struct, capstone
d=open(sys.argv[1],'rb').read()
lo=int(sys.argv[2],16) if len(sys.argv)>2 else 0x200
hi=int(sys.argv[3],16) if len(sys.argv)>3 else struct.unpack('>I',d[4:8])[0]
md=capstone.Cs(capstone.CS_ARCH_PPC, capstone.CS_MODE_32|capstone.CS_MODE_BIG_ENDIAN)
# tracebacks: a zero word then 0x00002041-like, the name after a length halfword
names={}; start=0x200
for m in re.finditer(rb'\x00\x00\x00\x00\x00\x00\x20[\x00-\xff]',d):
    o=m.start()
    if o<start or o>=0x4000: continue
    # name: find the halfword length followed by ascii
    seg=d[o+8:o+64]
    mm=re.search(rb'\x00([\x03-\x30])([A-Za-z_][A-Za-z0-9_]+)',seg)
    if mm and len(mm.group(2))==mm.group(1)[0]:
        names[start]=mm.group(2).decode()
        e=o+8+mm.end(); e=(e+3)&~3
        start=e
for a in range(lo,hi,4):
    if a in names: print('\n%05X <%s>:'%(a,names[a]))
    w=d[a:a+4]
    ins=list(md.disasm(w,a))
    print('%05X  %s  %s %s'%(a,w.hex(),ins[0].mnemonic if ins else '.long',ins[0].op_str if ins else ''))
