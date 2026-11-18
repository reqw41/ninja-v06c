; render.asm: вывод Ninja на Вектор без заднего буфера ZX. Поле (строки ZX 0..20) собирается по столбцам в
; полосе STRIP (байт точек на строку): тайлы TILE_MAP -> дыры -> идол -> бойцы 5..0 по маске -> оружие, потом
; полоса раскладывается в 3 плоскости по цвету клетки (AMAP): плоскость = (точки & (чернила^бумага)) ^ бумага.
; Строка экрана: i = 191 - строка ZX (снизу вверх, как таблица $D717 ZX); байт Вектора — (A0+столбец, 32+i).
; Перерисовываются прямоугольники изменившихся бойцов (старое ∪ новое), оружия, идола.
MAP_V		EQU	0x8AB7 - ZS			; карта тайлов 21 x 32
TGFX_V		EQU	0xD00C - ZS			; тайлы, 8 байт
MASK_OFS	EQU	0x2140				; маска кадра — данные + $2140

; ---- очистка экрана A000..FFFF (стек: прерывания запрещены) ----
scr_clear:	DI
			LD	HL,0
			ADD	HL,SP
			LD	(.ssp+1),HL
			LD	SP,0
	IF	EX_D
			LD	DE,0xFFFF			; владелец 18.11 («пол с HUD одним серым, вместе с бордюром»): E000 = FF — всё
.l:			REPT	8					; вне комнаты серое (номер 1 — серый пол во всех комнатах), A000/C000 = 0;
			PUSH	DE					; нижние 16 строк экрана (байты 00..0F столбца) — чёрные (владелец 18.11)
			ENDR
			LD	HL,0
			ADD	HL,SP
			LD	A,L
			SUB	0x10
			JP	Z,.d				; следующие 16 байт — 00..0F: чёрные (A = 0)
			CP	0xF0
			JP	NZ,.k
			LD	A,H					; новый столбец: E1..FF — снова серый, E000 и ниже — 0
			CP	0xE1
			SBC	A,A
			CPL
.d:			LD	D,A
			LD	E,A
.k:			LD	A,H
	ELSE
			LD	DE,0
.l:			REPT	32
			PUSH	DE
			ENDR
			LD	HL,0
			ADD	HL,SP
			LD	A,H
	ENDIF
			CP	0xA0
			JP	NZ,.l
			LD	A,L					; до самого A000 (шаг 64)
			OR	A
			JP	NZ,.l
.ssp:		LD	SP,0
			EI
			RET

; ---- маски цвета клетки: A = атрибут ZX -> операнды pm_* (плоскости A000/C000/E000 = биты 2/1/0) ----
setm:		PUSH	HL					; тот же цвет, что в прошлый раз, — маски уже готовы
			LD	HL,sm_last
			CP	(HL)
			POP	HL
			RET	Z
			LD	(sm_last),A
			PUSH	BC
			PUSH	DE
			LD	C,A
			RRCA
			RRCA
			RRCA
			AND	7
			LD	D,A					; бумага
			LD	A,C
			AND	7
			XOR	D
			LD	E,A					; чернила ^ бумага
			AND	4
			CALL	ff
			LD	(pm_i2+1),A
			LD	A,D
			AND	4
			CALL	ff
			LD	(pm_p2+1),A
			LD	A,E
			AND	2
			CALL	ff
			LD	(pm_i1+1),A
			LD	A,D
			AND	2
			CALL	ff
			LD	(pm_p1+1),A
			LD	A,E
			AND	1
			CALL	ff
			LD	(pm_i0+1),A
			LD	A,D
			AND	1
			CALL	ff
			LD	(pm_p0+1),A
			POP	DE
			POP	BC
			RET
sm_last:	DB	0xFF
ff:			ADD	A,0xFF				; A != 0 -> FF, 0 -> 0
			SBC	A,A
			RET
; байт точек C -> 3 плоскости по (HL): H — плоскость A000 этого столбца
put3:		LD	A,C
pm_i2:		AND	0
pm_p2:		XOR	0
			LD	(HL),A
			LD	A,H
			ADD	A,0x20
			LD	H,A
			LD	A,C
pm_i1:		AND	0
pm_p1:		XOR	0
			LD	(HL),A
			LD	A,H
			ADD	A,0x20
			LD	H,A
			LD	A,C
pm_i0:		AND	0
pm_p0:		XOR	0
			LD	(HL),A
			LD	A,H
			SUB	0x40
			LD	H,A
			RET

