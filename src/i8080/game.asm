; Ход игры (перевод src/model/game.js): проход $ED23, новая игра $EC2D, идол $F554, очки $EA76.

; --- $ED23: один проход ---------------------------------------------------------------------------------
pass:		CALL	random
			CALL	check_hits
			LD	A,(zv_E8A9)
			OR	A
			CALL	NZ,hit
			LD	A,(zv_EE8C)
			OR	A
			CALL	NZ,ko
			LD	A,(zv_EE8E)
			OR	A
			CALL	NZ,hero_death
			CALL	enemy_throw
			CALL	hero_action
			CALL	enemy_state
			CALL	enemy_ai
			CALL	animate_all
			CALL	draw
			CALL	bars
	IF	EX_D
			CALL	wpn_hud				; оружие в руках героя — в HUD (src/vec/sound.asm)
	ENDIF
			LD	A,(zv_E8A8)
			OR	A
			JP	Z,.w
			DEC	A
			LD	(zv_E8A8),A
.w:			LD	A,(zv_E4CC)
			CP	7
			JP	NZ,.i
			XOR	A
			LD	(zv_E88C),A
			LD	A,(zv_E4BB)
			CP	4
			JP	Z,plat_winner
.i:			LD	A,(zv_E4BB)
			CP	10
			JP	Z,.it
			CALL	idol_room
			JP	NC,.sc
.it:		CALL	idol_take
.sc:		CALL	score_tick
			CALL	C,score_hud
			LD	A,(zv_E1ED)
			OR	A
			JP	NZ,.k
			CALL	read_controls
			LD	A,(zv_E1ED)
			OR	A
			JP	Z,.k
			LD	A,1
			LD	(zv_E8A4),A
.k:			LD	A,0xFD
			CALL	zx_in
			AND	0x10
			JP	NZ,.f
.p:			XOR	A				; G — пауза до клавиши управления
			LD	(zv_E1ED),A
			CALL	read_controls
			LD	A,(zv_E1ED)
			OR	A
			JP	Z,.p
			RET
.f:			LD	A,0xFD
			CALL	zx_in
			AND	8
			JP	Z,plat_menu		; F — в меню
			RET

; --- $EA76: 2 очка из $E4C2 в счёт; перенос — начислено -----------------------------------------------
score_tick:	LD	HL,(zv_E4C2)
			LD	A,H
			OR	L
			RET	Z
			DEC	HL
			DEC	HL
			LD	(zv_E4C2),HL
			LD	HL,zv_DB8A
			LD	A,(HL)
			ADD	A,2
.l:			CP	0x3A
			JP	NC,.o
			LD	(HL),A
			SCF
			RET
.o:			SUB	10
			LD	(HL),A
			DEC	HL
			LD	A,(HL)
			OR	A
			SCF
			RET	Z
			INC	A
			JP	.l

; --- $F554: идол у края по направлению ------------------------------------------------------------------
idol_take:	LD	A,(zv_E88C)
			OR	A
			RET	Z
			LD	A,(zv_E1F3)
			OR	A
			LD	A,(zv_E461)
			JP	Z,.l
			ADD	A,EX_D				; вид ×1.5: X бывает отрицательным (вход на краях 40 тайлов) — сравнение по X + 4,
			CP	0x19+EX_D			; пороги — как у ZX (идол нарисован там же)
			RET	C
			JP	.t
.l:			ADD	A,EX_D
			CP	3+EX_D
			RET	NC
.t:			LD	A,SND_IDOL
			CALL	plat_sound
			XOR	A
			LD	(zv_E4DB),A
			LD	(zv_E4DC),A
			LD	HL,zv_E4CC
			INC	(HL)
			LD	HL,(zv_E4C2)
			LD	DE,0xC8
			ADD	HL,DE
			LD	(zv_E4C2),HL
			LD	A,(zv_E4BB)
			CP	10
			JP	Z,.e
			CALL	idol_room
			LD	(HL),0
.e:			LD	A,0x0F
			LD	(zv_E46D),A
			LD	A,(zv_E4CC)
			CP	6
			RET	NZ
			LD	A,7				; $F5B2: шестой идол открывает 17 вверх -> 10
			LD	(zv_DBD7),A
			LD	(zv_DBCA),A
			LD	A,0x0B
			LD	(zv_D8DD),A
			RET

; --- $EC2D: новая игра (A = тип управления) -------------------------------------------------------------
new_game:	LD	(zv_E1EC),A
			LD	HL,zv_E4BC
			LD	B,6
			XOR	A
.z:			LD	(HL),A
			INC	HL
			DEC	B
			JP	NZ,.z
			LD	HL,zv_E4BC
			LD	B,6
.r:			CALL	random
			AND	0x1F
			CP	0x14
			JP	NC,.r
			INC	A
			PUSH	HL
			LD	HL,zv_E4BC
			LD	D,6
.c:			CP	(HL)
			JP	Z,.dup
			INC	HL
			DEC	D
			JP	NZ,.c
			POP	HL
			CP	0x0B
			JP	Z,.r
			LD	(HL),A
			INC	HL
			DEC	B
			JP	NZ,.r
			JP	.x
.dup:		POP	HL
			JP	.r
.x:			XOR	A
			LD	(zv_EE8E),A
			LD	HL,zv_E866
			LD	B,0x25
.y:			LD	(HL),A
			INC	HL
			DEC	B
			JP	NZ,.y
			LD	(zv_E4CC),A
			LD	(zv_DBD7),A
			LD	(zv_DBCA),A
			LD	(zv_E4C2),A
			LD	(zv_E4C3),A
			LD	(zv_D8DD),A
			LD	HL,zv_E461
			LD	B,0x5A
.q:			LD	(HL),A
			INC	HL
			DEC	B
			JP	NZ,.q
			INC	A
			LD	(zv_E86D),A
			LD	(zv_E878),A
			LD	(zv_E883),A
			LD	(zv_E88C),A
			LD	(zv_E1F3),A
			LD	A,4
			LD	(zv_E88D),A
			LD	A,0x0F
			LD	(zv_E46D),A
			LD	A,0xFF
			LD	(zv_EE90),A
			LD	HL,zv_DB86
			LD	B,5
			LD	A,0x30
.s:			LD	(HL),A
			INC	HL
			DEC	B
			JP	NZ,.s
			CALL	reset_inputs
			LD	HL,zv_FA8B
			LD	DE,zv_DCE3
			CALL	cp4
			LD	HL,zv_FA87
			LD	DE,zv_DCDE
			CALL	cp4
			LD	A,(zv_F924)
			OR	A
			JP	Z,.nf
			LD	HL,0x2140
			LD	(zv_E864),HL
			CALL	flip_frames
			LD	HL,0
			LD	(zv_E864),HL
			CALL	flip_frames
.nf:		LD	HL,0
			LD	(zv_E4C2),HL
			CALL	place_enemies
			XOR	A
			LD	(zv_F924),A
			LD	A,6
			LD	(zv_E4BB),A
			LD	A,3
			LD	(zv_E478),A
			LD	(zv_E487),A
			LD	(zv_E496),A
			LD	(zv_E4A5),A
			LD	(zv_E4B3),A		; у ZX — поле +7 бойца 5
			LD	A,1
			CALL	next_room
			JP	plat_hudinit		; $F5CB
