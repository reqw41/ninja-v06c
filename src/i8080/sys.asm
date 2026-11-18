; Служебное (перевод src/model/sys.js и общих помощников): ГСЧ $DECA, сложения, таблицы, записи бойцов.
EX_D		DEFL	0
	IFDEF	VEC_CPC	; вид ×1.5: комната 40 тайлов — края переходов и стены на 4 тайла дальше
	IFNDEF	TESTFONT	; (сборка для сверки шаг в шаг с ZX — края ZX)
EX_D		DEFL	4						; (X со знаком: сравнения по X + 4)
	ENDIF
	ENDIF
; X героя для ударов и расстояний: при краях 40 тайлов (EX_D) — прижат к диапазону ZX 2..$19 (8X и разности —
; в байте; в обычной игре то же самое, что X)
	MACRO	HERO_X
	IF	EX_D
			CALL	hero_xc
	ELSE
			LD	A,(zv_E461)
	ENDIF
	ENDM

; --- $DECA: сдвиговый регистр 32 бита DEF1..DEF4; A = новый DEF1; сохраняет BC, DE, HL --------------------
random:		PUSH	HL
			LD	A,(zv_DEF1)
			AND	0x48
			ADD	A,0x38
			ADD	A,A
			ADD	A,A				; перенос = бит 6 суммы
			LD	HL,zv_DEF4
			LD	A,(HL)
			RLA
			LD	(HL),A
			DEC	HL
			LD	A,(HL)
			RLA
			LD	(HL),A
			DEC	HL
			LD	A,(HL)
			RLA
			LD	(HL),A
			DEC	HL
			LD	A,(HL)
			RLA
			LD	(HL),A
			POP	HL
			RET

; HL += A (без знака); HL += B
add_b:		LD	A,B
add_a:		ADD	A,L
			LD	L,A
			RET	NC
			INC	H
			RET
; $E2B4: HL = слово по адресу HL + (2*A mod 256)
tword:		ADD	A,A
			CALL	add_a
			LD	A,(HL)
			INC	HL
			LD	H,(HL)
			LD	L,A
			RET
; HL = запись бойца A ($E461 + 15*A); сохраняет BC, DE
rec_a:		PUSH	DE
			LD	E,A
			ADD	A,A
			ADD	A,A
			ADD	A,A
			ADD	A,A
			SUB	E
			LD	L,A
			LD	H,0
			LD	DE,zv_E461
			ADD	HL,DE
			POP	DE
			RET
; HL = запись оружия A ($E866 + 11*A); сохраняет BC, DE
proj_j:		PUSH	DE
			LD	E,A
			ADD	A,A
			ADD	A,A
			ADD	A,E
			ADD	A,A
			ADD	A,E
			LD	L,A
			LD	H,0
			LD	DE,zv_E866
			ADD	HL,DE
			POP	DE
			RET
; HL = (t_rec) + A
fld:		LD	HL,(t_rec)
			JP	add_a
; $F063: перенос, если отрезки [L, L+H] и [E, E+D] не пересекаются
apart:		LD	A,H
			ADD	A,L
			CP	E
			RET	C
			LD	A,D
			ADD	A,E
			CP	L
			RET
; 4 байта HL -> DE
cp4:		LD	B,4
.l:			LD	A,(HL)
			LD	(DE),A
			INC	HL
			INC	DE
			DEC	B
			JP	NZ,.l
			RET
; текущий боец ($E8A2): HL += номер; ввод/таймер/тип/X
cur_hl:		LD	A,(zv_E8A2)
			JP	add_a
set_input:	PUSH	HL				; $E7D8: ввод и запомненный ввод бойца = A
			PUSH	AF
			LD	HL,zv_E1ED
			CALL	cur_hl
			POP	AF
			LD	(HL),A
			PUSH	AF
			LD	HL,zv_E899
			CALL	cur_hl
			POP	AF
			LD	(HL),A
			POP	HL
			RET
set_timer:	PUSH	HL				; $E7E7
			PUSH	AF
			LD	HL,zv_E893
			CALL	cur_hl
			POP	AF
			LD	(HL),A
			POP	HL
			RET
kind:		LD	HL,zv_E88D		; тип врага: 0 бандит, 1 каратист, 2 ниндзя
			CALL	cur_hl
			LD	A,(HL)
			AND	3
			RET
curX:		LD	A,(zv_E8A2)		; $E809: X текущего бойца
			CALL	rec_a
			LD	A,(HL)
			RET
; $F5F2: имя C (0 THUG, 1 KARATEKA, 2 NINJA, 3 HERO, 4 — стереть) в строке B — вывод платформы
	IF	EX_D
print_name:	JP	nm_chk				; Вектор (боевой образ): на экране APPROACHING имена откладываются
	ELSE
print_name:	JP	plat_name
	ENDIF

; --- временные ячейки (не ZX; стенд их не сверяет) -----------------------------------------------------
scratch:
t_rec:		DW	0
t_pj:		DW	0
t_flag:		DW	0
t_p:		DW	0
t_inp:		DB	0
t_v:		DB	0
t_x:		DB	0
t_l:		DB	0
t_dir:		DB	0
pj_er:		DS	3				; оружие стёрто в этом проходе ($F21B)
pj_dr:		DS	3				; нарисовано ($F1B4)
t_wpn:		DB	0				; удар оружием (звук — канал 0)
scratch_end:

t_hx:		DB	0