; ---- клетка HUD/текста: pr_cell (0..767), точки 8 байт по DE, цвет — AMAP[клетки] ----
cell_draw:	LD	HL,(pr_cell)
			PUSH	HL
			LD	BC,AMAP
			ADD	HL,BC
			LD	A,(HL)
			CALL	setm
			POP	HL
			LD	A,L
			AND	31
			ADD	A,0xA0
			LD	B,A					; плоскость A000 столбца
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL				; H = строка клетки (cell*8 >> 8 = R)
			CALL	row_low
			LD	H,B
			LD	B,8
.r:			LD	A,(DE)
			LD	C,A
			CALL	put3
			INC	DE
			DEC	L
			DEC	B
			JP	NZ,.r
			RET

; ---- печать строки ZX (HL): $16 строка столбец, $11 цвет, знаки — свой шрифт; pr_big — двойная высота ----
vprint:		LD	A,(HL)
			OR	A
			RET	Z
			INC	HL
			CP	0x16
			JP	NZ,.c
			LD	A,(HL)				; AT строка, столбец -> клетка
			INC	HL
			PUSH	HL
			LD	L,A
			LD	H,0
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			EX	DE,HL
			POP	HL
			LD	A,(HL)
			INC	HL
			ADD	A,E
			LD	E,A
			EX	DE,HL
			LD	(pr_cell),HL
			EX	DE,HL
			JP	vprint
.c:			CP	0x11
			JP	NZ,.ch
			LD	A,(HL)
			INC	HL
			LD	(pr_color),A
			JP	vprint
.ch:		PUSH	HL
			CALL	pr_char
			POP	HL
			JP	vprint
; знак A в pr_cell цветом pr_color; pr_cell + 1
pr_char:	SUB	32
			LD	L,A
			LD	H,0
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			LD	DE,font
			ADD	HL,DE
			EX	DE,HL				; DE = знак
			LD	A,(pr_big)
			OR	A
			JP	NZ,.big
			CALL	pr_attr
			CALL	cell_draw
			JP	.nx
.big:		LD	HL,pr_buf			; строки знака дважды: 16 байт
			LD	B,8
.d:			LD	A,(DE)
			LD	(HL),A
			INC	HL
			LD	(HL),A
			INC	HL
			INC	DE
			DEC	B
			JP	NZ,.d
			CALL	pr_attr
			LD	DE,pr_buf
			CALL	cell_draw
			LD	HL,(pr_cell)
			PUSH	HL
			LD	BC,32
			ADD	HL,BC
			LD	(pr_cell),HL
			CALL	pr_attr
			LD	DE,pr_buf+8
			CALL	cell_draw
			POP	HL
			LD	(pr_cell),HL
.nx:		LD	HL,(pr_cell)
			INC	HL
			LD	(pr_cell),HL
			RET
pr_attr:	LD	HL,(pr_cell)		; AMAP[клетки] = pr_color (строки HUD 21..23 — телесный на чёрном, как CPC)
			LD	A,H
			CP	high 672
			LD	A,(pr_color)
			JP	C,.s
			JP	NZ,.h
			LD	A,L
			CP	low 672
			LD	A,(pr_color)
			JP	C,.s
.h:
	IF	EX_D
			LD	A,0x08				; HUD: чёрный на сером (как ST)
	ELSE
			LD	A,3
	ENDIF
.s:			LD	BC,AMAP
			ADD	HL,BC
			LD	(HL),A
			RET
pr_cell:	DW	0
pr_color:	DB	7
pr_big:		DB	0
pr_buf:		DS	16

; ---- точки платформы для логики ----
; $FB40..$FB6A: очистка экрана, APPROACHING <комната> двойной высоты
plat_approach:
			DI						; как Atari: на экране APPROACHING песня на паузе ($CC = $FF), регистры
			LD	A,0xFF				; заглушены — иначе песня успевает включить ноту, и та застывает гулом
			LD	(snd_cc),A
			CALL	snd_mute
			EI
	IF	EX_D
			LD	A,1					; имена бойцов на экране APPROACHING не печатать (владелец 18.11): nm_chk
			LD	(nm_on),A
	ENDIF
			LD	HL,pal_appr			; экран APPROACHING: чёрный, текст жёлтый (7), HUD — телесный (3)
			CALL	pal_set8
			LD	A,0xFF
			LD	(bar_disp),A
			LD	(bar_disp+1),A
			LD	(bar_disp+2),A
			CALL	scr_clear
			LD	HL,AMAP
			LD	BC,768
	IF	EX_D
