; field2.asm: постройка комнаты ×1.5 (поля карты, свои тайлы дыр и идола) — в верхней области (место)
; ---- комната: поля карты MARG_T из потоков (до постройки AMAP: поток лежит в ROOMBUF = AMAP) ----
marg_build:	LD	HL,MARG_T
			LD	B,168
			XOR	A
.z:			LD	(HL),A
			INC	HL
			DEC	B
			JP	NZ,.z
			LD	HL,ROOMBUF			; поток комнаты: с конца строки -1, 480 видимых клеток
			LD	A,0x27
			LD	B,0xFF
			LD	DE,480
			CALL	ms_stream
			LD	HL,floor_s			; пол: строка 14, столбец $1B, 200 клеток
			LD	A,0x1B
			LD	B,14
			LD	DE,200
			CALL	ms_stream
			LD	A,(zv_E4BB)			; нет выхода — стена в полях 0..3 / 36..39, строки 2..16
			ADD	A,A
			ADD	A,A
			LD	HL,zv_D897
			CALL	add_a
			LD	A,(HL)
			INC	HL
			PUSH	HL
			OR	A
			LD	HL,wall_l
			LD	DE,MARG_T + 2*8
			CALL	Z,ms_wall
			POP	HL
			LD	A,(HL)
			OR	A
			RET	NZ
			LD	HL,wall_r
			LD	DE,MARG_T + 2*8 + 4
ms_wall:	LD	B,15
.r:			LD	C,4
.c:			LD	A,(HL)
			LD	(DE),A
			INC	HL
			INC	DE
			DEC	C
			JP	NZ,.c
			LD	A,E
			ADD	A,4
			LD	E,A
			LD	A,D
			ADC	A,0
			LD	D,A
			DEC	B
			JP	NZ,.r
			RET
; поток HL (как $F64C): A — столбец, B — строка до первого тайла, DE — видимых клеток (столбцы 4..35)
ms_stream:	LD	(ms_col),A
			LD	A,B
			LD	(ms_row),A
			EX	DE,HL
			LD	(ms_cnt),HL
			EX	DE,HL
.t:			LD	A,(HL)
			INC	HL
			LD	B,0
			CP	0xFF
			JP	NZ,.one
			LD	A,(HL)
			INC	HL
			LD	B,(HL)				; повторов - 1
			INC	HL
.one:		LD	(ms_tile),A
.rp:		PUSH	HL
			PUSH	BC
			CALL	ms_put
			POP	BC
			POP	HL
			RET	Z
			LD	A,B
			SUB	1
			LD	B,A
			JP	NC,.rp
			JP	.t
; следующий тайл: Z — видимые клетки кончились
ms_put:		LD	A,(ms_col)
			INC	A
			CP	40
			JP	C,.c
			LD	A,(ms_row)
			INC	A
			LD	(ms_row),A
			XOR	A
.c:			LD	(ms_col),A
			CP	4
			JP	C,.m
			CP	36
			JP	NC,.m2
			LD	HL,(ms_cnt)
			DEC	HL
			LD	(ms_cnt),HL
			LD	A,H
			OR	L
			RET
.m2:		SUB	32
.m:			LD	C,A
			LD	A,(ms_row)
			CP	21
			JP	NC,.nz
			LD	L,A
			LD	H,0
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			LD	A,C
			CALL	add_a
			LD	DE,MARG_T
			ADD	HL,DE
			LD	A,(ms_tile)
			LD	(HL),A
.nz:		OR	1
			RET
ms_col:		DB	0
ms_row:		DB	0
ms_tile:	DB	0
ms_cnt:		DW	0

