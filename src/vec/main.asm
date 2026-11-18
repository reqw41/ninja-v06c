; Ninja для Вектора-06Ц (ваниль 64 КБ, 3 плоскости, 8 цветов) — сборка образа.
;   ./build.sh  (tools/mkl80.py, tools/mkfont.py; sjasmplus --i8080)
; Раскладка (docs/I8080.md): 0000 переходы, 0038 прерывание, остальное — page0.asm (образ .rom с 0100 их не грузит); 0100.. логика (src/i8080) и платформа;
; 2000–8413 данные ZX $7300–$D713 (ZX − ZS); 8414.. островки; дальше вывод, шрифт, amap, полоса, стек;
; A000–FFFF экран (плоскости A000/C000/E000 = биты 2/1/0 цвета ZX, номер палитры = цвет ZX).
			DEVICE	NOSLOT64K
			DEFINE	VEC_CPC					; вид CPC: кадры бойцов CPC, разворот — при выводе (логика не трогает спрайты)
			INCLUDE	"../i8080/gen/zxequ.asm"
SND_SW0		EQU	0x10			; звуковые события (озвучка Atari, docs/MUSIC.md)
SND_SW1		EQU	0x11
SND_HIT0	EQU	0x20
SND_HIT1	EQU	0x21
SND_KO		EQU	0x30
SND_IDOL	EQU	0x40
SND_ROOM	EQU	0x50
	IFNDEF	WH_TH
WH_TH		EQU	2					; свист: громкость 0 — шириной (10b), 1 — редкостью ~v², 2 — редкостью ~v (владелец 15.11: 13c), 3 — таблица WT1..7
	ENDIF
	IFNDEF	MUS_NZ
MUS_NZ		EQU	1					; шумовые удары баса песни: 0 — шум, 1 — тишина, 2 — тон
	ENDIF
	IFNDEF	AMB_PH
AMB_PH		EQU	0					; подыгрывание тише сдвигом фазы (владелец 15.11 выбрал громкое: «2»)
	ENDIF
	IFNDEF	AMB_K
AMB_K		EQU	2					; подыгрывание: недобор до противофазы (витки): 0 — -30 дБ, 2 — -33 (Atari -32,5), 5 — -43
	ENDIF
STACK		EQU	0xA000				; стек 9F00..9FFF
STRIP		EQU	0x9E00				; полоса столбца: байт на строку i (i = 32 + строка снизу)
STRIP_H		EQU	high STRIP
AMAP		EQU	0x9B00				; атрибуты клеток ZX (768)
TICK		EQU	4					; кадров на проход (ZX p50 ≈ 3,7)
CP_H		EQU	0x32				; столбец собирается в 3 невидимых полосах 3200/3300/3400 (байт на строку i):
									; фон и бойцы — там, на экран — готовое (каждый байт экрана пишется один раз)

			ORG	0x0000
			DI
			LD	SP,STACK
			JP	boot
			DEFINE	P0_A
			INCLUDE	"page0.asm"
			UNDEFINE P0_A
			DISPLAY "page0 A end ",/H,$
			ASSERT	$ <= 0x0038
			ORG	0x0038
			JP	isr
			INCLUDE	"page0.asm"
			DISPLAY "page0 B end ",/H,$
			ASSERT	$ <= 0x0100

			ORG	0x0100
			JP	boot				; образ .rom грузится с 0100 и стартует отсюда
code_start:
			INCLUDE	"../i8080/sys.asm"
			INCLUDE	"../i8080/fight.asm"
			INCLUDE	"../i8080/actors.asm"
			INCLUDE	"../i8080/room.asm"
			INCLUDE	"../i8080/game.asm"
			INCLUDE	"plat.asm"
			INCLUDE	"../i8080/dzx0.asm"
			INCLUDE	"cpcdec.asm"
			INCLUDE	"field_lo.asm"
code_end:
pool_a:							; хвост низа до 2000 — запас полос готовых клеток (field.asm)
			ASSERT	code_end <= 0x2000
ROOMBUF		EQU	AMAP				; поток комнаты распаковывается в AMAP (его строит plat_room после)
			INCLUDE	"../i8080/gen/rooms.asm"
			INCLUDE	"sound.asm"
			INCLUDE	"gen/music.asm"
			INCLUDE	"gen/cpc_lo.asm"		; полосы строк части комнат (tools/mkcpc.py LO_RUNS)
free_lo:							; свободно до 37B7 (3200..34FF — полосы плоскостей)
			ASSERT	$ <= CP_H * 256
			ASSERT	(CP_H + 3) * 256 <= 0x8AB7 - ZS
			ORG	0x8AB7 - ZS				; карта тайлов, картинки оружия ZX
			INCBIN	"../../build/zx/ram4000.bin", 0x8AB7 - 0x4000, 0x8D8C - 0x8AB7
			INCLUDE	"gen/cpc.asm"			; на месте спрайтов ZX: кадры CPC (по столбцам), палитры комнат
			INCLUDE	"fixes.asm"
			INCLUDE	"field.asm"			; вывод поля ×1.5 (место освободили кадры ×0.75)
cpc_end:
			DISPLAY "cpc_end ",/H,$
			ASSERT	cpc_end <= 0xD00C - ZS
			ORG	0xD00C - ZS				; тайлы по 6 точек (×1.5) на месте тайлов ZX
			INCLUDE	"gen/tiles6.asm"
			INCLUDE	"tilespare.asm"
			DISPLAY "tilespare end ",/H,$," limit ",/H,0xD714 - ZS
			ASSERT	$ <= 0xD714 - ZS
			INCLUDE	"../i8080/gen/zxdata.asm"
hi_start:
			INCLUDE	"render.asm"
			INCLUDE	"field2.asm"
font:
	IFDEF	TESTFONT
			INCLUDE	"../../build/vec/font_zx.asm"	; только для сверки экрана с ZX (не в образе порта)
	ELSE
			INCLUDE	"gen/font.asm"
	ENDIF
hi_end:
			ASSERT	hi_end <= AMAP
			ORG	0x9F00
			INCLUDE	"stk.asm"
			INCLUDE	"gen/cpc_stk.asm"		; полосы строк части комнат (tools/mkcpc.py STK_RUNS)
			DISPLAY	"стек: код до ", /H, $, " (до 9FB0)"
			ASSERT	$ <= 0x9FB0
	IF	EX_D
			ORG	zv_DB63 + 11			; строка HUD: «SCORE» — да, «IDOLS» и цифра — нет (владелец 18.11: идолы значками,
			DB	0					; idol_hud)
			ORG	zv_DB63 + 2				; «SCORE» и цифры счёта — на знакоместо правее (владелец 19.11)
			DB	1
			ORG	zv_DB81 + 2
			DB	7
	ENDIF
	IFDEF	TESTFONT
			SAVEBIN	"../../build/vec/ninja_t.bin", 0, 0xA000
	ELSE
			SAVEBIN	"../../build/vec/ninja.bin", 0, 0xA000
			SAVEBIN	"../../build/vec/ninja.rom", 0x0100, 0xA000 - 0x0100
	ENDIF
			DISPLAY	"низ: код до ", /H, code_end, ", комнаты до ", /H, free_lo, " (свободно ", /D, 0x8AB7 - ZS - free_lo, " Б), верх: ", /H, hi_start, "..", /H, hi_end, " (до AMAP ", /D, AMAP - hi_end, " Б)"
