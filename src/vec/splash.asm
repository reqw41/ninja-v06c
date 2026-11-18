; Заставка Ninja (tools/mksplash.py, владелец 15.11): образ 64 КБ с 0x0000. Показ картинки (8 цветов) до
; клавиши (или огня джойстика «П»), затем — распаковка игры в 0000..9FFF и запуск с 0000.
			DEVICE	NOSLOT64K
			INCLUDE	"tskip.inc"
			ORG	0x0000
			di
			ld	sp,0x0100
			jp	sp_entry
			ORG	0x0038
			ret						; будит HALT; дальше — с DI
			ORG	0x0040
sp_entry:	ld	a,0x88
			out	(0x00),a
			xor	a
			out	(0x02),a
			ld	a,0xFF
			out	(0x03),a
			ld	a,0x83				; джойстик «П»
			out	(0x04),a
			ld	a,0x9F
			out	(0x05),a
.w:			ei						; палитра — каждый кадр в обратном ходе (как в monty: разовая запись
			halt					; на некоторых эмуляторах попадает не туда)
			di
			ld	hl,sp_pal+15
			call	sp_palette
			call	sp_key
			jp	z,.w
			jp	sp_info_go			; стартовый экран, потом игра
; HL = последний байт палитры: 15..0
sp_palette:	ld	e,15
.l:			ld	a,e
			out	(0x02),a
			ld	a,(hl)
			dec	hl
			out	(0x0C),a
			out	(0x0C),a
			out	(0x0C),a
			out	(0x0C),a
			dec	e
			jp	p,.l
			xor	a
			out	(0x02),a
			ret
sp_copy:	ld	a,(hl)
			ld	(de),a
			inc	hl
			inc	de
			dec	bc
			ld	a,b
			or	c
			jp	nz,sp_copy
			ret
sp_black:	ds	16
			ASSERT	$ <= 0x00E0
			ORG	0x0100
sp_payload:	INCBIN	"game.zx0"
PAYLOAD_END:
sp_pal:		INCBIN	"palette.bin"
sp_unpack_src:
			DISP	0xFE00
			ld	sp,0
			ld	hl,0xA000
			ld	bc,0x0000
			call	dzx0
			ld	a,1					; игре: стартовый экран уже был — сразу в игру
			ld	(TSKIP),a
			jp	0x0000
			INCLUDE	"../i8080/dzx0.asm"
			ENT
sp_unpack_end:
; стартовый экран (владелец 18.11: «стартовый экран с названием игры, копирайтами, описанием управления»):
; распаковать в экран, ждать отпускания и нажатия; игре — флаг t_skip: сразу в игру, без ожидания огня
sp_info_go:	ei
			halt
			di
			ld	hl,sp_black+15
			call	sp_palette
			ld	hl,sp_info
			ld	bc,0xA000
			call	info.dzx0
.r:			ei
			halt
			di
			ld	hl,sp_ipal+15
			call	sp_palette
			call	sp_key				; отпустить
			jp	nz,.r
.i:			ei
			halt
			di
			ld	hl,sp_ipal+15
			call	sp_palette
			call	sp_key
			jp	z,.i
			ei
			halt
			di
			ld	hl,sp_black+15
			call	sp_palette
			ld	hl,sp_payload		; сжатая игра -> A000, распаковщик -> FE00
			ld	de,0xA000
			ld	bc,PAYLOAD_END - sp_payload
			call	sp_copy
			ld	hl,sp_unpack_src
			ld	de,0xFE00
			ld	bc,sp_unpack_end - sp_unpack_src
			call	sp_copy
			jp	0xFE00
; NZ — нажата клавиша или огонь джойстика «П»
sp_key:		ld	a,0x8A				; клавиатура: все ряды
			out	(0x00),a
			xor	a
			out	(0x03),a
			in	a,(0x02)
			ld	b,a
			ld	a,0xFF
			out	(0x03),a
			ld	a,0x88
			out	(0x00),a
			ld	a,b
			inc	a
			ret	nz
			in	a,(0x06)			; огонь джойстика (0 — нажат)
			ld	b,a
			in	a,(0x0E)
			and	b
			and	0xC0
			cp	0xC0
			ret
sp_ipal:	INCBIN	"ipal.bin"
sp_info:	INCBIN	"info.zx0"
			MODULE	info
			INCLUDE	"../i8080/dzx0.asm"
			ENDMODULE
			ASSERT	$ <= 0x8000
			ASSERT	PAYLOAD_END - sp_payload <= 0xFE00 - 0xA000
			ORG	0x8000
			INCBIN	"screen.bin"
			SAVEBIN	"splash.rom", 0, 0x10000
