import sys
from skoolkit.snapshot import Snapshot
from skoolkit.traceutils import disassemble
mem=[0]*16384+list(Snapshot.get(sys.argv[1]).ram(-1))
hist={}
for l in open(sys.argv[2]):
    a,n=l.split()[:2]; hist[int(a,16)]=int(n)
for r in sys.argv[3:]:
    s,e=(int(x,16) for x in r.split('-'))
    a=s
    while a<=e:
        t,n=disassemble(mem,a)
        print(f'{a:04X} {"".join(f"{mem[a+i]:02X}" for i in range(n)):8s} {t:22s} {hist.get(a,"")}')
        a+=n
    print()
