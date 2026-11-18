; field_lo.asm: клетки идола (в нижней области — место; запас полос готовых клеток после неё)
; ---- идол: клетки с ним и без него (при взятии — подмена в карте клеток) ----
cb_idol:	XOR	A
			LD	(il_n),A
			LD	A,(idol_on)
			OR	A
			RET	Z
			LD	A,(idol_col)		; точки 32 + 6X .. +11 -> столбцы экрана c0..c1
			AND	31
			LD	B,A
			ADD	A,A
			ADD	A,B
			ADD	A,A
			ADD	A,32
			LD	B,A
			RRCA
			RRCA
			RRCA
			AND	0x1F
			LD	(il_c0),A
			LD	A,B
			ADD	A,17				; идол CPC — 18 точек (3 тайла)
			RRCA
			RRCA
			RRCA
			AND	0x1F
			INC	A
			LD	(il_c1),A
			LD	A,(idol_col)		; исходные тайлы на место
			AND	31
			LD	HL,ct_idol
			CALL	ct_back
			LD	A,(il_c0)
.c:			LD	(cb_b),A
			LD	A,18
.r:			LD	(cb_rr),A
			LD	C,A
			CALL	cb_colset
			CALL	cb_one
			LD	C,A					; без идола
			PUSH	BC
			CALL	cb_mapp
			LD	A,(il_n)
			LD	B,A
			INC	A
			LD	(il_n),A
			LD	A,B
			ADD	A,A
			ADD	A,A
			EX	DE,HL
			LD	HL,il_ent
			CALL	add_a
			LD	(HL),E				; адрес в карте, с идолом, без
			INC	HL
			LD	(HL),D
			INC	HL
			LD	A,(DE)
			LD	(HL),A
			INC	HL
			POP	BC
			LD	(HL),C
			LD	A,(cb_rr)
			INC	A
			CP	20
			JP	NZ,.r
			LD	A,(cb_b)
			INC	A
			LD	HL,il_c1
			CP	(HL)
			JP	NZ,.c
			RET
; карта клеток: идол есть (A != 0) / нет
il_set:		LD	C,A
			LD	A,(il_n)
			OR	A
			RET	Z
			LD	B,A
			LD	HL,il_ent
.l:			LD	E,(HL)
			INC	HL
			LD	D,(HL)
			INC	HL
			LD	A,C
			OR	A
			LD	A,(HL)
			JP	NZ,.s
			INC	HL
			LD	A,(HL)
			DEC	HL
.s:			LD	(DE),A
			INC	HL
			INC	HL
			DEC	B
			JP	NZ,.l
			RET
il_n:		DB	0
il_c0:		DB	0
il_c1:		DB	0
il_ent:		DS	4*8

	IF	EX_D
; вид ×1.5 (владелец 15.11: «оружие крутится»): брошенное к краю экрана (цель X 0 / $1F) и ни в кого не попавшее у ZX
; качается по Y и крутится на краю вечно; край ZX у Вектора — посреди комнаты: падает на пол, как после попадания
; ($F3E8: цель Y $1E, +6 = $28, владелец 0). HL — запись (+0)
proj_land:	PUSH	HL
			LD	HL,4				; флаг владельца — на стеке proj_move: [HL][возврат][владелец]
			ADD	HL,SP
			LD	E,(HL)
			INC	HL
			LD	D,(HL)
			POP	HL
			LD	A,(DE)
			CP	7
			RET	C
			CALL	pj_floor
			PUSH	HL
			LD	BC,6
			ADD	HL,BC
			LD	(HL),0x28
			XOR	A
			LD	(DE),A
			POP	HL
			RET