AP_AT		EQU	0x0A				; надпись — оранжевым (перо 2) на сером 1 (владелец 18.11: «почему не на сером»);
	ELSE							; номера 4..7 — уже палитра комнаты (ставится, пока экран APPROACHING виден)
AP_AT		EQU	7
	ENDIF
.f:			LD	(HL),AP_AT
			INC	HL
			DEC	BC
			LD	A,B
			OR	C
			JP	NZ,.f
			LD	A,AP_AT
			LD	(pr_color),A
			LD	A,1
			LD	(pr_big),A
			LD	HL,zv_DB8C
			CALL	vprint
			LD	HL,zv_D900
			LD	A,(zv_E4BB)
			LD	B,A
			INC	B
.s:			DEC	B
			JP	Z,.p
.z:			LD	A,(HL)
			INC	HL
			OR	A
			JP	NZ,.z
			JP	.s
.p:			CALL	vprint
			XOR	A
			LD	(pr_big),A
			RET
; $F5F2: имя C в слоте B (строка 21, столбцы 0/13/24) текущим цветом печати
plat_name:	LD	A,B
			LD	HL,slot_col
			CALL	add_a
			LD	A,(HL)
			ADD	A,low (21*32)
			LD	L,A
			LD	H,high (21*32)
			LD	(pr_cell),HL
			LD	A,C
			LD	HL,zv_F61C
			CALL	tword
			JP	vprint
	IF	EX_D
slot_col:	DB	1,14,25				; имена и полоски — на знакоместо правее (владелец 19.11)
	ELSE
slot_col:	DB	0,13,24
	ENDIF
bar_disp:	DB	0xFF,0xFF,0xFF		; энергия на экране по слотам (FF — нет)
; $EDE8..$EE14: полоска энергии C в слоте B: 4 клетки строки 22, строки 1..5 — узор $DC1F + 4*C
plat_bar:	LD	A,B					; та же энергия в том же слоте — не рисовать
			LD	HL,bar_disp
			CALL	add_a
			LD	A,(HL)
			CP	C
			RET	Z
			LD	(HL),C
			LD	A,B
			LD	HL,slot_col
			CALL	add_a
			LD	A,(HL)
			ADD	A,low (22*32)
			LD	L,A
			LD	H,high (22*32)
			LD	(pr_cell),HL
			LD	A,C
			ADD	A,A
			ADD	A,A
			LD	HL,zv_DC1F
			CALL	add_a
			LD	B,4
.c:			LD	A,(HL)
			INC	HL
			PUSH	HL
			PUSH	BC
			LD	HL,pr_buf
			LD	(HL),0
			INC	HL
			LD	B,5
.r:			LD	(HL),A
			INC	HL
			DEC	B
			JP	NZ,.r
			LD	(HL),0
			INC	HL
			LD	(HL),0
			LD	DE,pr_buf
			CALL	cell_draw
			LD	HL,(pr_cell)
			INC	HL
			LD	(pr_cell),HL
			POP	BC
			POP	HL
			DEC	B
			JP	NZ,.c
			RET
; $F5CB: строки 21..23 — цвет 7, строка 22 — 3 (точки не трогаются: перекраска видна со следующим выводом); SCORE / IDOLS
plat_hudinit:
			LD	A,0xFF
			LD	(bar_disp),A
			LD	(bar_disp+1),A
			LD	(bar_disp+2),A
	IF	EX_D
			CALL	hi_rst				; оружие в HUD — перерисовать, отложенные имена — напечатать (stk.asm)
	ENDIF
			LD	HL,21*32			; строки 21..23 — телесный на чёрном (как CPC), полоски энергии — серые
			LD	(pr_cell),HL
			LD	B,96
.a:			PUSH	BC
			LD	A,B					; строка 22 (полоски энергии) — серый 1 (владелец 15.11)
			SUB	33
			CP	32
	IF	EX_D
			LD	A,0x08				; HUD на сером: текст чёрный, полоски энергии оранжевые (как ST — красные)
			JP	NC,.c3
			LD	A,0x0A
	ELSE
			LD	A,3
			JP	NC,.c3
			LD	A,1
	ENDIF
.c3:		CALL	recolor
			LD	HL,(pr_cell)
			INC	HL
			LD	(pr_cell),HL
			POP	BC
			DEC	B
			JP	NZ,.a
			LD	HL,zv_DB63
			JP	vprint