; ---- свои тайлы дыр и идола: группа HL (gen/cpc.asm), A — столбец ZX: тайл клетки := свой, его точки =
; точки исходного | узор; ct_back — вернуть исходные ----
ct_apply:	CALL	ct_base
.e:			PUSH	BC
			LD	A,(HL)				; смещение клетки
			INC	HL
			PUSH	HL
			LD	HL,(ca_base)
			CALL	add_a
			LD	C,(HL)				; исходный тайл
			EX	DE,HL
			POP	HL
			LD	A,(HL)				; свой
			LD	(DE),A
			INC	HL
			LD	(HL),C
			INC	HL
			PUSH	HL
			CALL	t6_addr
			EX	DE,HL				; DE — точки своего
			LD	A,C
			CALL	t6_addr
			LD	B,H
			LD	C,L					; BC — точки исходного
			POP	HL					; узор
			PUSH	HL
			PUSH	DE
			PUSH	BC
			LD	A,8
.p:			PUSH	AF					; бит 0 пера: | узор
			LD	A,(BC)
			OR	(HL)
			LD	(DE),A
			INC	HL
			INC	BC
			INC	DE
			POP	AF
			DEC	A
			JP	NZ,.p
			POP	HL					; бит 1 пера: дыра — чёрное перо 1 (& ~узор), идол — перо 3 (| узор)
			LD	BC,TB_D
			ADD	HL,BC
			LD	B,H
			LD	C,L
			POP	HL
			LD	DE,TB_D
			ADD	HL,DE
			EX	DE,HL
			POP	HL
			PUSH	HL
			LD	A,8
.q:			PUSH	AF
			LD	A,(ct_or)
			OR	A
			LD	A,(HL)
			JP	NZ,.qo
			CPL
			EX	DE,HL
			PUSH	HL
			LD	H,B
			LD	L,C
			AND	(HL)
			POP	HL
			EX	DE,HL
			JP	.qs
.qo:		EX	DE,HL
			PUSH	HL
			LD	H,B
			LD	L,C
			OR	(HL)
			POP	HL
			EX	DE,HL
.qs:		LD	(DE),A
			INC	HL
			INC	BC
			INC	DE
			POP	AF
			DEC	A
			JP	NZ,.q
			POP	HL
			LD	DE,8
			ADD	HL,DE
			POP	BC
			DEC	B
			JP	NZ,.e
			RET
ct_back:	CALL	ct_base
.e:			LD	A,(HL)
			INC	HL
			INC	HL
			PUSH	HL
			LD	HL,(ca_base)
			CALL	add_a
			EX	DE,HL
			POP	HL
			LD	A,(HL)				; исходный
			LD	(DE),A
			LD	DE,9
			ADD	HL,DE
			DEC	B
			JP	NZ,.e
			RET
; ca_base = MAP_V + строка группы + A; B — записей; HL — первая запись
ct_base:	LD	E,(HL)
			INC	HL
			LD	D,(HL)
			INC	HL
			PUSH	HL
			LD	HL,MAP_V
			ADD	HL,DE
			CALL	add_a
			LD	(ca_base),HL
			POP	HL
			LD	B,(HL)
			INC	HL
			RET
; HL = точки тайла A
t6_addr:	LD	HL,tremap			; номер ZX -> плотная таблица
			CALL	add_a
			LD	L,(HL)
			LD	H,0
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			PUSH	DE
			LD	DE,TGFX_V
			ADD	HL,DE
			POP	DE
			RET
ca_base:	DW	0
ct_or:		DB	0					; 1 — идол (перо 3), 0 — дыра (перо 1)

; бит шума из долгого вывода (без задержки): проход длиннее темпа — простоя нет, шум не должен глохнуть в гул
nz_tick:	LD	A,(nz_ch)
			CP	3
			RET	NC
			LD	A,1
			LD	(nz_fast),A
			CALL	nz_bit
			XOR	A
			LD	(nz_fast),A
			RET
nz_fast:	DB	0


cdesc:		DS	3*NC_MAX				; готовые клетки: 3 номера полос (A000, C000, E000)

	IF	EX_D
hero_xc:	LD	A,(zv_E461)
			ADD	A,0x80				; со знаком -> порядок без знака
			CP	0x80+2
			JP	NC,.a
			LD	A,0x80+2
.a:			CP	0x80+0x1A
			JP	C,.b
			LD	A,0x80+0x19
.b:			SUB	0x80
			RET
	ENDIF