; перспектива пола ниже нижней линии (владелец 18.11: «как в ST — продолжим вниз за горизонтальную линию»): строка
; клеток 21 (серый пол под комнатой) в столбцах экрана 4, 5 (диагональ 7 — продолжение 12 из тайла 6) и 26, 27
; (диагональ 8 — продолжение 13 из тайла 33): клетка из тайлов (t0, t0 + 1) по своим указателям, остальное — серое
r21_diag:	LD	BC,r21_t
			LD	A,4
			CALL	.c
			LD	A,5
			CALL	.c
			INC	BC
			LD	A,26
			CALL	.c
			LD	A,27
.c:			PUSH	BC
			LD	(cb_b),A
			LD	C,21
			CALL	cb_colset
			POP	HL
			PUSH	HL
			LD	(fa_p),HL
			INC	HL
			LD	(fb_p),HL
			LD	A,21
			LD	(cb_rr),A
			CALL	cb_one
			PUSH	AF
			CALL	cb_mapp
			POP	AF
			LD	(HL),A
			POP	BC
			INC	BC
			RET
r21_t:		DB	0,7,0,0,8,0
; оружие HL (+0) — на пол под ним: цель X = X, цель Y $1E (падает шагом 3 — не ниже пола: proj_move); портит A
pj_floor:	LD	A,(HL)
			INC	HL
			INC	HL
			LD	(HL),A				; +2: цель X
			INC	HL
			LD	(HL),0x1E			; +3: цель Y
			DEC	HL
			DEC	HL
			DEC	HL
			RET
	ENDIF

; ---- полоса пола (строки клеток 14..20, i < BAND_I): бойцы в 2 плоскостях C000/E000, A000 не трогается. Владелец
; 16.11 (вариант Б): в полосе в C000/E000 только серый пол, линии пола — номер 5 (A000, tools/cpcroom.py); пока в
; комнате идол (жёлтый — в A000) — обычный путь в 3 плоскости; band_ok ----
bo_calc:	LD	A,(zv_E4BB)			; владелец 17.11: линия пола в плоскостях бойцов — где A000 полосы пуста
			LD	HL,room_band		; (все комнаты, кроме 10: там цвет линии свой — номер 5 в A000)
			CALL	add_a
			LD	A,(HL)
			LD	(band_ok),A
			RET
il_draw		EQU	rect_draw
band_ok:	DB	0
; вывод без сборки в полосах: бойцы (contrib, ct_h) и оружие (op_w) — прямо на экран столбца rc_col, в 3 плоскости
; (A000 &= ~M — линии пола под бойцом гаснут, ушёл боец — клетка снова из тайла); страницы — в команды
pg_set:		LD	A,(rc_col)
			ADD	A,0xA0
			LD	(ct_h+1),A
			LD	(ct_pa+1),A
			LD	(ow_a+1),A
			ADD	A,0x20
			LD	(ct_pc+1),A
			LD	(ow_c+1),A
			ADD	A,0x20
			LD	(ct_pe+1),A
			LD	(ow_e+1),A
			RET
; клетка F8+биты (cl_uni): плоскость p — FF, если бит p, иначе 00; HL = верх клетки на экране (A000). Без цикла:
; плоскости по очереди вниз, вверх, вниз (строку не возвращать). Модель tools/rmodel.js: 56 % клеток
cu_fill:	LD	C,A
			RRCA
			LD	C,A
			SBC	A,A
			LD	(HL),A
			DEC	L
			LD	(HL),A
			DEC	L
			LD	(HL),A
			DEC	L
			LD	(HL),A
			DEC	L
			LD	(HL),A
			DEC	L
			LD	(HL),A
			DEC	L
			LD	(HL),A
			DEC	L
			LD	(HL),A
			LD	A,H
			ADD	A,0x20
			LD	H,A
			LD	A,C
			RRCA
			LD	C,A
			SBC	A,A
			LD	(HL),A
			INC	L
			LD	(HL),A
			INC	L
			LD	(HL),A
			INC	L
			LD	(HL),A
			INC	L
			LD	(HL),A
			INC	L
			LD	(HL),A
			INC	L
			LD	(HL),A
			INC	L
			LD	(HL),A
			LD	A,H
			ADD	A,0x20
			LD	H,A
			LD	A,C
			RRCA
			SBC	A,A
			LD	(HL),A
			DEC	L
			LD	(HL),A
			DEC	L
			LD	(HL),A
			DEC	L
			LD	(HL),A
			DEC	L
			LD	(HL),A
			DEC	L
			LD	(HL),A
			DEC	L
			LD	(HL),A
			DEC	L
			LD	(HL),A
			JP	cd_nx