; перекраска клетки pr_cell в цвет A (как запись атрибута ZX): точки восстанавливаются из плоскости, где
; чернила и бумага старого цвета различаются (если совпадают — точек не видно, клетка пуста)
recolor:	PUSH	AF
			LD	HL,(pr_cell)
			LD	DE,AMAP
			ADD	HL,DE
			LD	C,(HL)				; старый цвет
			POP	AF
			LD	(HL),A
			LD	A,C
			RRCA
			RRCA
			RRCA
			XOR	C
			AND	7					; чернила ^ бумага
			LD	B,0xA0
			LD	E,4
.p:			LD	D,A
			AND	E
			JP	NZ,.g
			LD	A,B
			ADD	A,0x20
			LD	B,A
			LD	A,E
			RRCA
			LD	E,A
			LD	A,D
			CP	0
			JP	NZ,.p
			LD	DE,zero8			; цвета совпадали — пусто
			JP	cell_draw
.g:			LD	A,C					; бумага старого цвета в этой плоскости -> маска
			RRCA
			RRCA
			RRCA
			AND	E
			CALL	ff
			LD	D,A
			LD	HL,(pr_cell)		; адрес клетки в плоскости B
			LD	A,L
			AND	31
			ADD	A,B
			LD	B,A
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			CALL	row_low
			LD	H,B
			LD	BC,pr_buf
			LD	E,8
.r:			LD	A,(HL)
			XOR	D
			LD	(BC),A
			INC	BC
			DEC	L
			DEC	E
			JP	NZ,.r
			LD	DE,pr_buf
			JP	cell_draw
zero8:		DS	8
; $EAA7: счёт и число идолов
plat_hud:	LD	HL,zv_DB81
			CALL	vprint
	IF	EX_D
			JP	idol_hud			; идолы — значками (sound.asm)
	ELSE
			LD	HL,zv_DB7A
			JP	vprint
	ENDIF

; ---- комната: поля карты, атрибуты (AMAP — столбцы 4..35, MARG_A — поля), свои тайлы, всё поле ----
plat_room:	CALL	marg_build			; поток ещё в ROOMBUF (= AMAP)
			LD	HL,TGFX_V + 8*T_9C	; тайл $A0 = тайл $9C, в комнате 1 — перо 2 (у ZX логика его стирает;
			LD	DE,TGFX_V + 8*T_A0	; здесь — обе плоскости пера, плотная таблица)
			LD	A,(zv_E4BB)
			DEC	A
			LD	C,A
			LD	B,8
.t0:		LD	A,C
			OR	A
			LD	A,(HL)
			JP	NZ,.t3
			XOR	A
.t3:		LD	(DE),A
			INC	HL
			INC	DE
			DEC	B
			JP	NZ,.t0
			LD	HL,tile_b + 8*T_9C
			LD	DE,tile_b + 8*T_A0
			LD	B,8
.t1:		LD	A,C
			OR	A
			LD	A,(HL)
			JP	NZ,.t2
			LD	A,0xFC				; комната 1: у CPC тайл $A0 — сплошное перо 2 (оранжевые стены, снимок MAME)
.t2:		LD	(DE),A
			INC	HL
			INC	DE
			DEC	B
			JP	NZ,.t1
			LD	A,(zv_E4BB)			; палитра и полосы строк комнаты CPC (владелец 15.11: комнаты как CPC)
			LD	L,A
			LD	H,0
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			LD	DE,pal_rooms
			ADD	HL,DE
			CALL	pal_set8
			LD	A,(zv_E4BB)
			LD	HL,room_runs
			CALL	tword
			LD	(rr_room),HL
			CALL	fl_patch			; нижняя линия пола — на 8 строк ниже (field_lo.asm); ct_or = 0
			LD	A,(zv_E4D9)			; свои тайлы: дыра в потолке, в полу, идол
			OR	A
			LD	HL,ct_hc
			CALL	NZ,ct_apply
			LD	A,(zv_E4DA)
			OR	A
			LD	HL,ct_hf
			CALL	NZ,ct_apply
			LD	A,(zv_E4DB)
			LD	(idol_col),A
			LD	A,(zv_E4DC)
			LD	(idol_on),A
			OR	A
			LD	A,1
			LD	(ct_or),A
			LD	A,(idol_col)
			AND	31
			CALL	NZ,ct_idol2			; идол CPC: силуэт жёлтым пером, затем чёрный узор
			CALL	cb_build			; готовые клетки комнаты (схема Montezuma / Bruce Lee)
	IF	EX_D
			CALL	r21_diag			; диагонали пола ниже нижней линии (field_lo.asm)
	ENDIF
			CALL	cb_idol
			XOR	A					; на экране — ни бойцов, ни оружия
			LD	HL,disp
			LD	B,8*6+5*3
