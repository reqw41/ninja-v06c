; Бойцы (перевод src/model/actors.js): бросок врага $E4FC, ИИ $E583.., анимация $FB71, $F4AC, полоски $EDC2,
; действия героя $FC78..$FDDB, ввод $E1F4.

; --- $E4FC: враг с вводом $23 и своим оружием: фаза <4 — в руке, 4 — летит ------------------------------
enemy_throw: LD	B,5
.l:			PUSH	BC
			LD	A,B
			LD	(zv_E88B),A
			LD	(zv_E8A2),A
			LD	HL,zv_E1ED
			CALL	add_b
			LD	A,(HL)
			CP	0x23
			JP	NZ,.n
			CALL	proj_of			; B = номер оружия + 1
			JP	NZ,.n
			LD	(t_pj),HL
			LD	A,(zv_E8A2)
			LD	HL,zv_E4CD
			CALL	add_a
			LD	A,(HL)
			CP	4
			JP	Z,.f
			JP	NC,.n
			LD	HL,(t_pj)
			LD	DE,7
			ADD	HL,DE
			LD	(HL),0
			LD	A,(zv_E8A2)
			CALL	rec_a
			LD	E,(HL)
			INC	HL
			LD	D,(HL)
			LD	HL,0x1402
			ADD	HL,DE
			EX	DE,HL
			LD	HL,(t_pj)
			LD	(HL),E
			INC	HL
			LD	(HL),D
			INC	HL
			LD	(HL),E
			INC	HL
			LD	(HL),D
			LD	DE,3
			ADD	HL,DE
			LD	(HL),0x32
			INC	HL
			LD	(HL),1
			JP	.n
.f:			LD	HL,(t_pj)
			INC	HL
			INC	HL
			LD	A,(zv_E1F3)
			OR	A
			LD	A,0
			JP	NZ,.f1
			LD	A,0x1F
.f1:		LD	(HL),A
			INC	HL
			INC	(HL)
			LD	A,B
			DEC	A
			LD	HL,zv_E888
			CALL	add_a
			LD	(HL),0x32
			LD	HL,(t_pj)
			LD	DE,6
			ADD	HL,DE
			LD	(HL),0x32
			INC	HL
			LD	(HL),1
.n:			POP	BC
			DEC	B
			JP	NZ,.l
			RET

; --- ИИ врагов ---------------------------------------------------------------------------------------------
; $E75C: атака $E83F или шаг $E83D/$E83E
ai_choose:	CALL	random
			LD	HL,zv_E840
			CP	(HL)
			JP	NC,ai_atk
			INC	HL
			CP	(HL)
			JP	C,.e716
			LD	A,(zv_E1F3)		; $E73B
			CPL
			OR	A
			JP	NZ,ai_second
			JP	ai_first
.e716:		CALL	random
ai_e719:	LD	A,(zv_E1F3)
			OR	A
			JP	NZ,ai_second
ai_first:	LD	A,(zv_DEF1)
			AND	7
			CALL	set_timer
			LD	A,(zv_E83D)
			JP	set_input
ai_second:	LD	A,(zv_DEF1)
			AND	7
			CALL	set_timer
			LD	A,(zv_E83E)
			JP	set_input
ai_atk:		LD	A,(zv_E83F)
			CALL	set_input
			LD	A,(zv_DEF1)
			AND	3
			OR	1
			JP	set_timer
; $E7A7: вблизи героя — приём из таблицы $E842
ai_close:	CALL	random
			XOR	A
			CALL	set_timer
			CALL	kind
			ADD	A,A
			ADD	A,A
			ADD	A,A
			LD	HL,zv_E842
			CALL	add_a
			LD	A,(zv_DEF1)
			AND	7
			CALL	add_a
			LD	A,(HL)
			OR	A
			JP	NZ,set_input
			LD	(zv_DEF1),A
			JP	ai_e719
; $E77D: у края
ai_edge:	LD	HL,zv_E899
			CALL	cur_hl
			LD	A,(HL)
			LD	HL,zv_E83D
			CP	(HL)
			LD	A,(zv_E83E)
			JP	Z,.c
			LD	A,(zv_E83D)
.c:			LD	C,A
			CALL	random
			CP	0x64
			JP	NC,.s
			LD	A,(zv_E83F)
			LD	C,A
.s:			LD	A,C
			CALL	set_input
			CALL	random
			AND	7
			JP	set_timer
; $E669/$E689: ниндзя у дыры прыгает (A = $29/$28)
ai_jump:	LD	C,A
			CALL	kind
			CP	2
			JP	NZ,ai_close
			CALL	random
			CP	0x78
			JP	NC,ai_close
			XOR	A
			CALL	set_timer
			LD	A,C
			JP	set_input
