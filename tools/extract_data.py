#!/usr/bin/env python3
"""Extract Ninja (ZX) game data from the verified RAM image.

  tools/.venv/bin/python tools/extract_data.py [--check build/rooms_rt]

Reads build/zx/ram4000.bin (tools/build_skool.py) and writes data/:
  tiles.bin         TILE_GFX: 8 bytes per tile, ZX bit order (bit 7 = left)
  tile_attr.bin     ZX attribute per tile (table $E37E, BRIGHT added at draw time)
  rooms/rNN.map     672 tile ids (21 rows x 32), as the game builds TILE_MAP $8AB7
  rooms/rNN.attr    672 attributes (before holes/idol/HUD)
  rooms.json        stream addresses, holes, names, recolour rules
  frames/fNNN.bin   fighter frame: h, w, then w*h sprite bytes; mask in fNNN.mask
  frames.json       frame table
  png/              tiles sheet, every room, every frame (for viewing)

With --check DIR it compares rooms/rNN.map with runtime dumps DIR/rN/dump_EB30.bin
(TILE_MAP right after the floor is drawn) and attributes with dump_ED23.bin.
"""
import argparse
import json
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
RAM = open(os.path.join(ROOT, 'build', 'zx', 'ram4000.bin'), 'rb').read()


def m(a):
    return RAM[a - 0x4000]


def w(a):
    return m(a) | m(a + 1) << 8


TILE_GFX = 0xD00C
TILE_ATTR = 0xE37E
ROOM_STREAMS = 0xD9DE
FLOOR_STREAM = 0x7808
RECOLOUR_ROOMS, RECOLOUR_ROWS, RECOLOUR_PTRS = 0xEB56, 0xEB50, 0xEB5C
HOLES = 0xDBB5
FRAME_TABLE = 0xDA0C
MASK_OFFSET = 0x2140
NROOMS = 21


def decode_stream(ptr, col, count, start, tmap, attr):
    """DRAW_ROOM_STREAM ($F64C): rows of 40 columns, columns 4..35 visible.
    Byte t = one tile; $FF t n = tile t repeated n+1 times. Stops after
    `count` visible cells. Returns the pointer after the last byte read."""
    pos = start

    def put(t):
        nonlocal col, pos, count
        col += 1
        if col >= 40:
            col = 0
            return
        if 4 <= col < 36:
            tmap[pos] = t
            attr[pos] = m(TILE_ATTR + t) | 0x40
            pos += 1
            count -= 1

    while count:
        t = m(ptr)
        ptr += 1
        if t != 0xFF:
            put(t)
            continue
        t, n = m(ptr), m(ptr + 1)
        ptr += 2
        for _ in range(n + 1):
            put(t)
            if not count:
                break
    return ptr


NEIGHBOURS = 0xD897      # per room: left, right, up, down as room+1 (0 = no exit)
TILE25_ROOMS = 0xF694    # 5 rooms where tile $25 gets attribute $2C instead of $2A
WALL_LEFT, WALL_RIGHT = 0x8134, 0x8158   # 4 x 15 tile blocks, source rows 40 wide


def tile_attr_table(r):
    """Tile attributes as ENTER_ROOM leaves them for room r ($F800, $EABC)."""
    t = list(RAM[TILE_ATTR - 0x4000:TILE_ATTR - 0x4000 + 256])
    t[0x25] = 0x2C if r in [m(TILE25_ROOMS + i) for i in range(5)] else 0x2A
    t[0xA0] = 0x30 if r == 1 else 0x28
    return t


def tile_gfx(t, r):
    """Tile $A0 is blank in room 1, a copy of tile $9C elsewhere ($EABC)."""
    if t == 0xA0:
        if r == 1:
            return [0] * 8
        t = 0x9C
    return [m(TILE_GFX + 8 * t + y) for y in range(8)]


def decode_stream(ptr, col, count, start, tmap, attr, at):
    """DRAW_ROOM_STREAM ($F64C): rows of 40 columns, columns 4..35 visible.
    Byte t = one tile; $FF t n = tile t repeated n+1 times. Stops after
    `count` visible cells. Returns the pointer after the last byte read."""
    pos = start

    def put(t):
        nonlocal col, pos, count
        col += 1
        if col >= 40:
            col = 0
            return
        if 4 <= col < 36:
            tmap[pos] = t
            attr[pos] = at[t] | 0x40
            pos += 1
            count -= 1

    while count:
        t = m(ptr)
        ptr += 1
        if t != 0xFF:
            put(t)
            continue
        t, n = m(ptr), m(ptr + 1)
        ptr += 2
        for _ in range(n + 1):
            put(t)
            if not count:
                break
    return ptr