.z:			LD	(HL),A
			INC	HL
			DEC	B
			JP	NZ,.z
			LD	HL,cur
			LD	B,8*6+5*3
.z2:		LD	(HL),A
			INC	HL
			DEC	B
			JP	NZ,.z2
			LD	A,1
			LD	(rb_c0),A
			LD	A,31
			LD	(rb_c1),A
			LD	A,24
			LD	(rb_lo),A
			LD	A,199
			LD	(rb_hi),A
			XOR	A					; вся комната — прямо на экран, все 3 плоскости (после APPROACHING в A000 полосы
			LD	(band_ok),A			; пола остатки надписей); потом — сборка полосы пола по комнате (bo_calc)
			CALL	rect_draw
			JP	bo_calc
fx_w:		DB	0
rm_n:		DB	0

; ---- проход: что изменилось — перерисовать (ждёт TICK кадров с прошлого вывода) ----
plat_draw:	CALL	snd_idle			; простой: шум на счётчик
			LD	A,(frames)
			LD	HL,last_draw
			SUB	(HL)
			CP	TICK
			JP	C,plat_draw
			LD	A,(frames)
			LD	(last_draw),A
			CALL	snd_mode			; песня / подыгрывание по наличию врага
			CALL	spr_orient			; направление сменилось — развернуть кадры
			LD	B,0					; новые состояния бойцов
.a:			PUSH	BC
			CALL	act_state
			POP	BC
			INC	B
			LD	A,B
			CP	6
			JP	NZ,.a
			LD	B,0					; бойцы: старое ∪ новое
.c:			PUSH	BC
			LD	A,B
			CALL	act_rect
			POP	BC
			INC	B
			LD	A,B
			CP	6
			JP	NZ,.c
			CALL	rl_flush
			LD	HL,cur
			LD	DE,disp
			LD	B,8*6
.cp:		LD	A,(HL)
			LD	(DE),A
			INC	HL
			INC	DE
			DEC	B
			JP	NZ,.cp
			LD	B,0					; оружие
.p:			PUSH	BC
			LD	A,B
			CALL	proj_upd
			POP	BC
			INC	B
			LD	A,B
			CP	3
			JP	NZ,.p
			LD	A,(zv_E4DC)			; идол: взят / появился — подмена готовых клеток
			LD	HL,idol_on
			CP	(HL)
			RET	Z
			LD	(HL),A
			CALL	il_set
.ir:		LD	A,(idol_col)		; точки 32 + 6X .. +11
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
			LD	(rb_c0),A
			LD	A,B
			ADD	A,17				; идол CPC — 18 точек (3 тайла)
			RRCA
			RRCA
			RRCA
			AND	0x1F
			INC	A
			LD	(rb_c1),A
			LD	A,40				; строки клеток 18..19 (i = 8 * (24 - строка))
			LD	(rb_lo),A
			LD	A,55
			LD	(rb_hi),A
			JP	il_draw				; идол в A000: его клетки — в 3 плоскостях (field_lo.asm)
idol_on:	DB	0
idol_col:	DB	0

; HL = cur + 8*A ; DE = disp + 8*A
ent_k:		ADD	A,A
			ADD	A,A
			ADD	A,A
			LD	E,A
			LD	D,0
			LD	HL,disp
			ADD	HL,DE
			PUSH	HL
			LD	HL,cur
			ADD	HL,DE
			POP	DE
			RET