; $E6BC: таймер истёк; перенос — ход сделан (бросок $23 или подбор $2D)
ai_timer:	CALL	kind
			CP	2
			JP	NZ,.ch
			LD	A,(zv_E8A2)
			LD	(zv_E88B),A
			CALL	proj_of
			JP	NZ,.np
			LD	A,(zv_DEF1)
			CP	0xA0
			JP	NC,.ch
			LD	A,0x23
			CALL	set_input
			SCF
			RET
.np:		CALL	random
			CP	0x3C
			JP	C,.ch
			LD	A,(zv_E8A2)
			LD	(zv_E88B),A
			CALL	pick_up
			LD	A,(zv_E85A)
			OR	A
			JP	Z,.ch
			XOR	A
			CALL	set_timer
			LD	A,0x2D
			CALL	set_input
			SCF
			RET
.ch:		CALL	ai_choose
			SCF
			CCF
			RET
dec_t:		LD	HL,zv_E893
			CALL	cur_hl
			DEC	(HL)
			RET
; $E613: общий ход врага
ai_move:
	IF	EX_D
			HERO_X
			LD	(t_hx),A
			CALL	curX
			LD	HL,t_hx
	ELSE
			CALL	curX
			LD	HL,zv_E461
	ENDIF
			SUB	(HL)
			JP	NC,.d
			CPL
			INC	A
.d:			CP	4
			JP	C,ai_close
			LD	HL,zv_E893
			CALL	cur_hl
			LD	A,(HL)
			OR	A
			JP	Z,.z
			DEC	(HL)
			JP	NZ,.nz
.z:			CALL	ai_timer
			RET	C
.nz:		LD	HL,zv_E899
			CALL	cur_hl
			LD	A,(HL)
			LD	(zv_DFE1),A
			LD	HL,zv_E83D
			CP	(HL)
			JP	Z,.tw
			LD	HL,zv_E83F
			CP	(HL)
			JP	Z,.atk
			LD	HL,zv_E83E
			CP	(HL)
			CALL	NZ,ai_choose
			CALL	curX
			CP	0x18
			JP	NC,ai_edge
			LD	HL,zv_E89F
			CP	(HL)
			JP	C,.keep
			JP	Z,.j29
			LD	HL,zv_E8A0
			CP	(HL)
			JP	C,.j29
.keep:		CALL	dec_t
			LD	A,(zv_DFE1)
			JP	set_input
.j29:		LD	A,0x29
			JP	ai_jump
.tw:		CALL	curX
			CP	2
			JP	C,ai_edge
			LD	HL,zv_E8A0
			CP	(HL)
			JP	NC,.keep
			LD	HL,zv_E89F
			CP	(HL)
			JP	C,.keep
			LD	A,0x28
			JP	ai_jump
.atk:		CALL	dec_t
			LD	A,(zv_E83F)
			JP	set_input

; $E583: враги 5..1 по типу
enemy_ai:	LD	B,5
.l:			PUSH	BC
			LD	A,B
			LD	(zv_E8A2),A
			LD	HL,zv_E88D
			CALL	add_b
			LD	A,(HL)
			CP	0xFF
			JP	NZ,.t
			LD	A,0x2C
			CALL	set_input
			JP	.r
.t:			AND	3
			CP	3
			JP	Z,.r
			LD	C,A
			ADD	A,A
			ADD	A,C
			LD	HL,ai_types
			CALL	add_a
			LD	C,(HL)
			INC	HL
			LD	E,(HL)
			INC	HL
			LD	D,(HL)
			LD	HL,zv_E1ED
			CALL	cur_hl
			LD	A,(HL)
			OR	A
			JP	NZ,.r
			LD	A,(zv_E8A4)
			OR	A
			JP	Z,.st
			POP	HL
			PUSH	HL
			LD	A,H
			CALL	rec_a
			PUSH	DE
			LD	DE,8
			ADD	HL,DE
			POP	DE
			LD	A,(HL)
			OR	A
			JP	NZ,.st
			LD	HL,zv_E83D
			LD	B,5
.cp:		LD	A,(DE)
			LD	(HL),A
			INC	DE
			INC	HL
			DEC	B
			JP	NZ,.cp
			CALL	ai_move
			JP	.r
.st:		LD	A,C
			CALL	set_input
.r:			CALL	random
			POP	BC
			DEC	B
			JP	NZ,.l
			RET
ai_types:	DB	0x1C
			DW	zv_E82E
			DB	0x15
			DW	zv_E838
			DB	0x21
			DW	zv_E833

