; Бой (перевод src/model/fight.js): попадания $EF3F, удар $EE4B, нокаут $EE91/$EEE6/$EF24, гибель $EE29,
; метательное оружие $F476/$F40D/$F3C3/$F277.

; HL = INPUT+... ; HL = FEF6 + 2*A
reach:		LD	L,A
			LD	H,0
			ADD	HL,HL
			LD	DE,zv_FEF6
			ADD	HL,DE
			RET

; --- $EF3F: удары врагов 5..1 по герою, потом героя по врагам 1..5 ---------------------------------------
check_hits:	LD	A,(zv_E8A8)
			OR	A
			RET	NZ
			LD	(zv_E8A9),A
			LD	(zv_E8AA),A
			LD	B,5
.e:			LD	A,B
			LD	(zv_E8A2),A
			CALL	rec_a
			LD	(t_rec),HL
			LD	DE,8
			ADD	HL,DE
			LD	A,(HL)			; исправление порта: состояние +8
			OR	A
			JP	NZ,.en
			LD	HL,zv_E1ED
			CALL	add_b
			LD	A,(HL)
			LD	(t_inp),A
			LD	HL,zv_FECA
			CALL	add_a
			LD	A,(HL)
			OR	A
			JP	Z,.en
			LD	C,A
			LD	HL,zv_E4CD
			CALL	add_b
			LD	A,(HL)
			CP	C
			JP	NZ,.en
			LD	A,(t_inp)
			CALL	reach
			LD	(t_p),HL
			LD	C,(HL)
			LD	A,(zv_E1F3)
			OR	A
			JP	NZ,.r1
			LD	A,0x28
			SUB	C
			LD	C,A
.r1:		LD	HL,(t_rec)
			LD	A,(HL)
			ADD	A,A
			ADD	A,A
			ADD	A,A
			ADD	A,C
			LD	E,A
			LD	D,2
			HERO_X
			ADD	A,A
			ADD	A,A
			ADD	A,A
			LD	L,A
			LD	H,0x28
			CALL	apart
			JP	C,.en
			LD	HL,(t_p)
			INC	HL
			LD	C,(HL)
			LD	HL,(t_rec)
			INC	HL
			LD	A,(HL)
			ADD	A,C
			LD	E,A
			LD	D,2
			LD	A,(zv_E462)
			LD	L,A
			LD	H,0x30
			CALL	apart
			JP	C,.en
			XOR	A
			LD	(zv_E8AA),A
			INC	A
			LD	(zv_E8A9),A
.en:		DEC	B
			JP	NZ,.e
			LD	B,1
.h:			LD	A,B
			LD	(zv_E8A2),A
			CALL	rec_a
			LD	(t_rec),HL
			LD	DE,8
			ADD	HL,DE
			LD	A,(HL)
			OR	A
			JP	NZ,.hn
			LD	A,(zv_E1ED)
			LD	(t_inp),A
			LD	HL,zv_FECA
			CALL	add_a
			LD	A,(HL)
			OR	A
			JP	Z,.hn
			LD	C,A
			LD	A,(zv_E4CD)
			CP	C
			JP	NZ,.hn
			LD	A,(t_inp)
			CALL	reach
			LD	(t_p),HL
			LD	C,(HL)
			LD	A,(zv_E1F3)
			OR	A
			JP	Z,.r2
			LD	A,0x28
			SUB	C
			LD	C,A
.r2:		HERO_X
			ADD	A,A
			ADD	A,A
			ADD	A,A
			ADD	A,C
			LD	L,A
			LD	H,2
			PUSH	HL
			LD	HL,(t_rec)
			LD	A,(HL)
			ADD	A,A
			ADD	A,A
			ADD	A,A
			LD	E,A
			LD	D,0x28
			POP	HL
			CALL	apart
			JP	C,.hn
			LD	HL,(t_rec)
			INC	HL
			LD	L,(HL)
			LD	H,0x30
			PUSH	HL
			LD	HL,(t_p)
			INC	HL
			LD	A,(zv_E462)
			ADD	A,(HL)
			LD	E,A
			LD	D,2
			POP	HL
			CALL	apart
			JP	C,.hn
			LD	A,B
			LD	(zv_E8AA),A
			LD	(zv_E8A9),A
			RET
.hn:		INC	B
			LD	A,B
			CP	6
			JP	NZ,.h
			RET