; боец B -> cur: видим, X (байт, со знаком), низ, верх (строки i), ширина, заголовок кадра CPC (2), кадр | разворот<<7
; (gen/cpc.asm: кадры уже распакованы по столбцам; разворот — общий, spr_m)
act_state:	LD	A,B
			LD	(as_k),A
			CALL	ent_k
			LD	(as_ent),HL
			LD	A,B
			CALL	rec_a
			LD	(t_rec),HL
			LD	A,8
			CALL	fld
			LD	A,(HL)
			INC	A
			CP	4
			LD	HL,(as_ent)
			LD	(HL),0
			RET	NC					; состояние 3 — нет на экране
			LD	(HL),1
			LD	A,9
			CALL	fld
			LD	A,(HL)				; кадр ZX
			LD	(as_f),A
			LD	A,(spr_m)			; разворот — общий (кадры развёрнуты на месте)
			LD	(as_m),A
			LD	A,(as_f)			; ходьба героя (9..14): готовый кадр по X mod 4 и лицу (50..53 вправо,
			SUB	9					; 54..57 влево), не развёрнутый, сдвиг зашит — без вращений
			CP	6
			JP	NC,.nw
			CP	3					; 12..14 — лицом вправо при spr_m = 0
			LD	A,(as_m)
			CCF
			ADC	A,0
			AND	1					; 1 — лицом вправо
			XOR	1
			ADD	A,A
			ADD	A,A					; 0 — вправо, 4 — влево
			LD	C,A
			LD	HL,(t_rec)
			LD	A,(HL)				; X & 3
			AND	3
			ADD	A,C
			ADD	A,50
			LD	(as_f),A
			XOR	A
			LD	(as_m),A
.nw:		LD	A,(as_f)
			LD	HL,cpc_frp			; заголовок кадра CPC
			CALL	tword
			LD	(as_hdr),HL
			LD	HL,(as_hdr)			; позиция (точки экрана) = 32 + 6X + ox (разворот: 6wzx - ox - 8wv вместо ox)
			LD	C,(HL)				; ox
			INC	HL
			LD	A,(HL)				; wv
			LD	(as_wv),A
			LD	A,(as_m)
			OR	A
			LD	A,C
			JP	Z,.nm
			INC	HL
			INC	HL
			INC	HL
			INC	HL					; +5: wzx
			LD	A,(HL)
			LD	B,A
			ADD	A,A
			ADD	A,B
			ADD	A,A					; 6wzx
			SUB	C
			LD	C,A
			LD	A,(as_wv)
			ADD	A,A
			ADD	A,A
			ADD	A,A
			LD	B,A
			LD	A,C
			SUB	B
.nm:		LD	(as_off),A
			LD	HL,(t_rec)
			LD	A,(HL)				; X со знаком
			LD	L,A
			ADD	A,A
			SBC	A,A
			LD	H,A
			LD	D,H
			LD	E,L
			ADD	HL,HL
			ADD	HL,DE
			ADD	HL,HL				; 6X
			LD	DE,32+128			; +128: позиция + 128 > 0
			ADD	HL,DE
			LD	A,(as_off)
			LD	E,A
			ADD	A,A
			SBC	A,A
			LD	D,A
			ADD	HL,DE
			LD	A,(as_f)			; не ходьба (как Bruce Lee) — по ближайшему байту: одна часть на столбец
			LD	C,A
			RRCA
			RRCA
			RRCA
			AND	7
			PUSH	HL
			LD	HL,walk_fr
			CALL	add_a
			LD	B,(HL)
			LD	A,C
			AND	7
			LD	C,A
			LD	A,1					; бит кадра: 1 << (f & 7)
			INC	C
.wb:		DEC	C
			JP	Z,.wt
			RLCA
			JP	.wb
.wt:		POP	HL
			AND	B
			JP	NZ,.ex
			LD	DE,4
			ADD	HL,DE
			LD	A,L
			AND	0xF8
			LD	L,A
.ex:		LD	A,L
			AND	7
			LD	(as_s),A			; сдвиг
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL				; H = (позиция + 128) >> 3
			LD	A,H
			SUB	16
			LD	HL,(as_ent)
			INC	HL
			LD	(HL),A				; col0
			PUSH	HL
			LD	HL,(as_hdr)			; верх i = Y + hzx - top; низ = верх - h + 1
			INC	HL
			INC	HL
			LD	C,(HL)				; top
			INC	HL
			LD	D,(HL)				; h
			INC	HL
			LD	E,(HL)				; hzx
			LD	HL,(t_rec)
			INC	HL
			LD	A,(HL)				; Y
			ADD	A,E
			SUB	C
			LD	C,A					; верх
			SUB	D
			INC	A					; низ
			POP	HL
			INC	HL
			LD	(HL),A
			INC	HL
			LD	(HL),C
			INC	HL
			LD	A,(as_s)			; ширина в столбцах экрана: wv (+1 при сдвиге)
			CP	1
			LD	A,(as_wv)
			CCF
			ADC	A,0
			LD	(HL),A
			INC	HL
			EX	DE,HL
			LD	HL,(as_hdr)			; заголовок (по нему вывод найдёт столбцы)
			EX	DE,HL
			LD	(HL),E
			INC	HL
			LD	(HL),D
			INC	HL
			LD	A,(as_m)			; разворот << 7 | сдвиг
			RRCA
			LD	B,A
			LD	A,(as_s)
			OR	B
			LD	(HL),A
			RET