; --- $FB71: бойцы 5..0: шаг анимации по вводу, кадр, сдвиг X/Y ------------------------------------------
animate_all: LD	B,6
.l:			DEC	B
			PUSH	BC
			LD	A,B
			LD	(zv_E88B),A
			CALL	rec_a
			LD	(t_rec),HL
			LD	HL,zv_E1ED
			CALL	add_b
			LD	A,(HL)
			LD	(zv_E85A),A
			LD	L,A
			LD	H,0
			ADD	HL,HL
			LD	DE,zv_DC63
			ADD	HL,DE
			LD	E,(HL)
			INC	HL
			LD	D,(HL)
			LD	HL,zv_E4CD
			CALL	add_b
			LD	A,(HL)
			INC	(HL)
			LD	(zv_E85C),A
			OR	A				; начало приёма / броска — звук замаха
			JP	NZ,.np
			PUSH	DE
			LD	A,(zv_E85A)
			OR	A
			JP	Z,.ns
			CP	0x23
			JP	Z,.sw
			LD	HL,zv_FECA
			CALL	add_a
			LD	A,(HL)
			OR	A
			JP	Z,.ns
.sw:		LD	A,B
			OR	A
			LD	A,SND_SW0
			JP	Z,.s0
			LD	A,SND_SW1
.s0:		CALL	plat_sound
.ns:		POP	DE
			XOR	A
.np:		EX	DE,HL
			CALL	add_a
			LD	A,(HL)
			OR	A
			JP	NZ,.go
			LD	HL,zv_E1ED
			CALL	add_b
			LD	(HL),0
			LD	HL,zv_E4CD
			CALL	add_b
			LD	(HL),0
			JP	.n
.go:		DEC	A
			CP	0x34
			JP	NC,.mv
			CP	0x23
			JP	C,.f
			SUB	2
.f:			LD	HL,(t_rec)
			LD	DE,9
			ADD	HL,DE
			LD	(HL),A
.mv:		LD	A,(zv_E85A)
			LD	L,A
			LD	H,0
			ADD	HL,HL
			LD	DE,zv_DDA8
			ADD	HL,DE
			LD	E,(HL)
			INC	HL
			LD	D,(HL)
			LD	A,(zv_E85C)
			ADD	A,A
			LD	L,A
			LD	H,0
			ADD	HL,DE
			LD	A,(HL)
			INC	HL
			LD	C,(HL)
			LD	D,A
			AND	0x7F
			RRCA
			RRCA
			AND	0x1F
			LD	E,A
			LD	HL,(t_rec)
			LD	A,D
			AND	0x80
			JP	NZ,.lt
			LD	A,(zv_E88B)
			OR	A
			JP	NZ,.r
			LD	A,(zv_E8A7)
			OR	A
			JP	NZ,.y
.r:			LD	A,(HL)
			ADD	A,E
			LD	(HL),A
			JP	.y
.lt:		LD	A,(zv_E88B)
			OR	A
			JP	NZ,.lf
			LD	A,(zv_E8A6)
			OR	A
			JP	NZ,.y
.lf:		LD	A,(HL)
			SUB	E
			LD	(HL),A
.y:			INC	HL				; Y = $E4D3[b] + C
			LD	A,C
			POP	BC
			PUSH	BC
			PUSH	HL
			LD	HL,zv_E4D3
			PUSH	AF
			LD	A,B
			CALL	add_a
			POP	AF
			ADD	A,(HL)
			POP	HL
			LD	(HL),A
.n:			POP	BC
			LD	A,B
			OR	A
			JP	NZ,.l
			RET

; --- $F4AC: X врагов 4..$18; близость к герою ------------------------------------------------------------
enemy_state: LD	B,5
.c:			LD	A,B
			CALL	rec_a
			LD	A,(HL)
			CP	4
			JP	NC,.c1
			LD	(HL),4
.c1:		CP	0x18
			JP	C,.c2
			LD	(HL),0x18
.c2:		DEC	B
			JP	NZ,.c
			XOR	A
			LD	(zv_E8A5),A
			LD	(zv_E8A7),A
			LD	(zv_E8A6),A
			LD	B,5
.l:			LD	A,B
			LD	(zv_E8A2),A
			CALL	rec_a
			PUSH	HL
			LD	DE,8
			ADD	HL,DE
			LD	A,(HL)
			POP	HL
			OR	A
			JP	NZ,.n
			LD	A,(zv_E1F3)
			OR	A
			JP	Z,.lt
			HERO_X
			SUB	(HL)
			JP	NC,.r1
			CPL
			INC	A
