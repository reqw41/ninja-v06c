; tilespare.asm: в хвосте плотной таблицы тайлов (место)
; палитра комнаты: 8 цветов по HL -> pal_tmp дважды (номера i и i + 8 — плоскость 8000 — код), pal_set
pal_set8:	LD	DE,pal_tmp
			LD	B,8
.c:			LD	A,(HL)
			LD	(DE),A
			PUSH	HL
			LD	HL,8
			ADD	HL,DE
			LD	(HL),A
			POP	HL
			INC	HL
			INC	DE
			DEC	B
			JP	NZ,.c
			LD	HL,pal_tmp
			JP	pal_set
pal_tmp:	DS	16

; бит шума на выход счётчика nz_ch (режим 0: запись управляющего слова опускает выход, счёт 1 поднимает его
; через такт) и задержка nz_dly; портит A (как Bruce Lee)
nz_bit:		LD	A,(nz_ch)
			CP	3
			RET	NC
			PUSH	HL
			PUSH	BC
			LD	C,A
			LD	HL,(nz_rnd)
			LD	A,(nz_p4)			; полином 4 (канал 4 Atari): бит — из него
			OR	A
			JP	Z,.rn
			CALL	p4_step
			JP	NC,.z
			JP	.one
.rn:		LD	A,H
			RRA
			LD	H,A
			LD	A,L
			RRA
			LD	L,A
			JP	NC,.ns
			LD	A,H
			XOR	0xB4
			LD	H,A
.ns:		LD	A,(nz_thin)			; единица с вероятностью nz_thin / 256 (128 — обычный шум; меньше — тише,
			LD	B,A					; без тона на частоте битов — владелец 15.11: «завывают»)
			LD	A,H
			XOR	L
			CP	B
			JP	NC,.z
.one:		LD	(nz_rnd),HL
			LD	A,C
			RRCA
			RRCA
			OR	0x10				; режим 0, только младший байт
			DI
			OUT	(0x08),A
			LD	A,0x0B
			SUB	C
			LD	(.pt+1),A
			LD	A,1
.pt:		OUT	(0x0B),A
			LD	A,(nz_isr)			; из прерывания — не разрешать (вложенное прерывание портит экран: владелец 15.11
			OR	A					; «мусор в HUD» при свисте почти на весь кадр)
			JP	NZ,.ni
			EI
.ni:
			LD	A,(nz_thr)			; узкий импульс — тише: через nz_thr витков выход вниз
			OR	A
			JP	Z,.d
.w:			DEC	A
			JP	NZ,.w
			LD	A,C
			RRCA
			RRCA
			OR	0x30
			OUT	(0x08),A
			JP	.d
.z:			LD	(nz_rnd),HL
			LD	A,C
			RRCA
			RRCA
			OR	0x30				; режим 0, оба байта, без счёта — выход внизу
			OUT	(0x08),A
.d:			LD	A,(nz_fast)
			OR	A
			JP	NZ,.e
			LD	A,(nz_dlh)			; задержка: nz_dlh * 256 + nz_dly витков
			OR	A
			JP	Z,.lo
			LD	B,A
.hi:		XOR	A
.h1:		DEC	A
			JP	NZ,.h1
			DEC	B
			JP	NZ,.hi
.lo:		LD	A,(nz_dly)
			OR	A
			JP	Z,.e
.dl:		DEC	A
			JP	NZ,.dl
.e:			POP	BC
			POP	HL
			RET
; кадры ходьбы врагов (X меняется каждый проход: 42..44, 32/48/49, перекат 25) — точный сдвиг; ходьба героя —
; готовые кадры 50..57
walk_fr:	DB	0x00,0x00,0x00,0x02,0x01,0x1C,0x03,0x00

