#!/usr/bin/env python3
"""Disassemble CPC NINJA3.BIN ranges: dis_cpc.py START-END ... (hex). Needs tools/cpc_dsk.py output."""
import sys
from skoolkit.traceutils import disassemble
m=[0]*65536; d=open('build/cpc/Ninja__UK___1987___Version_MT0015_/NINJA3.BIN.body','rb').read(); m[0x40:0x40+len(d)]=d
for r in sys.argv[1:]:
    a,e=(int(x,16) for x in r.split('-'))
    while a<=e:
        t,n=disassemble(m,a); print(f'{a:04X} {"".join(f"{m[a+i]:02X}" for i in range(n)):8s} {t}'); a+=n
    print()
