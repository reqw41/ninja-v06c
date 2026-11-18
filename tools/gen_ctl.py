#!/usr/bin/env python3
"""Generate src/ninja.ctl from a traced execution map and the name table below.

  tools/.venv/bin/python tools/gen_ctl.py build/trace/hist/ranges.txt > src/ninja.ctl

Every executed range becomes a 'c' block; everything in between stays 'b'
(not executed during the trace: data, or code paths the trace did not reach).
Names marked (?) are guesses from a quick read and still need checking.
"""
import sys

# address: (label, description)
CODE = {
    0x5CEF: ('POSTLOAD_NOPS', '64 NOPs: the loader RET lands here; falls into JP $D714 (bugfix patch lives here)'),
    0xD714: ('START_TRAMPOLINE', 'JP GAME_START'),
    0xDECA: ('RANDOM', 'Pseudo-random byte in A; 32-bit shift register at RNG_SEED'),
    0xDEFB: ('PRINT_STRING', 'Print 0-terminated string at HL (control codes handled by PRINT_CHAR)'),
    0xDF04: ('PRINT_CHAR', 'Print one character / control code'),
    0xDF47: ('PRINT_STRING_BIG', 'Print string at HL in double height (sets flag $DEF5)'),
    0xDF65: ('DRAW_CHAR8', 'Copy 8 bytes from DE to screen at HL (INC H per row)'),
    0xDF85: ('DRAW_CHAR16', 'Copy 8 bytes from DE doubled vertically (16 screen rows)'),
    0xDFAB: ('SCREEN_ADDR', 'Screen address from character coordinates in B/C'),
    0xDFCA: ('SET_BORDER_ATTR', 'Border = B (also BORDCR), fill attributes with C'),
    0xDFE3: ('CLEAR_SCREEN', 'Zero pixels $4000-$57FF with a PUSH fill (SP=$5800 down to $4000). With interrupts on (bug 1) an interrupt near the end pushes below $4000 into ROM and the game crashes'),
    0xE007: ('NEXT_ROW', 'HL = next screen pixel row (hottest routine: sprite drawing)'),
    0xE01A: ('ADD_HL_A', 'HL += A'),
    0xE1F4: ('READ_CONTROLS', 'Read keys (table at $E021 by control type $E1EC) and Kempston into HERO_INPUT'),
    0xE276: ('WAIT_KEY', 'Delay, then wait for a key via ROM KEY-SCAN ($028E)'),
    0xE2A3: ('MENU_CHOICE', 'Wait for menu digit 0-5, click, return 0-5 in A'),
    0xE2B4: ('TABLE_WORD', 'HL = word at HL + 2*A'),
    0xE2C0: ('CLICK', 'Menu click through ROM BEEPER (bug 1: BEEPER ends with EI)'),
    0xE2D5: ('DRAW_FIELD', 'Tile map $8BF7 -> back buffer (screen+$1B00): 320 cells (rows 10-19); full 672 cells from $8AB7 if $E2D4. Empty cells skipped. ~40% of CPU'),
    0xE336: ('CLEAR_ROOM_TABLES', 'Place enemies in all rooms: MAX_ENEMIES slots, each but last present with p=191/256, random type 1..3 (new game and every up/down move)'),
    0xE4DF: ('TILE_ADDR', 'HL = TILE_GFX + 8 * tile ($E4CB)'),
    0xE4ED: ('NEXT_ROW_SHADOW', 'Advance DE = HL+$1B00 shadow pointer one row with NEXT_ROW'),
    0xE4FC: ('MOVE_ENEMIES', 'For actors 5..1: movement/state from per-actor input bytes (?)'),
    0xE583: ('ANIMATE_ACTORS', 'For actors 5..1: animation via table $E892 (?)'),
    0xE741: ('ACTOR_INPUT', 'A = input byte of current actor ($E8A2) from $E1ED table'),
    0xE74B: ('ACTOR_FIELD8', 'Test field +8 of actor B'),
    0xE757: ('GET_E8A4', 'A = ($E8A4)'),
    0xE7D8: ('SET_ACTOR_INPUT', 'Store A as current actor input ($E1ED+n) and $E899+n'),
    0xE809: ('ACTOR_PTR', 'HL = actor record of current actor ($E8A2)'),
    0xE81C: ('NEG_A', 'A = -A'),
    0xE8AB: ('DRAW_ACTORS', 'Per-tick render: DRAW_FIELD, actor frame setup, masked blit, projectiles, copy to screen, clear rects'),
    0xE8DB: ('ACTOR_FRAMES', 'For 6 actors: frame pointers from $DA0C, screen/buffer addresses from row table $D717'),
    0xE959: ('BLIT_ACTORS', 'Masked sprite blit (AND mask, OR sprite) into back buffer, actors from $E4AC backwards'),
    0xE9B1: ('COPY_ACTORS_TO_SCREEN', 'Copy each actor rectangle 7 bytes x 60 (66) rows from back buffer to screen with LDI'),
    0xEA0B: ('CLEAR_ACTOR_RECTS', 'Zero actor rectangles 7 x 60 in back buffer (redrawn by DRAW_FIELD next tick)'),
    0xF925: ('ROOM_TRANSITION', 'Room change effect, 50 steps drawing from $DA0C tables onto map $8AB6'),
    0xEA76: ('SCORE_TICK', 'Move 2 points from PENDING_POINTS to SCORE_DIGITS; if none pending skip the caller\'s next CALL (UPDATE_HUD)'),
    0xDF55: ('PRINT_CHAR_BIG', 'Print one character double height'),
    0xE0E5: ('REDEFINE_KEYS', 'Menu 5: prompt and read five keys into KEY_TABLES'),
    0xE16F: ('PRINT_KEY_PROMPT', 'Print prompt $E0B6 with key number A'),
    0xE178: ('READ_NEW_KEY', 'Wait for a key not used yet (ROM KEY-SCAN), store port row/mask at HL'),
    0xEA43: ('COPY_DOWNED_TO_SCREEN', 'Fighter in state $FF (down): copy 64 rows from back buffer at row $4880'),
    0xEF24: ('HERO_KO', 'Hero knocked out: last redraw, start HERO_DEATH (EE8E/EE8F)'),
    0xF0F2: ('ACTOR_RECORD', 'HL = ACTORS + 15*A'),
    0xF2BC: ('PROJECTILES_VS_ACTORS', 'Loop over fighters 5..1 against thrown weapons'),
    0xFC86: ('HERO_PICKUP', 'Hero input $0D: pick up / use item by $E4CD (?)'),
    0xFE0F: ('DRAW_HOLE_SCREEN', 'Draw a hole on screen: 3 bytes x 16 rows of $FF, edges from ($FE25)'),
    0xEABC: ('ROOM_BUILD', 'Build room ROOM: tile $A0 (blank in room 1, else copy of $9C), stream, recolour, floor, holes, idol, walls; copy screen to back buffer'),
    0xEB68: ('RECOLOUR_ROOM', 'Rooms in list $EB56: attributes $68-$6F in N rows -> paper blue (table index = 5 - list position)'),
    0xF107: ('DRAW_WALLS', 'No exit left/right (NEIGHBOURS) -> 4x15 wall block from $8134 / $8158'),
    0xF131: ('DRAW_TILE_BLOCK', '15 rows x 4 tiles from a 40-wide source at HL to map DE / screen BC'),
    0xF62F: ('DRAW_ROOM_TOP', 'Room stream -> 480 cells (rows 0-14); column counter 0..39, columns 4..35 visible'),
    0xF800: ('TILE25_COLOUR', 'Tile $25 attribute: $2C in rooms listed at $F694 (4,6,8,3,5), else $2A'),
    0xF817: ('RAINBOW', 'Room 0: rows 4-10 get paper 1..7'),
    0xFF48: ('DOOR_COLOUR', 'Rooms 19/20: 8x8 door attributes at row 5 col 12 ($50 red / $60 green)'),
    0xFB2A: ('NEXT_ROOM', 'ROOM = NEIGHBOURS[ROOM][A]-1 (NC if no exit), clear screen, APPROACHING <name>'),
    0xEAA7: ('UPDATE_HUD', 'Print idol count and HUD strings'),
    0xEB95: ('TILE_COLUMN', 'Advance tile column counter $E4CA (0..39) (?)'),
    0xEBE9: ('GAME_START', 'Game entry: DI, seed RNG from R, menu, new game setup'),
    0xED23: ('MAIN_LOOP', 'Main game loop: no HALT, runs unthrottled (~4.6 frames per pass in trace)'),
    0xEDA5: ('PAUSE', 'Pause (key G) until a control is pressed'),
    0xEDC2: ('ENEMY_AI', 'AI for actors 0..4 at $E461 (IY), writes their input bytes (?)'),
    0xEE29: ('HERO_DEATH', 'Hero down: count $EE8F (5 passes), wait until PENDING_POINTS drained, then GAME OVER (one life)'),
    0xEE4B: ('HIT_HANDLER', 'Fighter $E8AA hit: sound, energy (+$0C) -= random 3..10; at 0 set KO flag $EE8C'),
    0xEE91: ('KO_HANDLER', 'Fighter knocked out: points to PENDING_POINTS, mark record; hero -> HERO_KO ($EF24)'),
    0xEF3F: ('CHECK_HITS', 'Attack hit tests: enemies vs hero, hero vs enemies; sets $E8A9 (hit) / $E8AA (who)'),
    0xF063: ('OVERLAP_TEST', 'Range overlap test (H,L vs D,E); carry = no overlap'),
    0xF06C: ('SOUND_HIT', 'Beeper effect, OUT ($FE) at $F088'),
    0xF091: ('WINNER', 'Seven idols in room 4: print WINNER, wait, restart'),
    0xF0FD: ('ACTOR_LOOP_SETUP', 'IY = $E470, B = 5, DE = 15'),
    0xF1B4: ('PROJECTILES_MOVE', '3 thrown weapons at $E866 (IY) (?)'),
    0xF21B: ('PROJECTILES_UPDATE', '3 thrown weapons at $E866 (?)'),
    0xF277: ('PROJECTILES_HIT', 'Thrown weapons vs actors, calls PROJECTILE_COLLIDE (?)'),
    0xF3A7: ('PROJECTILE_SUB', 'Helper of PROJECTILE_COLLIDE (?)'),
    0xF3C3: ('PROJECTILE_COLLIDE', 'One thrown weapon vs actors (?)'),
    0xF4AC: ('ENEMY_STATE', 'For actors 5..1: state by record byte (?)'),
    0xF554: ('IDOL_IN_ROOM', 'Idol handling by control type $E1F3 via TABLE_WORD (?)'),
    0xF5CB: ('CLEAR_HUD_ATTRS', 'Set attributes of the bottom HUD lines $5AA0..'),
    0xF64C: ('DRAW_ROOM_STREAM', 'Draw room from tile stream at ($E4C4), $FF = end (?)'),
    0xF699: ('ENTER_ROOM', 'Go to the neighbour of ROOM in direction A (0 left, 1 right, 2 up, 3 down) and set it up; new game: ROOM=6, A=1 -> room 4'),
    0xF908: ('ROOM_SOUND', 'Beeper loop through ROM BEEPER (bug 1: BEEPER ends with EI)'),
    0xFAF3: ('IDOL_ROOM_CHECK', 'Carry if current room+1 is in IDOL_ROOMS'),
    0xFB71: ('ANIMATE_ALL', 'For 6 actors (IY=$E4AC backwards) (?)'),
    0xFC41: ('HERO_SUB', 'Called when $E8A5 != 0 (?)'),
    0xFC64: ('RESET_INPUTS', 'Clear per-actor input bytes except $14'),
    0xFC78: ('HERO_ACTION', 'Hero action by HERO_INPUT ($0D = special) (?)'),
    0xFE56: ('DRAW_HOLES', 'Per tick: floor hole (HOLE_FLOOR) into back buffer at $6B60+X, then ceiling hole (HOLE_CEIL)'),
    0xFE83: ('DRAW_CEILING_HOLE', 'Ceiling hole into back buffer at $5B00+X: 3 bytes x 16 rows of $FF, edges from $DBFF'),
    0xFDDC: ('SETUP_HOLES', 'HOLE_CEIL/HOLE_FLOOR from HOLES table for ROOM; draw them on screen'),
    0xFD00: ('ROOM_EXITS', 'Hero X<2 -> ENTER_ROOM(0) left, X>=$19 -> ENTER_ROOM(1) right'),
    0xFD3D: ('HOLE_EXITS', 'Up under HOLE_CEIL (X..X+2): climb, ENTER_ROOM(2); down+crouch phase 2 over HOLE_FLOOR: ENTER_ROOM(3)'),
    0xEF4E: ('ENEMY_HITS_LOOP', 'Enemies 5..1 vs hero. ORIGINAL BUG: gate reads field +7 ($E4B3 = record 5 +7, high byte of the frame pointer, never 0) instead of +8 (state) like HERO_HITS_LOOP, so enemy melee never lands. ZX conversion slip: the CPC code tests one state array $7454+n in both loops. Fix: $EF4F $B3 -> $B4'),
    0xEFD7: ('HERO_HITS_LOOP', 'Hero vs enemies 1..5: enemy state +8 = 0, hero input is an attack (table $FECA), reach (table $FEF6) overlaps'),
}