.r1:		CP	2
			JP	NC,.r2
			LD	C,A
			LD	A,1
			LD	(zv_E8A7),A
			LD	A,C
.r2:		CP	0x0A
			JP	NC,.n
			LD	A,1
			LD	(zv_E8A5),A
			JP	.n
.lt:		HERO_X
			ADD	A,2
			SUB	(HL)
			JP	NC,.l1
			CPL
			INC	A
.l1:		CP	4
			JP	NC,.l2
			LD	C,A
			LD	A,1
			LD	(zv_E8A6),A
			LD	A,C
.l2:		CP	0x0C
			JP	NC,.n
			LD	A,1
			LD	(zv_E8A5),A
.n:			DEC	B
			JP	NZ,.l
			RET

; --- $EDC2: бойцы 0..4: полоска энергии; без энергии — имя стирается -------------------------------------
bars:		LD	B,0
.l:			LD	A,B
			CALL	rec_a
			LD	(t_rec),HL
			LD	DE,8
			ADD	HL,DE
			LD	A,(HL)
			OR	A
			JP	Z,.ok
			INC	A
			JP	NZ,.n
.ok:		LD	A,0x0E
			CALL	fld
			LD	A,(HL)
			CP	3
			JP	NC,.n
			LD	A,0x0C
			CALL	fld
			LD	A,(HL)
			OR	A
			JP	NZ,.bar
			LD	A,0x0E
			CALL	fld
			LD	A,(HL)
			LD	(zv_EE90),A
			PUSH	BC
			LD	B,A
			LD	C,4
			CALL	print_name
			POP	BC
.bar:		PUSH	BC
			LD	A,0x0E
			CALL	fld
			LD	B,(HL)
			LD	A,0x0C
			CALL	fld
			LD	C,(HL)
			CALL	plat_bar		; B = строка, C = энергия
			POP	BC
			LD	A,0x0C
			CALL	fld
			LD	A,(HL)
			OR	A
			JP	NZ,.n
			LD	A,0x0E
			CALL	fld
			LD	(HL),0xFF
.n:			INC	B
			LD	A,B
			CP	5
			JP	NZ,.l
			RET

; --- $FC64: сброс вводов -----------------------------------------------------------------------------------
reset_inputs: LD	HL,zv_E1ED
			LD	A,(HL)
			CP	0x14
			JP	Z,.k
			LD	(HL),0
.k:			XOR	A
			LD	B,5
.l:			INC	HL
			LD	(HL),A
			DEC	B
			JP	NZ,.l
			LD	(zv_E4CD),A
			RET

; --- $FC41: враг рядом: шаг героя -> блок/приём --------------------------------------------------------
hero_near:	LD	A,(zv_E1ED)
			CP	3
			JP	Z,.b
			CP	7
			JP	Z,.b
			CP	4
			JP	Z,.c
			CP	8
			JP	Z,.c
			OR	A
			RET	NZ
			LD	A,0x11
			JP	.s
.b:			LD	A,0x2E
			JP	.s
.c:			LD	A,0x2F
.s:			LD	(zv_E1ED),A
			RET

; --- $FC78: действие героя ------------------------------------------------------------------------------
hero_action: LD	A,(zv_E8A5)
			OR	A
			CALL	NZ,hero_near
			LD	A,(zv_E1ED)
			CP	0x0D
			JP	NZ,.pk
			XOR	A
			LD	(zv_E88B),A
			LD	B,0				; у ZX здесь B = 0 после $E4FC
			CALL	proj_of
			JP	Z,.have
			LD	A,(zv_E4CD)
			OR	A
			JP	NZ,.pk
			LD	A,0x11
			LD	(zv_E1ED),A
			JP	.pk
.have:		LD	(t_pj),HL
			LD	A,(zv_E4CD)
			CP	4
			JP	Z,.fly
			JP	NC,.pk
			LD	DE,7
			ADD	HL,DE
			LD	(HL),0
			LD	HL,(zv_E461)
			LD	DE,0x1402
			ADD	HL,DE
			EX	DE,HL
			LD	HL,(t_pj)
			LD	(HL),E
			INC	HL
			LD	(HL),D
			INC	HL
			LD	(HL),E
			INC	HL
			LD	(HL),D
			LD	DE,3
			ADD	HL,DE
			LD	(HL),0x64
			INC	HL
			LD	(HL),0xFF
			JP	.pk
.fly:		LD	HL,(t_pj)
			INC	HL
			INC	HL
			INC	HL
			LD	A,(HL)
			ADD	A,2
			LD	(HL),A
			DEC	HL
			LD	A,(zv_E1F3)
			OR	A
			LD	A,0
			JP	Z,.f1
			LD	A,0x20