; оружие (цвет 3) на экран: строка C, точки A (ov_proj): A000 &= ~m, C000 |= m, E000 |= m
op_w:		PUSH	AF
			LD	A,C
			ADD	A,32
			LD	L,A
			POP	AF
ow_a:		LD	H,0
			PUSH	AF
			CPL
			AND	(HL)
			LD	(HL),A
			POP	AF
ow_c:		LD	H,0
			PUSH	AF
			OR	(HL)
			LD	(HL),A
			POP	AF
ow_e:		LD	H,0
			OR	(HL)
			LD	(HL),A
			RET

; ---- нижняя линия пола на 8 строк ниже (владелец 16.11: «сдвигаем оранжевую линию вниз»): ряд 19 — серый (тайл 0)
; с концами диагоналей без линии (тайлы 7 / 8, как в ряду 18), ряд 20 — линия внизу (тайл 9), диагонали — тайлы 12 / 13
; (наклон 4 точки на ряд тайлов: тайл продолжается тем же). Ряды 19, 20 одинаковы во всех комнатах. Тайл t: 4..35 —
; MAP_V + 32 R + t - 4, 0..3 / 36..39 — MARG_T + 8 R (+0..3 / +4..7) ----
fl_patch:	LD	HL,MAP_V+32*19
			LD	BC,0x2000
			CALL	.f
			LD	BC,0x2009
			CALL	.f
			LD	HL,MARG_T+8*19
			LD	BC,0x0800
			CALL	.f
			LD	BC,0x0809
			CALL	.f
			LD	HL,MAP_V+32*19+7-4
			LD	(HL),7
			LD	HL,MAP_V+32*19+32-4
			LD	(HL),8
			LD	HL,MAP_V+32*20+6-4
			LD	(HL),12
			LD	HL,MAP_V+32*20+33-4
			LD	(HL),13
			XOR	A
			LD	(ct_or),A
			RET
.f:			LD	(HL),C
			INC	HL
			DEC	B
			JP	NZ,.f
			RET

; H = строка клетки R -> L = младший байт верхней строки точек: 223 - 8R, HUD (R >= 21) — на символьную строку
; ниже поля, 215 - 8R (владелец 17.11)
row_low:	LD	A,H
			ADD	A,A
			ADD	A,A
			ADD	A,A
			CPL
			ADD	A,224
			LD	L,A
			LD	A,H
			CP	21
			RET	C
			LD	A,L
			SUB	8
			LD	L,A
			RET
	IF	EX_D
; ---- имена бойцов на экране APPROACHING (владелец 18.11: «внизу пишется HERO, KARATEKA» — не надо): пока экран
; названия комнаты (nm_on, ставит plat_approach), имя C слота B запоминается; plat_hudinit (hi_rst) печатает их
nm_chk:		LD	A,(nm_on)
			OR	A
			JP	Z,plat_name
			LD	A,B
			LD	HL,nm_buf
			CALL	add_a
			LD	(HL),C
			RET
nm_replay:	XOR	A
			LD	(nm_on),A
			LD	B,A
.l:			LD	A,B
			LD	HL,nm_buf
			CALL	add_a
			LD	C,(HL)
			LD	(HL),0xFF
			LD	A,C
			INC	A
			PUSH	BC
			CALL	NZ,plat_name
			POP	BC
			INC	B
			LD	A,B
			CP	3
			JP	NZ,.l
			RET
nm_on:		DB	0
nm_buf:		DB	0xFF,0xFF,0xFF
	ENDIF