DATA = {
    0xD00C: ('TILE_GFX', 'Room tile graphics, 8 bytes per tile'),
    0xDA70: ('ROOM_TABLES', 'Room work tables (?)'),
    0xDB7A: ('HUD_TEXT', 'HUD strings; score digits at $DB86'),
    0xDB86: ('SCORE_DIGITS', 'Score, 5 ASCII digits'),
    0xDEF1: ('RNG_SEED', 'RANDOM state (4 bytes), seeded from R at start'),
    0xE021: ('KEY_TABLES', 'Control tables per control type: (port row, mask) triples'),
    0xE1EC: ('CONTROL_TYPE', 'Menu choice 1..5 minus one'),
    0xE1ED: ('HERO_INPUT', 'Input bytes: hero at $E1ED, actors 1..5 follow (AI writes them)'),
    0xE461: ('ACTORS', '6 actor records x 15 bytes ($E461-$E4BA)'),
    0xE4BA: ('ROOM', 'Current room. Bug 2: it is byte 14 of actor record 5; bugfix moves it to $E4BB'),
    0xE4C2: ('PENDING_POINTS', 'Points still to add to the score, 2 per main loop pass'),
    0xDBB5: ('HOLES', 'Per room 2 bytes: X of ceiling hole, X of floor hole (0 = none)'),
    0xE4D9: ('HOLE_CEIL', 'X of the ceiling hole in this room (0 = none); HOLE_FLOOR follows'),
    0x7300: ('ROOM_STREAM_DATA', 'Room streams (see ROOM_STREAMS), floor stream at $7808'),
    0x7808: ('FLOOR_STREAM', 'Floor of every room: 200 cells from row 14 col 24'),
    0x8134: ('WALL_LEFT', 'Left wall block, 4 x 15 tiles in 40-wide rows'),
    0x8158: ('WALL_RIGHT', 'Right wall block, 4 x 15 tiles in 40-wide rows'),
    0xD897: ('NEIGHBOURS', 'Per room: left, right, up, down as room+1 (0 = no exit)'),
    0xD8EB: ('ROOM_NAME_ARTICLE', 'Per room: character put into APPROACHING message'),
    0xD900: ('ROOM_NAMES', '21 zero-terminated room names in room order'),
    0xD9DE: ('ROOM_STREAMS', '21 pointers to room tile streams'),
    0xDA70: ('MAX_ENEMIES', 'Per room: enemy slots'),
    0xDA85: ('ROOM_ENEMIES', 'Per room 5 bytes: $F0+type of each enemy (filled by CLEAR_ROOM_TABLES)'),
    0xE37E: ('TILE_ATTR', 'Attribute per tile (BRIGHT added when drawn)'),
    0xEB50: ('RECOLOUR_ROWS', 'RECOLOUR_ROOM: rows (6), attribute pointers at $EB5C, room list at $EB56'),
    0xF61C: ('ENEMY_NAMES', '4 pointers: THUG, KARATEKA, NINJA, HERO'),
    0xFB0A: ('IDOL_GFX', 'Idol 2 bytes x 16 rows'),
    0xE4BC: ('IDOL_ROOMS', '6 random distinct rooms 1..20 (not 11) holding idols'),
    0xE4CC: ('IDOLS_HELD', 'Idols collected; 7 in room 4 = WINNER'),
    0xF0A6: ('MSG_WINNER_FULL', 'WINNER screen text'),
    0x5B00: ('BACK_BUFFER', 'Back buffer $5B00-$72FF: same layout as the screen, screen address + $1B00'),
    0x8AB7: ('TILE_MAP', 'Room tile map, 1 byte per character cell; play area from $8BF7'),
    0xD717: ('ROW_TABLE', 'Screen row address table, 2 bytes per pixel row'),
    0xDA0C: ('FRAME_TABLE', 'Actor animation frame table (word per frame)'),
    0xE866: ('PROJECTILES', '3 thrown weapons; flags at $E888'),
}