; --- $EE4B: боец $E8AA получил удар: энергия -= (RND & 7) | 3; 0 — нокаут ----------------------------------
hit:		LD	A,(zv_E8A8)
			OR	A
			RET	NZ
			LD	A,(zv_EE8F)
			OR	A
			RET	NZ
			LD	A,(t_wpn)			; звук удара: канал — кто ударил (оружие — 0)
			OR	A
			LD	A,SND_HIT0
			JP	NZ,.s
			LD	A,(zv_E8AA)
			OR	A
			LD	A,SND_HIT0
			JP	NZ,.s
			LD	A,SND_HIT1
.s:			CALL	plat_sound
			LD	A,(zv_E8AA)
			CALL	rec_a
			LD	DE,0x0C
			ADD	HL,DE
			CALL	random
			AND	7
			OR	3
			LD	C,A
			LD	A,(HL)
			SUB	C
			JP	Z,.ko
			JP	NC,.st
.ko:		LD	A,0xFF
			LD	(zv_EE8C),A
			LD	A,4
			LD	(zv_E8A8),A
			LD	(zv_EE8D),A
			XOR	A
.st:		LD	(HL),A
			RET

; --- $EE91: нокаут бойца $E8AA -------------------------------------------------------------------------
ko:			LD	A,(zv_EE8F)
			OR	A
			RET	NZ
			LD	A,(zv_E8AA)
			LD	HL,zv_E88D
			CALL	add_a
			LD	A,(HL)
			LD	(HL),0xFF
			AND	3
			CP	3
			JP	NC,.np
			INC	A
			ADD	A,A
			LD	C,A
			ADD	A,A
			ADD	A,A
			ADD	A,C
			ADD	A,A				; 20 * (тип + 1)
			LD	HL,(zv_E4C2)
			CALL	add_a
			LD	(zv_E4C2),HL
.np:		XOR	A
			LD	(zv_EE8C),A
			LD	A,(zv_E8AA)
			LD	HL,zv_E4CD
			CALL	add_a
			LD	(HL),0
			LD	A,(zv_E8AA)
			CALL	rec_a
			LD	DE,8
			ADD	HL,DE
			LD	(HL),0xFF
			LD	A,(zv_E8AA)
			OR	A
			JP	Z,hero_ko
			LD	A,SND_KO
			CALL	plat_sound
			CALL	enemy_ko
			XOR	A
			LD	(zv_E8AA),A
			RET

; --- $EEE6: стереть имя нокаутированного; ждущий враг (состояние 2) выходит на его место ----------------
enemy_ko:	LD	A,(zv_EE8F)
			OR	A
			RET	NZ
			LD	A,(zv_EE90)
			CP	3
			RET	NC
			LD	B,A
			LD	C,4
			CALL	print_name
			LD	B,1
.l:			LD	A,B
			CALL	rec_a
			LD	(t_rec),HL
			LD	A,8
			CALL	fld
			LD	A,(HL)
			CP	2
			JP	Z,.f
			INC	B
			LD	A,B
			CP	6
			JP	NZ,.l
			RET
.f:			LD	A,0x0E			; $EF02
			CALL	fld
			LD	A,(zv_EE90)
			LD	(HL),A
			LD	A,0xFF
			LD	(zv_EE90),A
			LD	A,8
			CALL	fld
			LD	(HL),0
			LD	A,0x0E
			CALL	fld
			LD	B,(HL)
			LD	A,0x0D
			CALL	fld
			LD	C,(HL)
			JP	print_name

; --- $EF24: герой в нокауте ----------------------------------------------------------------------------
hero_ko:	LD	A,0x30
			LD	(zv_E1ED),A
			CALL	animate_all
			CALL	animate_all
			CALL	draw
			LD	(zv_EE8E),A
			LD	A,5
			LD	(zv_EE8F),A
			XOR	A
			LD	(zv_E4CD),A
			RET

; --- $EE29: герой лежит 5 проходов, ждёт начисления очков — GAME OVER --------------------------------------
hero_death:	LD	A,(zv_EE8F)
			OR	A
			JP	Z,.z
			DEC	A
			LD	(zv_EE8F),A
			JP	.w
.z:			LD	HL,(zv_E4C2)
			LD	A,H
			OR	L
			JP	Z,plat_game_over
.w:			LD	A,0x30
			LD	(zv_E1ED),A
			XOR	A
			LD	(zv_E469),A
			RET