as_wv:		DB	0
as_off:		DB	0
as_s:		DB	0
as_k:		DB	0
as_f:		DB	0
as_m:		DB	0
as_ent:		DW	0
as_hdr:		DW	0


; боец A: если cur != disp — перерисовать их общий прямоугольник
act_rect:	CALL	ent_k
			PUSH	HL
			PUSH	DE
			LD	B,8
.q:			LD	A,(DE)
			CP	(HL)
			JP	NZ,.ch
			INC	HL
			INC	DE
			DEC	B
			JP	NZ,.q
			POP	DE
			POP	HL
			RET
.ch:		LD	A,0xFF
			LD	(rb_c0),A
			LD	(rb_lo),A
			XOR	A
			LD	(rb_c1),A
			LD	(rb_hi),A
			POP	HL
			CALL	ent_add				; disp
			POP	HL
			CALL	ent_add				; cur
			LD	A,(rb_c1)
			OR	A
			RET	Z
			LD	A,(rl_n)			; в список (перекрывающиеся сольются в rl_flush)
			LD	C,A
			INC	A
			LD	(rl_n),A
			LD	A,C
			ADD	A,A
			ADD	A,A
			LD	HL,rl
			CALL	add_a
			LD	DE,rb_c0
			LD	B,4
.s:			LD	A,(DE)
			LD	(HL),A
			INC	HL
			INC	DE
			DEC	B
			JP	NZ,.s
			RET

; запись HL (видим, col0, низ, верх, ширина) — в прямоугольник rb_* (столбцы — с 1: столбец 0 — чёрное поле)
ent_add:	LD	A,(HL)
			OR	A
			RET	Z
			INC	HL
			LD	C,(HL)				; col0 (со знаком)
			INC	HL
			LD	D,(HL)				; низ
			INC	HL
			LD	E,(HL)				; верх
			INC	HL
			LD	A,(HL)
			ADD	A,C
			LD	B,A					; col0 + w
			CP	0x80
			RET	NC					; целиком левее экрана
			CP	2
			RET	C					; только в поле 0
			LD	A,C
			DEC	A
			CP	0x7F
			JP	C,.x
			LD	C,1					; col0 <= 0 -> 1
.x:			LD	A,(rb_c0)
			CP	C
			JP	C,.e1
			LD	A,C
			LD	(rb_c0),A
.e1:		LD	A,(rb_c1)
			CP	B
			JP	NC,.e2
			LD	A,B
			LD	(rb_c1),A
.e2:		LD	A,(rb_lo)
			CP	D
			JP	C,.e3
			LD	A,D
			LD	(rb_lo),A
.e3:		LD	A,(rb_hi)
			CP	E
			JP	NC,.e4
			LD	A,E
			LD	(rb_hi),A
.e4:		RET
; оружие A: как у ZX — нарисовано в проходе: видно на новом месте; стёрто и не нарисовано: не видно;
; ни то, ни другое — на экране остаётся прежнее
proj_upd:
	IF	EX_D
			PUSH	AF
			CALL	pj_held			; оружие в руках героя — не рисовать (fixes.asm)
			POP	AF
	ENDIF
			LD	C,A
			ADD	A,A
			ADD	A,A
			ADD	A,C					; 5*j
			LD	HL,pcur
			CALL	add_a
			PUSH	HL
			LD	A,C
			LD	HL,pj_dr
			CALL	add_a
			LD	A,(HL)
			OR	A
			JP	NZ,.dr
			LD	A,C
			LD	HL,pj_er
			CALL	add_a
			LD	A,(HL)
			POP	HL
			PUSH	HL
			LD	(HL),0
			OR	A
			JP	NZ,.cmp
			LD	DE,pdisp - pcur		; без изменений: cur = disp
			EX	DE,HL
			ADD	HL,DE
			LD	B,5
.kp:		LD	A,(HL)
			LD	(DE),A
			INC	HL
			INC	DE
			DEC	B
			JP	NZ,.kp
			JP	.cmp
.dr:		LD	A,C
			CALL	proj_j
			EX	DE,HL				; DE = запись оружия
			POP	HL
			PUSH	HL
			LD	(HL),1
			INC	HL
			LD	A,(DE)				; X -> точка экрана 32 + 6X (вся комната 40 тайлов: X -4..35, иначе не видно: 0)
			ADD	A,4
			CP	40
			LD	B,0
			JP	NC,.px
			SUB	4
			LD	B,A
			ADD	A,A
			ADD	A,B
			ADD	A,A
			ADD	A,32
			LD	B,A