MESSAGES = {
    0xD925: 'MSG_TORII_IN_THE_SEA', 0xD94F: 'MSG_SHIJO_ENTRANCE',
    0xD968: 'MSG_AKUMAS_CHAMBER', 0xD9CF: 'MSG_BIG_GREEN_DOOR',
    0xDB44: 'MSG_REDEFINE_KEYS', 0xF0AB: 'MSG_WINNER', 0xF0D1: 'MSG_GAME_OVER',
}

ranges = []
for line in open(sys.argv[1]):
    r = line.split()[0]
    s, e = (int(x.lstrip('$'), 16) for x in r.split('-'))
    ranges.append((s, e + 1))

entries = {}   # addr -> (type, label, desc)
for s, e in ranges:
    entries[s] = ('c', None, None)
    entries.setdefault(e, ('b', None, None))
for a, (lab, desc) in CODE.items():
    entries[a] = ('c', lab, desc)
for a, (lab, desc) in DATA.items():
    if a in entries and entries[a][0] == 'c':
        continue
    entries[a] = ('b', lab, desc)
for a, lab in MESSAGES.items():
    entries.setdefault(a, ('b', lab, 'Message text'))
    if entries[a][1] is None:
        entries[a] = ('b', lab, 'Message text')

def in_code(a):
    return any(s <= a < e for s, e in ranges)

