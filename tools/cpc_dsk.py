#!/usr/bin/env python3
"""Extract files from an Amstrad CPC DATA-format DSK (standard or EXTENDED).

  python3 tools/cpc_dsk.py IMAGE.dsk OUTDIR

Writes each file as NAME.EXT (raw, AMSDOS header kept) plus NAME.EXT.body
(header stripped) and prints load/exec addresses from the AMSDOS header.
"""
import os
import sys


def tracks(b):
    ext = b[:8] == b'EXTENDED'
    ntr, nsd = b[0x30], b[0x31]
    off = 0x100
    for t in range(ntr * nsd):
        tsz = b[0x34 + t] * 256 if ext else (b[0x32] | b[0x33] << 8)
        if tsz == 0:
            yield {}
            continue
        tb = b[off:off + tsz]
        ns = tb[0x15]
        secs = {}
        p = 0x100
        for i in range(ns):
            info = tb[0x18 + 8 * i:0x20 + 8 * i]
            sid, n = info[2], info[3]
            ln = (info[6] | info[7] << 8) if ext else (128 << n)
            if ln == 0:
                ln = 128 << n
            secs[sid] = tb[p:p + ln][:128 << n]
            p += ln
        yield secs
        off += tsz


def main():
    img, out = sys.argv[1], sys.argv[2]
    b = open(img, 'rb').read()
    lin = bytearray()
    for secs in tracks(b):
        for sid in range(0xC1, 0xCA):
            lin += secs.get(sid, bytes(512)).ljust(512, b'\0')
    dirb = lin[:2048]
    files = {}
    for i in range(64):
        e = dirb[32 * i:32 * i + 32]
        if e[0] == 0xE5 or e[0] > 15:
            continue
        name = bytes(c & 0x7F for c in e[1:9]).decode('latin1').rstrip()
        ext = bytes(c & 0x7F for c in e[9:12]).decode('latin1').rstrip()
        exn = e[12] + 32 * e[14]
        rc = e[15]
        blocks = [x for x in e[16:32] if x]
        files.setdefault((e[0], name, ext), []).append((exn, rc, blocks))
    os.makedirs(out, exist_ok=True)
    for (user, name, ext), exts in sorted(files.items()):
        data = bytearray()
        for exn, rc, blocks in sorted(exts):
            chunk = bytearray()
            for bl in blocks:
                chunk += lin[bl * 1024:(bl + 1) * 1024]
            data += chunk[:rc * 128]
        fn = f'{name}.{ext}'
        open(os.path.join(out, fn), 'wb').write(data)
        h = data[:128]
        hdr = sum(h[:67]) & 0xFFFF == (h[67] | h[68] << 8) and len(data) >= 128
        if hdr:
            load = h[21] | h[22] << 8
            ln = h[24] | h[25] << 8
            exe = h[26] | h[27] << 8
            typ = h[18]
            body = data[128:128 + ln]
            open(os.path.join(out, fn + '.body'), 'wb').write(body)
            print(f'{fn:14s} user {user} size {len(data):6d} AMSDOS type {typ} load ${load:04X} len ${ln:04X} exec ${exe:04X}')
        else:
            print(f'{fn:14s} user {user} size {len(data):6d} (no AMSDOS header)')


if __name__ == '__main__':
    main()