.px:		LD	(HL),B
			INC	HL
			INC	DE
			LD	A,(DE)
			LD	(HL),A				; Y
			INC	HL
			PUSH	HL
			INC	DE
			INC	DE
			INC	DE
			LD	A,(DE)				; +4: картинка 8D57 или FF62
			INC	DE
			LD	HL,p6_ff62			; картинки 6 точек (gen/cpc.asm)
			OR	A
			JP	Z,.g
			LD	HL,p6_8d57
.g:			CALL	pj_lie				; +5: кадр (нож на полу — своя картинка, fixes.asm)
			ADD	A,A
			ADD	A,A
			ADD	A,A
			CALL	add_a
			EX	DE,HL
			POP	HL
			LD	(HL),E
			INC	HL
			LD	(HL),D
.cmp:		POP	HL					; pcur[j]; pdisp[j] = pcur[j] + (pdisp - pcur)
			LD	DE,pdisp - pcur
			EX	DE,HL
			ADD	HL,DE
			EX	DE,HL				; DE = pdisp
			PUSH	HL
			PUSH	DE
			LD	B,5
.q:			LD	A,(DE)
			CP	(HL)
			JP	NZ,.ch
			INC	HL
			INC	DE
			DEC	B
			JP	NZ,.q
			POP	DE
			POP	HL
			RET
.ch:		POP	HL					; pdisp: стереть старое
			PUSH	HL
			CALL	p_rect
			POP	DE
			POP	HL					; pcur -> pdisp, нарисовать новое
			PUSH	HL
			LD	B,5
.c:			LD	A,(HL)
			LD	(DE),A
			INC	HL
			INC	DE
			DEC	B
			JP	NZ,.c
			POP	HL
p_rect:		LD	A,(HL)
			OR	A
			RET	Z
			INC	HL
			LD	A,(HL)				; точка экрана (0 — не видно)
			OR	A
			RET	Z
			LD	B,A
			RRCA
			RRCA
			RRCA
			AND	0x1F
			LD	(rb_c0),A
			INC	A
			LD	C,A
			LD	A,B
			AND	7
			CP	3					; 6 точек со сдвигом > 2 — и в соседний столбец
			LD	A,C
			JP	C,.w
			INC	A
.w:			LD	(rb_c1),A
			INC	HL
			LD	A,(HL)
			LD	(rb_hi),A
			SUB	7
			LD	(rb_lo),A
			JP	rect_draw

cur:		DS	8*6					; бойцы: видим, X, низ, верх, ширина, буфер (2), кадр|разворот
pcur:		DS	5*3					; оружие: видно, точка экрана, Y, картинка (2)
disp:		DS	8*6
pdisp:		DS	5*3
rb_c0:		DB	0					; прямоугольник: столбцы c0..c1-1, строки i lo..hi
rb_c1:		DB	0
rb_lo:		DB	0
rb_hi:		DB	0

; ---- перерисовать прямоугольник rb_* (поле: i 24..199 — фон поднят на 8 строк, строка клеток 21 — пол под комнатой; столбцы 0..31) ----
rect_draw:	LD	A,(rb_lo)			; строки — целыми клетками (i: 8m..8m+7)
			CP	24
			JP	NC,.l
			LD	A,24
.l:			AND	0xF8
			LD	(rc_lo),A
			LD	A,(rb_hi)
			CP	200
			JP	C,.h
			LD	A,199
.h:			OR	7
			LD	(rc_hi),A
			LD	HL,rc_lo
			CP	(HL)
			RET	C
			LD	A,(rb_c1)			; столбцы 1..30 (0 и 31 — чёрные поля)
			CP	32
			JP	C,.c
			LD	A,31
.c:			LD	(rb_c1),A
			LD	A,(rb_c0)
.col:		LD	HL,rb_c1
			CP	(HL)
			RET	NC
			LD	(rc_col),A
			CALL	col_draw
			LD	A,(rc_col)
			INC	A
			JP	.col
rc_col:		DB	0
rc_lo:		DB	0
rc_hi:		DB	0

; ---- столбец экрана rc_col (1..30), строки rc_lo..rc_hi: фон 40 тайлов по 6 точек в полосе, оружие, цвета
; в полосы плоскостей, бойцы, на экран (field.asm) ----

