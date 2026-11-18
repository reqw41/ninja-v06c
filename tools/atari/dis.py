#!/usr/bin/env python3
"""Disassemble a 64K Atari memory dump: dis.py MEM.bin START-END ... (hex)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from disasm6502 import disasm_range
mem = open(sys.argv[1], 'rb').read()
for r in sys.argv[2:]:
    a, b = (int(x, 16) for x in r.split('-'))
    for line in disasm_range(lambda x: mem[x & 0xFFFF], a, b):
        print(line)
    print()