; --- $F476: оружие бойца $E88B: Z — есть, HL = запись, B = номер+1 (как у ZX; ниже Y=$28 — Z, HL = адрес Y) -
proj_of:	LD	A,(zv_E88B)
			LD	C,A
			CALL	rec_a
			INC	HL
			LD	A,(HL)
			CP	0x28
			JP	NC,.y
			LD	B,3
			LD	HL,zv_E87C
			LD	DE,zv_E88A
.l:			LD	A,(DE)
			DEC	A
			CP	C
			RET	Z
			DEC	DE
			PUSH	DE
			LD	DE,-11
			ADD	HL,DE
			POP	DE
			DEC	B
			JP	NZ,.l
			LD	A,1
			OR	A
			RET
.y:			LD	A,C				; $F4AA: XOR A; RET (B = 0 после цикла, если боец не герой)
			OR	A
			JP	Z,.y0
			LD	B,0
.y0:		XOR	A
			RET

; --- $F40D: боец $E88B подбирает лежащее рядом оружие --------------------------------------------------
pick_up:	XOR	A
			LD	(zv_E85A),A
			LD	HL,zv_E888
			LD	DE,zv_E866
			LD	B,3
.l:			LD	A,(HL)
			OR	A
			JP	NZ,.n
			PUSH	HL
			LD	A,(zv_E88B)
			CALL	rec_a
			LD	A,(HL)
			LD	(t_x),A
			DEC	A
			LD	C,A
			ADD	A,6
			LD	H,A
			LD	A,(DE)
			CP	C
			JP	C,.p
			CP	H
			JP	NC,.p
			PUSH	DE
			EX	DE,HL
			INC	HL
			INC	HL
			LD	A,(t_x)
			ADD	A,2
			LD	(HL),A			; +2
			INC	HL
			LD	(HL),0x39		; +3
			LD	DE,4
			ADD	HL,DE
			LD	(HL),1			; +7
			DEC	HL
			LD	A,(zv_E88B)
			INC	A
			LD	(HL),A			; +6
			LD	(zv_E85A),A
			POP	DE
			POP	HL
			LD	(HL),A
			JP	.n
.p:			POP	HL
.n:			INC	HL
			PUSH	HL
			LD	HL,11
			ADD	HL,DE
			EX	DE,HL
			POP	HL
			DEC	B
			JP	NZ,.l
			RET

; --- $F3C3: шаг оружия DE (флаг HL) к цели +2/+3 -----------------------------------------------------------
proj_move:	LD	C,0
			PUSH	HL
			LD	HL,7
			ADD	HL,DE
			LD	A,(HL)
			OR	A
			JP	Z,.e
			LD	HL,3
			ADD	HL,DE
			LD	A,(HL)
			CP	0x39
			JP	C,.c
			LD	(HL),0x39
.c:			POP	HL				; $F3A7: мерцание
			PUSH	HL
			LD	A,(HL)
			CP	7
			JP	C,.s
			LD	HL,5
			ADD	HL,DE
			DEC	(HL)
			JP	P,.s
			DEC	HL
			LD	A,(HL)
			INC	HL
			LD	(HL),1
			OR	A
			JP	Z,.s
			LD	(HL),3
.s:			EX	DE,HL			; HL = запись
			INC	HL				; X и цель — со знаком (вид ×1.5: X героя бывает < 0): сравнение по X ^ $80
			INC	HL				; (для X 0..127 — то же, что у ZX)
			LD	A,(HL)
			XOR	0x80
			LD	B,A
			DEC	HL
			DEC	HL
			LD	A,(HL)
			XOR	0x80
			CP	B
			JP	Z,.y
			JP	C,.inc
			DEC	(HL)
			JP	.xc
.inc:		INC	(HL)
.xc:		INC	C
	IF	EX_D
			JP	.y1
.y:			CALL	proj_land			; долетело до края по X — на пол
.y1:
	ELSE
.y:
	ENDIF
			INC	HL
			LD	A,(HL)
			INC	HL
			INC	HL
			CP	(HL)
			DEC	HL
			DEC	HL
			JP	Z,.yd
			JP	C,.add
			SUB	3
	IF	EX_D
			CP	0x1E				; не ниже пола (владелец 18.11: «вращается как в полёте, но лежит внизу» — с Y не
			JP	NC,.ys				; кратной 3 от пола, например 55 после броска героя, оружие проскакивало пол и
			LD	A,0x1E				; вечно качалось у него)
	ENDIF
			JP	.ys
.add:		ADD	A,3
.ys:		LD	(HL),A
			INC	C
.yd:		DEC	HL
			EX	DE,HL