print('''; Ninja (Mastertronic / Icon Design, 1986), 48K: SkoolKit control file.
; Generated by tools/gen_ctl.py from a traced run (tools/run_trace.py --hist,
; build/trace/hist). 'c' = executed in the trace; 'b' between them = data or
; code the trace did not reach. Names with (?) are unverified guesses.
; Image: build/zx/ram4000.bin = RAM $4000-$FF7F.

@ $4000 org
@ $EBE9 start
b $4000 Screen, attributes, system variables, free RAM''')
print('@ $69DE label=LOADER_2STAGE')
print('c $69DE Second-stage loader copy (clear screen, LOAD via ROM $0556)')
print('b $6A00')
print('@ $6A25 label=LOADER_LOAD_LOOP')
print('c $6A25 Loader: wait key, load blocks')
print('@ $6A56 label=LOADER_PAUSE')
print('c $6A56 HALT x25 delay')
print('@ $6A5C label=WAIT_KEYPRESS')
print('c $6A5C Wait for key')
print('@ $6A64 label=LOADER_3STAGE_COPY')
print('b $6A64 Unused copy of the loader (length $BFC0)')
for a in sorted(entries):
    if a < 0x6A64 and a != 0x5CEF and a != 0x5D32:
        continue
    t, lab, desc = entries[a]
    if t == 'b' and in_code(a) and not lab:
        continue
    if lab:
        print(f'@ ${a:04X} label={lab}')
    print(f'{t} ${a:04X}' + (f' {desc}' if desc else ''))
print('i $FF80')
