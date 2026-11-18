; plat.asm: платформа Вектора для логики Ninja (src/i8080): запуск, прерывание, ввод, ход игры.
; Ввод — как Bruce Lee: стрелки + пробел и джойстик «П» -> Kempston ZX (управление 1 = клавиатура Q A O P
; ENTER + Kempston; буквы на Векторе не нажимаются); ВК — G ZX (пауза), АР2 — F ZX (выход).

boot:		DI
			LD	SP,STACK
			LD	A,0xC3				; вектор прерывания 0038 (образ .rom 0000..00FF не грузит)
			LD	(0x0038),A
			LD	HL,isr
			LD	(0x0039),HL
			LD	A,0x88				; ППА: A — скролл/ряд клавиатуры, B — бордюр, C — клавиши СС/УС/РУС
			OUT	(0x00),A
			XOR	A
			OUT	(0x02),A
			LD	A,0xFF
			OUT	(0x03),A
			LD	A,0x83				; джойстик «П»: ППА2, чтение — порт 6
			OUT	(0x04),A
			LD	A,0x9F
			OUT	(0x05),A
			LD	A,0x30				; ВИ53: счётчики в режим 0 без загрузки — тишина (звук — этап 5)
			OUT	(0x08),A
			LD	A,0x70
			OUT	(0x08),A
			LD	A,0xB0
			OUT	(0x08),A
			CALL	scr_clear
			LD	HL,pal_zx
			CALL	pal_set
			EI
title:		LD	SP,STACK			; заставка и меню — этап 6: пока ждём огонь/пробел
			CALL	t_chk				; после стартового экрана загрузчика — сразу игра (page0.asm)
			CALL	snd_title			; песня с шумовыми ударами баса (владелец 15.11)
.w0:		LD	A,(kemp)
			AND	0x10
			JP	NZ,.w0
.w1:		LD	A,(kemp)
			AND	0x10
			JP	Z,.w1
game:		LD	SP,STACK
			LD	A,(frames)			; GAME_START: LD A,R -> $DEF1
			LD	(zv_DEF1),A
			CALL	snd_newgame			; песня с начала
			XOR	A
			LD	(snd_pause),A
			LD	A,1					; управление: клавиатура + Kempston
			CALL	new_game
.l:			CALL	pass
			JP	.l

; A = старший байт порта ZX FE -> байт клавиатуры (бит = 0 — нажата): только G (ВК) и F (АР2) ряда FDFE
zx_in:		AND	2
			LD	A,0xFF
			RET	NZ
			LD	A,(key_gf)
			RET
zx_kemp:	LD	A,(kemp)
			RET
plat_ldar:	LD	A,(frames)
			RET

; GAME OVER / WINNER: строка ZX, ждать отпускания и нажатия огня — новая игра (меню — этап 6)
plat_game_over:
			LD	HL,zv_F0CC
			JP	end_msg
plat_winner:
			LD	HL,zv_F0A6
end_msg:	PUSH	HL
			DI						; $1871: подыгрывание стоп, всё заглушить
			LD	A,0xFF
			LD	(snd_cc),A
			CALL	snd_mute
			EI
			POP	HL
			CALL	vprint
			LD	SP,STACK
			JP	title
plat_menu:	JP	title

; ---- прерывание кадра ----
isr:		PUSH	AF
			PUSH	BC
			PUSH	DE
			PUSH	HL
			LD	A,(pal_load)
			OR	A
			JP	Z,.np
			DEC	A
			LD	(pal_load),A
			LD	HL,(pal_ptr)
			LD	DE,15
			ADD	HL,DE
			LD	E,0x0F
.pl:		LD	A,E
			OUT	(0x02),A
			LD	A,(HL)
			DEC	HL
			OUT	(0x0C),A
			OUT	(0x0C),A
			OUT	(0x0C),A
			OUT	(0x0C),A
			DEC	E
			JP	P,.pl
.np:
	IF	EX_D
			LD	A,1					; бордюр — серый номер 1 (владелец 18.11)
	ELSE
			XOR	A					; бордюр чёрный
	ENDIF
			OUT	(0x02),A
			CALL	vec_scan
			CALL	build_kemp
			LD	A,(vec_kbmat+8)		; УС — звук вкл/выкл (по нажатию)
			AND	0x40
			LD	HL,us_prev
			CP	(HL)
			LD	(HL),A
			JP	Z,.nus
			OR	A
			JP	Z,.nus
			LD	A,(snd_on)
			XOR	1
			LD	(snd_on),A