.e:			POP	HL
			LD	A,C
			OR	A
			RET	NZ
			PUSH	HL
			LD	HL,6
			ADD	HL,DE
			LD	A,(HL)
			POP	HL
			CP	(HL)
			RET	NZ
			LD	HL,7
			ADD	HL,DE
			LD	(HL),0
			RET

; --- $F277: полёт оружия и попадания ($32 — брошено врагом, $64 — героем) ------------------------------
projectiles: LD	A,(zv_E887)
			OR	A
			RET	NZ
	IF	EX_D
			CALL	proj_orphan
	ENDIF
			LD	B,3
			LD	HL,zv_E888
			LD	DE,zv_E866
.m:			PUSH	BC
			PUSH	HL
			PUSH	DE
			CALL	proj_move
			POP	DE
			POP	HL
			POP	BC
			INC	HL
			PUSH	HL
			LD	HL,11
			ADD	HL,DE
			EX	DE,HL
			POP	HL
			DEC	B
			JP	NZ,.m
			LD	A,(zv_E8A8)
			OR	A
			RET	NZ
			LD	B,3
.j:			LD	A,B
			DEC	A
			LD	(zv_F3A2),A
			CALL	proj_j
			LD	(t_pj),HL
			LD	A,(zv_F3A2)
			LD	HL,zv_E888
			CALL	add_a
			LD	A,(HL)
			CP	0x32
			JP	Z,.en
			CP	0x64
			JP	NZ,.nx
			LD	C,5
.t:			LD	A,C
			LD	(zv_F3A4),A
			CALL	rec_a
			LD	A,(HL)
			ADD	A,A
			ADD	A,A
			ADD	A,A
			ADD	A,6
			LD	(t_l),A
			INC	HL
			LD	A,(HL)
			LD	(zv_F3A6),A
			LD	DE,7
			ADD	HL,DE
			LD	A,(HL)
			OR	A
			JP	NZ,.tn
			LD	HL,(t_pj)
			LD	A,(HL)
			ADD	A,A
			ADD	A,A
			ADD	A,A
			LD	E,A
			LD	D,8
			LD	A,(t_l)
			LD	L,A
			LD	H,8
			CALL	apart
			JP	C,.tn
			LD	HL,(t_pj)
			INC	HL
			LD	E,(HL)
			LD	D,8
			LD	A,(zv_F3A6)
			LD	L,A
			LD	H,0x30
			CALL	apart
			JP	C,.tn
			LD	A,(zv_E8A9)
			OR	A
			JP	NZ,.tn
			LD	A,(zv_F3A4)
			LD	E,1
			PUSH	BC
			CALL	proj_hit
			POP	BC
.tn:		DEC	C
			JP	NZ,.t
			JP	.nx
.en:		HERO_X
			ADD	A,A
			ADD	A,A
			ADD	A,A
			ADD	A,6
			LD	E,A
			LD	D,8
			LD	HL,(t_pj)
			LD	A,(HL)
			ADD	A,A
			ADD	A,A
			ADD	A,A
			LD	L,A
			LD	H,8
			CALL	apart
			JP	C,.nx
			LD	A,(zv_E462)
			LD	E,A
			LD	D,0x30
			LD	HL,(t_pj)
			INC	HL
			LD	L,(HL)
			LD	H,8
			CALL	apart
			JP	C,.nx
			LD	A,(zv_E8A9)
			OR	A
			JP	NZ,.nx
			LD	E,0
			PUSH	BC
			CALL	proj_hit
			POP	BC
.nx:		DEC	B
			JP	NZ,.j
			RET
; попадание оружием (t_pj, номер $F3A2): A = кто, E = 1 — и кадр +5 = 0
proj_hit:	LD	(zv_E8AA),A
			LD	A,1
			LD	(zv_E8A9),A
			LD	HL,(t_pj)
			LD	A,(HL)
			INC	HL
			INC	HL
			LD	(HL),A			; +2
			INC	HL
			LD	(HL),0x1E		; +3
			INC	HL
			INC	HL
			LD	A,E
			OR	A
			JP	Z,.n5
			LD	(HL),0			; +5
.n5:		INC	HL
			LD	(HL),0x28		; +6
			LD	A,(zv_F3A2)
			LD	HL,zv_E888
			CALL	add_a
			LD	(HL),0
			LD	A,1
			LD	(t_wpn),A
			CALL	hit
			XOR	A
			LD	(t_wpn),A
			RET


