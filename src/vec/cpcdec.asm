; cpcdec.asm: распаковка кадров CPC в буферы бойцов (вызов — act_state в render.asm).
; Буфер: по столбцам (байт Вектора), в столбце h строк по 2 байта (P0, P1: перо 1 чёрное 01, 2 оранжевое 10,
; 3 телесное 11; 0 — прозрачно). Строка RLE: старший полубайт — повторов, младший — пара точек CPC (каждая —
; 2 точки Вектора) = полубайт буфера. Буфер не очищается: первая половина столбца пишется целиком (LD), вторая —
; OR, после конца строки остаток столбцов обнуляется. Разворот: столбцы справа налево, половины меняются местами.

; ---- разворот всех кадров на месте (как ZX $F925): у каждого кадра столбцы в обратном порядке, байты точек —
; с обращением битов; spr_m — текущее направление кадров (0 — как у CPC = $F924 0) ----
spr_m:		DB	0
spr_orient:	LD	A,(zv_F924)
			AND	1
			LD	HL,spr_m
			CP	(HL)
			RET	Z
			LD	(HL),A
			LD	HL,cpc_data			; все байты точек
			LD	DE,cpc_data_end - cpc_data
			LD	B,high rev_tab
.b:			LD	C,(HL)
			LD	A,(BC)
			LD	(HL),A
			INC	HL
			DEC	DE
			LD	A,D
			OR	E
			JP	NZ,.b
			LD	C,0					; таблицы столбцов 50 кадров
.f:			PUSH	BC
			LD	A,C
			LD	HL,cpc_frp
			CALL	tword
			INC	HL
			LD	B,(HL)				; wv
			LD	DE,CPC_HDR - 1
			ADD	HL,DE				; HL = первый столбец
			LD	A,B					; DE = последний: HL + 4*(wv-1)
			DEC	A
			ADD	A,A
			ADD	A,A
			LD	E,A
			LD	D,0
			EX	DE,HL
			ADD	HL,DE
			EX	DE,HL
			LD	A,B					; обменов wv / 2
			RRCA
			AND	0x7F
			JP	Z,.fn
			LD	B,A
.sw:		PUSH	BC
			LD	C,4
.s4:		LD	A,(DE)
			LD	B,(HL)
			LD	(HL),A
			LD	A,B
			LD	(DE),A
			INC	HL
			INC	DE
			DEC	C
			JP	NZ,.s4
			LD	A,E					; DE -= 8 (к предыдущему столбцу)
			SUB	8
			LD	E,A
			LD	A,D
			SBC	A,0
			LD	D,A
			POP	BC
			DEC	B
			JP	NZ,.sw
.fn:		POP	BC
			INC	C
			LD	A,C
			CP	50
			JP	NZ,.f
			RET

; ---- список прямоугольников бойцов: слить перекрывающиеся по столбцам, нарисовать ----
rl_flush:
.o:			LD	A,(rl_n)			; i, j: rl[i] и rl[j] перекрываются — rl[i] |= rl[j], rl[j] = последний
			CP	2
			JP	C,.dr
			LD	C,0
.i:			LD	A,C
			INC	A
			LD	B,A
.j:			LD	A,(rl_n)
			CP	B
			JP	Z,.ni
			PUSH	BC
			LD	A,C
			CALL	rl_at
			EX	DE,HL				; DE = rl[i]
			POP	BC
			PUSH	BC
			LD	A,B
			CALL	rl_at				; HL = rl[j]
			LD	A,(DE)				; ci0 < cj1
			INC	HL
			CP	(HL)
			DEC	HL
			JP	NC,.nj
			LD	A,(HL)				; cj0 < ci1
			INC	DE
			EX	DE,HL
			CP	(HL)
			EX	DE,HL
			DEC	DE
			JP	NC,.nj
			LD	A,(DE)				; слить: c0 = min, c1 = max, lo = min, hi = max
			CP	(HL)
			JP	C,.m0
			LD	A,(HL)
			LD	(DE),A
.m0:		INC	HL
			INC	DE
			LD	A,(DE)
			CP	(HL)
			JP	NC,.m1
			LD	A,(HL)
			LD	(DE),A
.m1:		INC	HL
			INC	DE
			LD	A,(DE)
			CP	(HL)
			JP	C,.m2
			LD	A,(HL)
			LD	(DE),A
.m2:		INC	HL
			INC	DE
			LD	A,(DE)
			CP	(HL)
			JP	NC,.m3
			LD	A,(HL)
			LD	(DE),A
.m3:		POP	BC					; rl[j] = последний, n -= 1
			LD	A,(rl_n)
			DEC	A
			LD	(rl_n),A
			CALL	rl_at
			EX	DE,HL				; DE = последний
			LD	A,B
			CALL	rl_at
			EX	DE,HL
			LD	B,4
.cpl:		LD	A,(HL)
			LD	(DE),A
			INC	HL
			INC	DE
			DEC	B
			JP	NZ,.cpl
			JP	.o
.nj:		POP	BC
			INC	B
			JP	.j
.ni:		INC	C
			LD	A,(rl_n)
			DEC	A
			CP	C
			JP	NZ,.i
.dr:		LD	A,(rl_n)			; нарисовать
			OR	A
			RET	Z
			DEC	A
			LD	(rl_n),A
			CALL	rl_at
			LD	DE,rb_c0
			LD	B,4
.c:			LD	A,(HL)
			LD	(DE),A
			INC	HL
			INC	DE
			DEC	B
			JP	NZ,.c
			CALL	rect_draw
			JP	.dr
rl_at:		ADD	A,A					; HL = rl + 4*A
			ADD	A,A
			LD	HL,rl
			JP	add_a
rl_n:		DB	0
rl:			DS	4*6