.nus:		CALL	snd_frame
			LD	HL,frames
			INC	(HL)
			POP	HL
			POP	DE
			POP	BC
			POP	AF
			EI
			RET

frames:		DB	0
us_prev:	DB	0
last_draw:	DB	0
kemp:		DB	0					; Kempston: R L D U огонь (биты 0..4)
key_gf:		DB	0xFF				; ряд FDFE ZX: G (бит 4) = ВК, F (бит 3) = АР2
pal_ptr:	DW	pal_zx
pal_load:	DB	0
pal_set:	LD	(pal_ptr),HL
			LD	A,3
			LD	(pal_load),A
			RET
; цвета ZX (яркие): чёрный, синий, красный, малиновый, зелёный, голубой, жёлтый, белый — дважды (плоскость 8000 — код)
pal_zx:		DB	0x00,0xC0,0x07,0xC7,0x38,0xF8,0x3F,0xFF, 0x00,0xC0,0x07,0xC7,0x38,0xF8,0x3F,0xFF

; ---- клавиатура Вектора (как Bruce Lee): vec_kbmat (1 = нажата), [8] — СС/УС/РУС из порта 01 ----
vec_kbmat:	DS	9
vec_scan:	LD	A,0x8A				; порт B — вход
			OUT	(0x00),A
			LD	HL,vec_kbmat
			LD	B,0xFE
.l:			LD	A,B
			OUT	(0x03),A
			IN	A,(0x02)
			CPL
			LD	(HL),A
			INC	HL
			LD	A,B
			RLCA
			LD	B,A
			JP	C,.l
			IN	A,(0x01)
			CPL
			AND	0xE0
			LD	(HL),A
			LD	A,0x88
			OUT	(0x00),A
			LD	A,0xFF
			OUT	(0x03),A
			RET
; стрелки (ряд 0: бит 7 вниз, 6 вправо, 5 вверх, 4 влево), пробел (ряд 7 бит 7), джойстик «П» -> kemp
build_kemp:	LD	A,(vec_kbmat+0)
			LD	B,0
			RLCA
			JP	NC,.a1
			LD	B,4					; вниз
.a1:		RLCA
			JP	NC,.a2
			INC	B					; вправо
.a2:		RLCA
			JP	NC,.a3
			LD	C,A
			LD	A,B
			OR	8					; вверх
			LD	B,A
			LD	A,C
.a3:		RLCA
			JP	NC,.a4
			LD	A,B
			OR	2					; влево
			LD	B,A
.a4:		LD	A,(vec_kbmat+7)
			AND	0x80
			JP	Z,.a5
			LD	A,B
			OR	0x10
			LD	B,A
.a5:		LD	A,0x9F				; оба джойстика «П»
			OUT	(0x05),A
			IN	A,(0x06)
			CALL	joy_dir
			OR	B
			LD	(kemp),A
			LD	B,0xFF				; ВК -> G, АР2 -> F
			LD	A,(vec_kbmat+0)
			AND	0x04
			JP	Z,.g
			LD	B,0xEF
.g:			LD	A,(vec_kbmat+1)
			AND	0x04
			LD	A,B
			JP	Z,.f
			AND	0xF7
.f:			LD	(key_gf),A
			RET
; порт джойстика «П» (0 — нажато: R L U D -- -- огонь огонь) -> R L D U огонь (биты 0..4)
joy_dir:	CPL
			LD	C,A
			AND	0x30				; в покое биты 4, 5 — единицы; иначе джойстика нет
			LD	A,0
			RET	NZ
			LD	A,C
			AND	3
			LD	D,A
			LD	A,C
			AND	4
			JP	Z,.u
			LD	A,D
			OR	8
			LD	D,A
.u:			LD	A,C
			AND	8
			JP	Z,.d
			LD	A,D
			OR	4
			LD	D,A
.d:			LD	A,C
			AND	0xC0
			LD	A,D
			RET	Z
			OR	0x10
			RET
