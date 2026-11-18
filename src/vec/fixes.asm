; fixes.asm: правки логики для краёв комнаты 40 тайлов (EX_D, только боевой образ) — в области кадров (место)

	IF	EX_D
; оружие в руке выбывшего врага (нокаут / ушёл) у ZX так и висит в воздухе у руки (владелец 2..6, Y $39) —
; падает на пол (владелец 15.11: «оружие прыгает»): владелец 0, цель — пол ($1E), летит (+7)
proj_orphan: LD	C,0
.l:			LD	A,C
			LD	HL,zv_E888
			CALL	add_a
			LD	A,(HL)				; владелец = номер бойца + 1: герой 1 (держит — не трогать), враги 2..6
			SUB	2
			CP	5
			JP	NC,.n
			INC	A					; номер врага 1..5
			PUSH	HL
			CALL	rec_a
			LD	DE,8
			ADD	HL,DE
			LD	A,(HL)				; состояние врага
			POP	HL
			OR	A
			JP	NZ,.dr				; выбыл — роняет
			LD	A,(HL)				; активен: бросает ($23) — держит, иначе (бросок прерван) — роняет
			DEC	A
			PUSH	HL
			LD	HL,zv_E1ED
			CALL	add_a
			LD	A,(HL)
			POP	HL
			CP	0x23
			JP	Z,.n
			LD	A,C					; в полёте (+7) — не трогать
			PUSH	HL
			CALL	proj_j
			LD	DE,7
			ADD	HL,DE
			LD	A,(HL)
			POP	HL
			OR	A
			JP	NZ,.n
.dr:
			LD	(HL),0
			LD	A,C
			CALL	proj_j
			CALL	pj_floor			; цель — пол под ним (Y кратно 3 от пола)
			LD	DE,6
			ADD	HL,DE
			LD	(HL),0x28
			INC	HL
			LD	(HL),1
.n:			INC	C
			LD	A,C
			CP	3
			JP	NZ,.l
			RET
	ENDIF

	IF	EX_D
; подобранное оружие (владелец — боец, цель Y $39) у ZX летит с пола к руке по 6 точек и 3 строки за проход и у героя
; висит там до броска — не рисовать (владелец 18.11: «собираешь — оно в воздухе прыгает», «дёргается на земле»):
; у врага нож пропадает с пола и появляется в руке (Y $36). Бросок — цель не $39, рисуется.
; Для вывода — «стёрто, не нарисовано». A — номер оружия
pj_held:	LD	C,A
			LD	HL,zv_E888
			CALL	add_a
			LD	A,(HL)
			OR	A					; ничьё — рисуется
			RET	Z
			LD	A,C
			CALL	proj_j
			INC	HL
			LD	A,(HL)
			CP	0x27				; на полу и первые 2 шага подъёма (Y $21, $24) — видно: как у CPC, нож приподнимается
			RET	C					; и уходит в присевшего бойца (у CPC оружие под бойцом, снимки MAME 18.11)
			INC	HL
			INC	HL
			LD	A,(HL)				; цель Y $39 — летит к руке (подбор) или в руке героя
			CP	0x39
			RET	NZ
			LD	A,C
			LD	HL,pj_dr
			CALL	add_a
			LD	(HL),0
			LD	A,C
			LD	HL,pj_er
			CALL	add_a
			LD	(HL),1
			RET
	ENDIF

; кадр оружия для вывода (proj_upd): HL — таблица картинок, DE — запись +5; выход: A — кадр, HL — таблица.
; Нож на полу (Y $1E) — как CPC, с рукоятью и крестовиной (владелец 18.11: «ножи не палочками, а как в CPC», «с ручками
; как в CPC»): X чётный — рукоять слева, нечётный — справа
pj_lie:		LD	A,L
			CP	low p6_8d57			; нож (сюрикен — p6_ff62)
			LD	A,(DE)				; кадр
			RET	NZ
			LD	B,A
			DEC	DE
			DEC	DE
			DEC	DE
			DEC	DE					; +1: Y
			LD	A,(DE)
			CP	0x1E
			LD	A,B
			RET	NZ
			DEC	DE					; +0: X
			LD	A,(DE)
			AND	1
			LD	HL,p6_lie
			RET
idol_ico:	DB	0x10,0x38,0x28,0x10,0x38,0x54,0x7C,0x38	; значок идола в HUD (силуэт идола ST, idol_hud)
p6_lie:		DB	0,0,0x40,0xF8,0x40,0,0,0		; как CPC (снимок MAME: 5 x 3 — рукоять, крестовина, клинок 3): «+----»,
			DB	0,0,0x10,0xF8,0x10,0,0,0		; «----+»; 5 точек из 6 — соседние не сливаются (биты 7..2)

; идол (столбец A): силуэт — перо 3 (ct_idol, в строках идола — жёлтый номер комнаты), узор — перо 1 (ct_idolb: те же
; свои тайлы, бит 1 пера &= ~узор)
ct_idol2:	PUSH	AF
			LD	HL,ct_idol
			CALL	ct_apply
			XOR	A
			LD	(ct_or),A
			POP	AF					; HL — сразу за ct_idol = ct_idolb
			ASSERT	ct_idolb == ct_idol + 3 + 3 * 11
			JP	ct_apply

