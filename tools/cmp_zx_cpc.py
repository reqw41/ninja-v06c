#!/usr/bin/env python3
"""Side-by-side disassembly ZX vs CPC: cmp_zx_cpc.py ZX_ADDR CPC_ADDR COUNT (hex, hex, dec).
Needs build/zx/ram4000.bin (tools/build_skool.py) and build/cpc/... (tools/cpc_dsk.py)."""
import sys
from skoolkit.traceutils import disassemble
def load(path, base):
    m=[0]*65536; d=open(path,'rb').read(); m[base:base+len(d)]=d; return m
z=load('build/zx/ram4000.bin',0x4000); c=load('build/cpc/Ninja__UK___1987___Version_MT0015_/NINJA3.BIN.body',0x40)
za,ca,n=(int(x,16) for x in sys.argv[1:4])
lines=[]
for _ in range(n):
    zt,zl=disassemble(z,za); ct,cl=disassemble(c,ca)
    zb=''.join(f'{z[za+i]:02X}' for i in range(zl)); cb=''.join(f'{c[ca+i]:02X}' for i in range(cl))
    mark=' ' if zb[:2]==cb[:2] else '*'
    print(f'{mark} {za:04X} {zb:8s} {zt:20s} | {ca:04X} {cb:8s} {ct}')
    za+=zl; ca+=cl