def neighbours(r):
    return [m(NEIGHBOURS + 4 * r + i) - 1 for i in range(4)]   # -1 = none


def build_room(r):
    """Tile map and attributes exactly as the game leaves them when the main loop
    starts in room r (pixels of holes and idol are drawn separately, not as tiles)."""
    at = tile_attr_table(r)
    tmap = [0] * 672
    attr = [0] * 672
    sp = w(ROOM_STREAMS + 2 * r)
    end = decode_stream(sp, 0x27, 0x1E0, 0, tmap, attr, at)
    rec = None
    for i in range(6):                       # $EB68
        if m(RECOLOUR_ROOMS + i) == r:
            j = 5 - i                        # B left by DJNZ = 6-i, table index B-1
            rows, a0 = m(RECOLOUR_ROWS + j), w(RECOLOUR_PTRS + 2 * j)
            rec = {'rows': rows, 'attr_addr': f'${a0:04X}'}
            o = a0 - 0x5800
            for k in range(o, o + 32 * rows):
                if 0x68 <= attr[k] < 0x70:
                    attr[k] = (attr[k] | 0x08) & ~0x30
    fend = decode_stream(FLOOR_STREAM, 0x1B, 0xC8, 0x1D8, tmap, attr, at)
    nb = neighbours(r)
    walls = []
    for side, src, col in ((0, WALL_LEFT, 0), (1, WALL_RIGHT, 28)):   # $F107
        if nb[side] < 0:
            walls.append('left' if side == 0 else 'right')
            for y in range(15):
                for x in range(4):
                    t = m(src + 40 * y + x)
                    k = (2 + y) * 32 + col + x
                    tmap[k] = t
                    attr[k] = at[t] | 0x40
    if r == 0:                               # $F817 rainbow: rows 4..10, paper 1..7
        for y in range(7):
            for x in range(32):
                k = (4 + y) * 32 + x
                attr[k] = (attr[k] & 0xC7) + 8 * (y + 1)
    if r in (19, 20):                        # $FF48 door block 8x8 at row 5 col 12
        for y in range(8):
            for x in range(8):
                attr[(5 + y) * 32 + 12 + x] = 0x50 if r == 19 else 0x60
    return tmap, attr, {'stream': f'${sp:04X}', 'stream_end': f'${end:04X}',
                        'floor_end': f'${fend:04X}', 'recolour': rec, 'walls': walls,
                        'exits': dict(zip(('left', 'right', 'up', 'down'), [x if x >= 0 else None for x in nb])),
                        'hole_ceiling_x': m(HOLES + 2 * r), 'hole_floor_x': m(HOLES + 2 * r + 1)}


# ---- PNG helpers (Pillow from tools/.venv) ----
ZX = [(0, 0, 0), (0, 0, 205), (205, 0, 0), (205, 0, 205), (0, 205, 0), (0, 205, 205), (205, 205, 0), (205, 205, 205)]
ZXB = [(0, 0, 0), (0, 0, 255), (255, 0, 0), (255, 0, 255), (0, 255, 0), (0, 255, 255), (255, 255, 0), (255, 255, 255)]


