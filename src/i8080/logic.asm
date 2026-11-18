; Ninja: логика на i8080 для сверки с эталонами ZX (tools/run80.js) — раскладка Вектора (tools/mkl80.py).
;   python3 -I tools/mkl80.py && (cd src/i8080 && ../../tools/sjasmplus --nologo --i8080 --sym=../../build/l80/logic.sym logic.asm)
			DEVICE	NOSLOT64K
			INCLUDE	"gen/zxequ.asm"

			ORG	0x0100
code_start:
			INCLUDE	"sys.asm"
			INCLUDE	"fight.asm"
			INCLUDE	"actors.asm"
			INCLUDE	"room.asm"
			INCLUDE	"game.asm"
			INCLUDE	"plat_test.asm"
			INCLUDE	"dzx0.asm"
roombuf:	DS	ROOMBUF_SIZE		; поток комнаты, распакованный (на Векторе — AMAP)
roombuf_end:
ROOMBUF		EQU	roombuf
code_end:
			ASSERT	code_end <= 0x2000
			INCLUDE	"gen/rooms.asm"
			ORG	0x8AB7 - ZS
			INCBIN	"../../build/zx/ram4000.bin", 0x8AB7 - 0x4000, 0xD714 - 0x8AB7
			INCLUDE	"gen/zxdata.asm"
stack_top	EQU	0xA000
			SAVEBIN	"../../build/l80/logic.bin", 0, 0xA000
			DISPLAY	"код ", /D, code_end - code_start, " Б"