.f1:		LD	(HL),A
			LD	A,B
			DEC	A
			LD	HL,zv_E888
			CALL	add_a
			LD	(HL),0x64
			LD	HL,(t_pj)
			LD	DE,6
			ADD	HL,DE
			LD	(HL),0x64
			INC	HL
			LD	(HL),0x64
.pk:		LD	A,(zv_E1ED)
			CP	2
			JP	NZ,.ex
			XOR	A
			LD	(zv_E88B),A
			CALL	pick_up
.ex:		LD	A,(zv_E461)
			ADD	A,EX_D
			CP	2
			JP	NC,.rt
			XOR	A
			CALL	next_room
			OR	A
			JP	Z,.wl
			LD	A,0x18+EX_D
			LD	(zv_E461),A
			JP	reset_inputs
.wl:		LD	A,2-EX_D
			LD	(zv_E461),A
			RET
.rt:		CP	0x19+2*EX_D
			JP	C,.up
			LD	A,1
			CALL	next_room
			OR	A
			JP	Z,.wr
			LD	A,3-EX_D
			LD	(zv_E461),A
			JP	reset_inputs
.wr:		LD	A,0x19+EX_D
			LD	(zv_E461),A
			RET
.up:		SUB	EX_D
			LD	C,A
			LD	A,(zv_E1ED)
			CP	1
			JP	NZ,.dn
			LD	A,(zv_E4D9)
			OR	A
			JP	Z,.dn
			CP	C
			JP	Z,.cl
			INC	A
			CP	C
			JP	Z,.cl
			INC	A
			CP	C
			JP	NZ,.dn
.cl:		LD	A,(zv_E462)
			ADD	A,8
			CP	0x7C
			JP	NC,.top
			LD	(zv_E462),A
			LD	A,0x11
			LD	(zv_E46A),A
			CALL	draw
			JP	.cl
.top:		LD	A,2
			CALL	next_room
			LD	A,0x14
			LD	(zv_E462),A
			CALL	hole_x
			ADD	A,2
			LD	(zv_E461),A
			CALL	reset_inputs
			XOR	A
			LD	(zv_E1ED),A
			LD	(zv_E4CD),A
			RET
.dn:		LD	A,(zv_E1ED)
			CP	2
			RET	NZ
			LD	A,(zv_E4CD)
			CP	2
			RET	NZ
			LD	A,(zv_E4DA)
			OR	A
			RET	Z
			CP	C
			JP	Z,.go
			INC	A
			CP	C
			JP	Z,.go
			INC	A				; у ZX третья проверка без CP: INC A / RET NZ
			RET	NZ
.go:		LD	A,3
			CALL	next_room
			LD	A,0x14
			LD	(zv_E1ED),A
			XOR	A
			LD	(zv_E4CD),A
			LD	A,0x50
			LD	(zv_E462),A
			CALL	reset_inputs
			CALL	hole_x
			LD	(zv_E461),A
			RET
hole_x:		LD	A,(zv_E4BB)		; X дыры в потолке комнаты ($DBB5 + 2*ROOM)
			ADD	A,A
			LD	HL,zv_DBB5
			CALL	add_a
			LD	A,(HL)
			RET

; --- $E1F4: клавиши по таблице типа управления и Kempston -> ввод героя ----------------------------------
read_controls: LD	A,(zv_E1EC)
			LD	HL,zv_E021
			CALL	tword
			LD	C,1
.l:			LD	A,(HL)
			INC	HL
			PUSH	HL
			CALL	zx_in
			POP	HL
			AND	(HL)
			INC	HL
			INC	HL
			JP	NZ,.rl			; не нажата: перенос 0 (AND)
			SCF
.rl:		LD	A,C
			RLA
			LD	C,A
			JP	NC,.l
			CALL	zx_kemp
			CP	0x1B
			JP	C,.k
			XOR	A
.k:			OR	C
			AND	0x1F
			LD	(zv_E1ED),A
			LD	B,A
			LD	HL,zv_E244
			AND	0x10
			JP	Z,.t
			LD	A,(zv_E1F3)
			OR	A
			JP	Z,.t
			LD	HL,zv_E254
.t:			LD	A,B
			AND	0xEF
			CALL	add_a
			LD	A,(HL)
			LD	B,A
			LD	A,(zv_E1ED)
			AND	0x10
			LD	A,B
			JP	Z,.s
			ADD	A,9
.s:			LD	(zv_E1ED),A
			RET