def tile_img(t, a, img, x0, y0, r=None):
    pal = ZXB if a & 0x40 else ZX
    ink, paper = pal[a & 7], pal[(a >> 3) & 7]
    g = tile_gfx(t, r) if r is not None else [m(TILE_GFX + 8 * t + y) for y in range(8)]
    for y in range(8):
        row = g[y]
        for x in range(8):
            img.putpixel((x0 + x, y0 + y), ink if row & (0x80 >> x) else paper)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', help='dir with runtime dumps rN/dump_EB30.bin, dump_ED23.bin')
    a = ap.parse_args()
    from PIL import Image
    out = os.path.join(ROOT, 'data')
    for d in ('rooms', 'frames', 'png'):
        os.makedirs(os.path.join(out, d), exist_ok=True)

    rooms = {}
    used = set()
    ok = True
    names = room_names()
    for r in range(NROOMS):
        tmap, attr, info = build_room(r)
        info['name'] = names.get(r)
        rooms[r] = info
        used |= set(tmap)
        open(os.path.join(out, 'rooms', f'r{r:02d}.map'), 'wb').write(bytes(tmap))
        open(os.path.join(out, 'rooms', f'r{r:02d}.attr'), 'wb').write(bytes(attr))
        img = Image.new('RGB', (256, 168))
        for i, t in enumerate(tmap):
            tile_img(t, attr[i], img, 8 * (i % 32), 8 * (i // 32), r)
        img.save(os.path.join(out, 'png', f'room{r:02d}.png'))
        if a.check:
            scr = open(os.path.join(a.check, f'r{r}', 'dump_ED23.bin'), 'rb').read()
            rt = scr[0x8AB7 - 0x4000:0x8AB7 - 0x4000 + 672]
            rattr = scr[0x1800:0x1800 + 672]
            dm = sum(1 for i in range(672) if rt[i] != tmap[i])
            da = [i for i in range(672) if rattr[i] != attr[i]]
            # pixels: back buffer ($5B00) holds the room as built, before actors/holes
            dp = 0
            for i in range(672):
                row, col = divmod(i, 32)
                g = tile_gfx(tmap[i], r)
                for y in range(8):
                    sa = ((row & 0x18) << 8) | ((row & 7) << 5) | (y << 8) | col
                    if scr[0x1B00 + sa] != g[y]:
                        dp += 1
                        break
            info['check'] = {'map_diff': dm, 'attr_diff': len(da), 'pixel_cells_diff': dp}
            print(f'room {r:2d} {str(info["name"]):22s} stream {info["stream"]} map diff {dm:3d}  attr diff {len(da):3d}  pixel cells diff {dp:3d}'
                  + (f' (first at row {da[0] // 32} col {da[0] % 32})' if da else ''))
            ok &= dm == 0 and not da

    ntiles = max(used) + 1
    open(os.path.join(out, 'tiles.bin'), 'wb').write(RAM[TILE_GFX - 0x4000:TILE_GFX - 0x4000 + 8 * ntiles])
    open(os.path.join(out, 'tile_attr.bin'), 'wb').write(RAM[TILE_ATTR - 0x4000:TILE_ATTR - 0x4000 + ntiles])
    sheet = Image.new('RGB', (16 * 9, ((ntiles + 15) // 16) * 9), (60, 60, 60))
    for t in range(ntiles):
        tile_img(t, m(TILE_ATTR + t) | 0x40, sheet, 9 * (t % 16), 9 * (t // 16))
    sheet = sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST)
    sheet.save(os.path.join(out, 'png', 'tiles.png'))

    frames = []
    i = 0
    while True:
        p = w(FRAME_TABLE + 2 * i)
        if not 0x8000 <= p < 0xB000:
            break
        h, wd = m(p), m(p + 1)
        if not (0 < h <= 80 and 0 < wd <= 8):
            break
        data = RAM[p + 2 - 0x4000:p + 2 + h * wd - 0x4000]
        mask = RAM[p + 2 + MASK_OFFSET - 0x4000:p + 2 + MASK_OFFSET + h * wd - 0x4000]
        open(os.path.join(out, 'frames', f'f{i:03d}.bin'), 'wb').write(bytes([h, wd]) + data)
        open(os.path.join(out, 'frames', f'f{i:03d}.mask'), 'wb').write(mask)
        frames.append({'n': i, 'addr': f'${p:04X}', 'h': h, 'w': wd})
        i += 1
    # frame sheet: sprite black on white, mask-transparent shown grey
    cols = 12
    fh = max(f['h'] for f in frames)
    fw = max(f['w'] for f in frames) * 8
    fs = Image.new('RGB', (cols * (fw + 4), ((len(frames) + cols - 1) // cols) * (fh + 4)), (90, 90, 90))
    for f in frames:
        p = int(f['addr'][1:], 16) + 2
        x0, y0 = (f['n'] % cols) * (fw + 4), (f['n'] // cols) * (fh + 4)
        for y in range(f['h']):
            for xb in range(f['w']):
                d = m(p + y * f['w'] + xb)
                mk = m(p + MASK_OFFSET + y * f['w'] + xb)
                for bit in range(8):
                    on, keep = d & (0x80 >> bit), mk & (0x80 >> bit)
                    c = (0, 0, 0) if on else ((150, 150, 150) if keep else (255, 255, 255))
                    fs.putpixel((x0 + 8 * xb + bit, y0 + y), c)
    fs = fs.resize((fs.width * 2, fs.height * 2), Image.NEAREST)
    fs.save(os.path.join(out, 'png', 'frames.png'))

    json.dump({'tiles': ntiles, 'tile_gfx': f'${TILE_GFX:04X}', 'tile_attr': f'${TILE_ATTR:04X}',
               'floor_stream': f'${FLOOR_STREAM:04X}', 'rooms': rooms},
              open(os.path.join(out, 'rooms.json'), 'w'), indent=1, ensure_ascii=False)
    json.dump({'frame_table': f'${FRAME_TABLE:04X}', 'mask_offset': f'${MASK_OFFSET:04X}', 'frames': frames},
              open(os.path.join(out, 'frames.json'), 'w'), indent=1)
    misc = extract_misc(out, Image)
    print(f'tiles {ntiles}, rooms {NROOMS}, frames {len(frames)}, misc {", ".join(misc)}')
    if a.check and not ok:
        raise SystemExit('map mismatch')


MAX_ENEMIES = 0xDA70     # per room: number of enemy slots (E336 fills $DA85 at new game)
ENEMY_NAMES = 0xF61C     # 4 pointers: THUG, KARATEKA, NINJA, HERO
WEAPONS = 0xFF62         # thrown weapons 8x8, 3 glyphs (also HUD markers); $8D57 = other set (IY+4 != 0)
WEAPONS_ALT = 0x8D57
IDOL = 0xFB0A            # 2 bytes x 16 rows, OR-ed onto the screen (FAB3)
HOLE_EDGES_FLOOR, HOLE_EDGES_CEIL = 0xDBDF, 0xDBFF   # 32 bytes each, drawn by $FE4C


def extract_misc(out, Image):
    def cstr(p):
        s = bytearray()
        while m(p):
            s.append(m(p))
            p += 1
        return s.decode('latin1')
    blobs = {
        'weapons.bin': (WEAPONS, 24), 'weapons_alt.bin': (WEAPONS_ALT, 24),
        'idol.bin': (IDOL, 32), 'hole_floor_edges.bin': (HOLE_EDGES_FLOOR, 32),
        'hole_ceiling_edges.bin': (HOLE_EDGES_CEIL, 32),
    }
    for fn, (a, n) in blobs.items():
        open(os.path.join(out, fn), 'wb').write(RAM[a - 0x4000:a - 0x4000 + n])
    info = {
        'enemy_names': [cstr(w(ENEMY_NAMES + 2 * i)) for i in range(4)],
        'max_enemies_per_room': [m(MAX_ENEMIES + r) for r in range(NROOMS)],
        'enemy_rule': ('$E336 at new game and on every up/down move: for each room r, '
                       'n = max_enemies[r] slots; each slot but the last is present with '
                       'probability 191/256 (RANDOM < $BF), the last always; type = random 1..3 '
                       '(1 THUG, 2 KARATEKA, 3 NINJA), stored as $F0+type (energy 15 in the high nibble)'),
        'font': 'ZX ROM character set at $3C00 (not in the game image)',
        'blobs': {k: f'${v[0]:04X}+{v[1]}' for k, v in blobs.items()},
    }
    json.dump(info, open(os.path.join(out, 'misc.json'), 'w'), indent=1)
    # small graphics sheet
    img = Image.new('RGB', (8 * 18, 16), (255, 255, 255))
    def put(a, wbytes, h, x0):
        for y in range(h):
            for xb in range(wbytes):
                v = m(a + y * wbytes + xb)
                for bit in range(8):
                    if v & (0x80 >> bit):
                        img.putpixel((x0 + 8 * xb + bit, y), (0, 0, 0))
    for i in range(3):
        put(WEAPONS + 8 * i, 1, 8, 9 * i)
        put(WEAPONS_ALT + 8 * i, 1, 8, 9 * i + 40)
    put(IDOL, 2, 16, 80)
    put(HOLE_EDGES_FLOOR, 1, 16, 100)
    put(HOLE_EDGES_CEIL, 1, 16, 112)
    img.resize((img.width * 4, img.height * 4), Image.NEAREST).save(os.path.join(out, 'png', 'misc.png'))
    return list(blobs)


def room_names():
    """'APPROACHING <name>' ($FB43): names are 0-terminated strings from $D900 in room
    order; $D8EB+room is a character stored into the message at $DB8E."""
    names, p = {}, 0xD900
    for r in range(NROOMS):
        s = bytearray()
        while m(p):
            s.append(m(p))
            p += 1
        p += 1
        names[r] = s.decode('latin1')
    return names


if __name__ == '__main__':
    main()
