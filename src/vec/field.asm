; field.asm: поле в геометрии оригинала Atari/CPC ×1.5 (владелец 14.11.2026). Комната — 40 тайлов по 6 точек
; (240 точек) от x = 8: столбцы экрана 1..30, столбцы 0 и 31 — чёрные поля. Тайл t (0..39): 4..35 — карта ZX
; MAP_V (столбец t - 4, шаг 32), 0..3 и 36..39 — MARG_T (поля карты, шаг 8; строит plat_room из потоков).
; Атрибуты — AMAP (шаг 32) и MARG_A (шаг 8). Байт экрана столбца b = тайл t0 << o | тайл t0+1 >> (6 - o),
; f = 8(b - 1), t0 = f / 6, o = f % 6 (col_t0o). Тайлы — 6 точек в битах 7..2 (gen/tiles6.asm на месте тайлов ZX).
; Цвет клетки байта: маски двух тайлов, смешанные по Mf (FC / F0 / C0). Бойцы — кадры ×0.75 (точки от левого
; края рамки ZX), на экране со сдвигом s = позиция & 7: каждый столбец данных даёт части двум столбцам экрана.
BAND_I		EQU	88					; строки i < 88 — полоса пола (клетки 14..21, строки комнаты 112..175)
MARG_T		EQU	0x3500				; тайлы полей: 21 строка x 8 (столбцы 0..3, 36..39)
MARG_A		EQU	MARG_T + 168		; их атрибуты
			ASSERT	MARG_A + 168 <= 0x8AB7 - ZS

; ---- готовые клетки комнаты (схема Montezuma / Bruce Lee, владелец 15.11): при входе в комнату каждая клетка
; экрана (столбец 1..30, строка 0..20) строится один раз — 3 полосы плоскостей по 8 байт (тайлы CPC ×1.5, перья ->
; цвета по полосам строк); одинаковые полосы и клетки — одни (pool_a / POOL_B, cdesc). Вывод: клетка без бойца и
; оружия — копия полос прямо на экран; с ними — в полосы CP_H, поверх оружие и бойцы, затем на экран ----
TB_D		EQU	tile_b - TGFX_V
CB_PA		EQU	CP_H*256			; бит 0 пера, строка k — CB_PA + 7 - k (сборка — временно в полосах)
CB_PB		EQU	CP_H*256 + 8		; бит 1 пера
CB_O		EQU	CP_H*256 + 16		; 3 полосы по 8 (A000, C000, E000), сверху вниз
CB_NX		EQU	(CP_H+1)*256		; цепочки полос (номер + 1)
CB_BK		EQU	(CP_H+2)*256		; корзины по хэшу полосы (номер + 1)
CMAP		EQU	AMAP				; карта клеток по столбцам: (столбец - 1) * 22 + строка -> номер клетки (22 * 30 < 672 —
								; строки HUD в AMAP не задеты); строка 21 — серый пол под комнатой (владелец 16.11)
NA			EQU	(0x2000 - pool_a) / 8
POOL_B		EQU	MARG_T + 168
NB			EQU	(0x8AB7 - ZS - POOL_B) / 8
	IF	NA + NB > 240
NS_MAX		EQU	240
	ELSE
NS_MAX		EQU	NA + NB
	ENDIF
NC_MAX		EQU	140				; клеток в комнате до 131 + 6 клеток идола
cb_build:	XOR	A
			LD	(cb_ns),A
			LD	(cb_nc),A
			LD	HL,CB_BK
			LD	B,0
.z:			LD	(HL),A
			INC	HL
			DEC	B
			JP	NZ,.z
			LD	HL,STRIP_H*256		; слоты кэша пусты (тайла FF нет)
			LD	B,21*3*4
			LD	A,0xFF
.zs:		LD	(HL),A
			INC	HL
			DEC	B
			JP	NZ,.zs
			CALL	cb_z0				; полосы 0 — нули, 1 — FF (cd_pl: заливка без запаса)
			LD	HL,STRIP_H*256
			CALL	st_find
			LD	A,1
			LD	(cb_b),A
.col:		LD	C,0
			CALL	cb_colset
			XOR	A
			LD	(cb_rr),A
.cell:		CALL	cb_one
			PUSH	AF
			CALL	cb_mapp
			POP	AF
			LD	(HL),A
			LD	A,(cb_rr)
			INC	A
			LD	(cb_rr),A
			CP	21
			JP	NZ,.cell
			INC	HL					; строка 21 — серый пол (номер 1 = только E000: клетка F8 + 4, cu_fill)
			LD	(HL),0xFC
			LD	A,(cb_b)
			INC	A
			LD	(cb_b),A
			CP	31
			JP	NZ,.col
			RET
; HL = CMAP + (cb_b - 1) * 22 + cb_rr
cb_mapp:	LD	A,(cb_b)
			DEC	A
			LD	L,A
			LD	H,0
			LD	D,H
			LD	E,L
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,DE				; 5
			ADD	HL,HL
			ADD	HL,DE				; 11
			ADD	HL,HL				; 22
			LD	A,(cb_rr)
			CALL	add_a
			LD	DE,CMAP
			ADD	HL,DE
			RET
; столбец cb_b с клетки C: тайлы t0 / t0 + 1, вариант сборки по o, полоса строк для строки 8C
cb_colset:	LD	A,C
			LD	(f_r0),A
			ADD	A,A
			ADD	A,A
			ADD	A,A
			LD	(cb_y),A
			LD	A,(cb_b)			; f = 8(b - 1): t0 = f / 6, o = f % 6 (было таблицей col_t0o)
			DEC	A
			ADD	A,A
			ADD	A,A
			ADD	A,A
			LD	C,0
.dv:		CP	6
			JP	C,.dd
			SUB	6
			INC	C
			JP	.dv
.dd:		LD	B,A
			LD	A,C					; t0
			LD	C,B					; o
			PUSH	AF
			LD	A,C
			LD	(cb_o),A
			LD	HL,bgv_tab
			CALL	add_a
			LD	A,(HL)
			LD	(cb_v+1),A
			LD	(cb_v2+1),A
			INC	HL
			LD	A,(HL)
			LD	(cb_v+2),A
			LD	(cb_v2+2),A
			POP	AF
			PUSH	AF
			CALL	tsrc
			LD	(fa_p),HL
			EX	DE,HL
			LD	(cb_sa+1),HL
			POP	AF
			INC	A
			CALL	tsrc
			LD	(fb_p),HL
			EX	DE,HL
			LD	(cb_sb+1),HL
			LD	A,0xFF				; клетка выше — не в кэше
			LD	(cv_ta),A
			LD	HL,(rr_room)		; полоса строки cb_y: следующая начинается позже
			LD	B,(HL)
			INC	HL
.f:			DEC	B
			JP	Z,.go
			PUSH	HL
			LD	DE,4
			ADD	HL,DE
			LD	A,(cb_y)
			CP	(HL)
			POP	HL
			JP	C,.go
			LD	DE,4
			ADD	HL,DE
			JP	.f
.go:		LD	A,B
			INC	A
			LD	(rn_left),A
			LD	(rn_ptr),HL
; следующая полоса строк: операнды cf2 / cf1 / cf0, cb_ny — строка начала следующей (FF — нет)
cb_rnext:	PUSH	HL
			PUSH	BC
			LD	HL,(rn_ptr)
			INC	HL
			LD	A,(HL)
			CALL	.pf
			LD	(cf2+1),HL
			CALL	.nx
			CALL	.pf
			LD	(cf1+1),HL
			CALL	.nx
			CALL	.pf
			LD	(cf0+1),HL
			CALL	.nx
			LD	A,(rn_left)
			DEC	A
			LD	(rn_left),A
			LD	A,0xFF
			JP	Z,.nb
			LD	HL,(rn_ptr)
			LD	A,(HL)
.nb:		LD	(cb_ny),A
			POP	BC
			POP	HL
			RET
.pf:		LD	(rn_ptr),HL
			LD	HL,plf_tab
			JP	tword
.nx:		LD	HL,(rn_ptr)
			INC	HL
			LD	(rn_ptr),HL
			LD	A,(HL)
			RET
; клетка по указателям fa_p / fb_p (потом — клетка ниже): A = номер готовой клетки
cb_one:		LD	HL,(fa_p)
			LD	C,(HL)				; тайл t0
cb_sa:		LD	DE,0
			ADD	HL,DE
			LD	(fa_p),HL
			LD	HL,(fb_p)
			LD	B,(HL)				; тайл t0 + 1
cb_sb:		LD	DE,0
			ADD	HL,DE
			LD	(fb_p),HL
			LD	A,(cb_y)			; кэш: внутри клетки полоса строк не меняется — ключ (t0, t0+1, полоса)
			LD	D,A
			LD	A,(cb_ny)
			SUB	D
			CP	8
			LD	A,0xFF
			JP	C,.nk
			LD	A,(rn_ptr)
.nk:		LD	(ck_r),A
			LD	A,C
			LD	(ck_a),A
			LD	A,B
			LD	(ck_b),A
			LD	A,(ck_r)
			INC	A
			JP	Z,.miss				; без ключа
			LD	HL,cv_ta			; та же клетка выше
			CALL	ck_cmp
			JP	Z,.hit
			CALL	ch_slot				; та же — три столбца левее (тот же сдвиг o)
			CALL	ck_cmp
			JP	NZ,.miss
.hit:		INC	HL
			INC	HL
			INC	HL
			LD	A,(HL)
			LD	(cv_ta+3),A
			PUSH	AF
			LD	HL,(ck_a)			; клетка выше := эта
			LD	(cv_ta),HL
			LD	A,(ck_r)
			LD	(cv_ta+2),A
			LD	A,(cb_y)
			ADD	A,8
			LD	(cb_y),A
			POP	AF
			RET
.miss:		LD	A,(ck_a)
			LD	C,A
			LD	A,(ck_b)
			LD	B,A
			CALL	.mk
			LD	(ck_i),A			; в кэш: выше и слот
			LD	HL,cv_ta
			CALL	ck_put
			LD	A,(ck_r)
			INC	A
			JP	Z,.nr
			CALL	ch_slot
			CALL	ck_put
.nr:		LD	A,(ck_i)
			RET
.mk:		LD	HL,tremap			; номера ZX -> плотная таблица тайлов
			LD	A,C
			CALL	add_a
			LD	C,(HL)
			LD	HL,tremap
			LD	A,B
			CALL	add_a
			LD	B,(HL)
			LD	L,B					; BC = точки тайла t0 + 1, HL = тайла t0
			LD	H,0
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			LD	DE,TGFX_V
			ADD	HL,DE
			PUSH	HL
			LD	L,C
			LD	H,0
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,DE
			POP	BC
			PUSH	HL
			PUSH	BC
			LD	DE,CB_PA+7
cb_v:		CALL	bg8_0				; бит 0 пера
			POP	HL
			LD	BC,TB_D
			ADD	HL,BC
			LD	B,H
			LD	C,L
			POP	HL
			LD	DE,TB_D
			ADD	HL,DE
			LD	DE,CB_PB+7
cb_v2:		CALL	bg8_0				; бит 1 пера
			LD	HL,CB_O				; 8 строк: перо -> 3 плоскости по полосе строк
cb_row:		LD	A,(cb_ny)
			LD	B,A
			LD	A,(cb_y)
			CP	B
			CALL	Z,cb_rnext
			LD	A,L
			CPL
			ADD	A,low CB_O + 8		; 7 - k
			LD	E,A
			LD	D,CP_H
			LD	A,(DE)
			LD	C,A
			LD	A,E
			ADD	A,8
			LD	E,A
			LD	A,(DE)
			LD	B,A
cf2:		CALL	plf0
			LD	A,L
			ADD	A,8
			LD	L,A
cf1:		CALL	plf0
			LD	A,L
			ADD	A,8
			LD	L,A
cf0:		CALL	plf0
			LD	A,L
			SUB	15
			LD	L,A
			LD	A,(cb_y)
			INC	A
			LD	(cb_y),A
			LD	A,L
			CP	low CB_O + 8
			JP	NZ,cb_row
			LD	HL,CB_O				; полосы — в запас (одинаковые — одна)
			CALL	st_find
			LD	(cb_s),A
			LD	HL,CB_O+8
			CALL	st_find
			LD	(cb_s+1),A
			CALL	st_inv				; E = ~C — номер FF без запаса (17.11: линия пола в C000, пол в E000)
			LD	(cb_s+2),A
			JP	cl_uni
; полоса E (CB_O+16) — дополнение полосы C (не заливки): номер FF (cd_pl: инверсия полосы C), иначе — в запас
st_inv:		LD	A,(cb_s+1)
			CP	2
			JP	C,.f
			LD	HL,CB_O+8
			LD	DE,CB_O+16
			LD	B,8
.c:			LD	A,(DE)
			CPL
			CP	(HL)
			JP	NZ,.f
			INC	HL
			INC	DE
			DEC	B
			JP	NZ,.c
			LD	A,0xFF
			RET
.f:			LD	HL,CB_O+16
			JP	st_find				; клетка из полос 0/FF — номер F8+биты (fgap3.asm)
; HL = слот кэша строки cb_rr и сдвига cb_o (STRIP: 21 x 3 x 4: t0, t0+1, полоса, номер)
ch_slot:	LD	A,(cb_rr)
			LD	L,A
			ADD	A,A
			ADD	A,L					; 3R
			LD	L,A
			LD	A,(cb_o)
			RRCA
			ADD	A,L
			ADD	A,A
			ADD	A,A
			LD	L,A
			LD	H,STRIP_H
			RET
; Z — ключ ck_a, ck_b, ck_r совпадает с (HL)
ck_cmp:		LD	A,(ck_a)
			CP	(HL)
			RET	NZ
			INC	HL
			LD	A,(ck_b)
			CP	(HL)
			DEC	HL
			RET	NZ
			INC	HL
			INC	HL
			LD	A,(ck_r)
			CP	(HL)
			DEC	HL
			DEC	HL
			RET
ck_put:		LD	A,(ck_a)
			LD	(HL),A
			INC	HL
			LD	A,(ck_b)
			LD	(HL),A
			INC	HL
			LD	A,(ck_r)
			LD	(HL),A
			INC	HL
			LD	A,(ck_i)
			LD	(HL),A
			RET
ck_a:		DB	0
ck_b:		DB	0
ck_r:		DB	0
ck_i:		DB	0
cv_ta:		DS	4					; клетка выше: t0, t0+1, полоса, номер
cb_o:		DB	0
; клетка (cb_s: 3 номера полос) — в описатели cdesc (одинаковые — одна): A = номер
cl_find:	LD	HL,cdesc
			LD	A,(cb_nc)
			LD	C,A
			LD	B,0
.l:			LD	A,B
			CP	C
			JP	Z,.new
			LD	A,(cb_s)
			CP	(HL)
			JP	NZ,.n
			INC	HL
			LD	A,(cb_s+1)
			CP	(HL)
			DEC	HL
			JP	NZ,.n
			INC	HL
			INC	HL
			LD	A,(cb_s+2)
			CP	(HL)
			DEC	HL
			DEC	HL
			JP	NZ,.n
			LD	A,B
			RET
.n:			INC	HL
			INC	HL
			INC	HL
			INC	B
			JP	.l
.new:		LD	A,C
			CP	NC_MAX
			JP	NC,.full
			LD	A,(cb_s)
			LD	(HL),A
			INC	HL
			LD	A,(cb_s+1)
			LD	(HL),A
			INC	HL
			LD	A,(cb_s+2)
			LD	(HL),A
			LD	A,C
			INC	A
			LD	(cb_nc),A
			DEC	A
			RET
.full:		XOR	A
			RET
; полоса HL (8 байт) -> номер в запасе (новая — добавить)
st_find:	LD	(sf_src),HL
			LD	B,8
			XOR	A
.h:			RLCA					; хэш: (h <<< 1) + байт, 256 корзин
			ADD	A,(HL)
			INC	HL
			DEC	B
			JP	NZ,.h
			LD	L,A
			LD	H,high CB_BK
			LD	(sf_bk),HL
			LD	A,(HL)
.c:			OR	A
			JP	Z,.new
			DEC	A
			LD	(sf_i),A
			CALL	st_addr
			EX	DE,HL
			LD	HL,(sf_src)
			LD	B,8
.cm:		LD	A,(DE)
			CP	(HL)
			JP	NZ,.nx
			INC	DE
			INC	HL
			DEC	B
			JP	NZ,.cm
			LD	A,(sf_i)
			RET
.nx:		LD	A,(sf_i)
			LD	L,A
			LD	H,high CB_NX
			LD	A,(HL)
			JP	.c
.new:		LD	A,(cb_ns)
			CP	NS_MAX
			JP	NC,.full
			LD	(sf_i),A
			INC	A
			LD	(cb_ns),A
			LD	A,(sf_i)
			CALL	st_addr
			EX	DE,HL
			LD	HL,(sf_src)
			LD	B,8
.cp:		LD	A,(HL)
			LD	(DE),A
			INC	HL
			INC	DE
			DEC	B
			JP	NZ,.cp
			LD	HL,(sf_bk)			; в начало цепочки корзины
			LD	C,(HL)
			LD	A,(sf_i)
			INC	A
			LD	(HL),A
			DEC	A
			LD	L,A
			LD	H,high CB_NX
			LD	(HL),C
			RET
.full:		XOR	A
			RET
; HL = адрес полосы A в запасе (портит DE)
st_addr:	CP	NA
			JP	NC,.b
			LD	L,A
			LD	H,0
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			LD	DE,pool_a
			ADD	HL,DE
			RET
.b:			SUB	NA
			LD	L,A
			LD	H,0
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			LD	DE,POOL_B
			ADD	HL,DE
			RET
bgv_tab:	DW	bg8_0, bg8_2, bg8_4
; тайл A (0..39) -> HL = клетка карты строки f_r0, DE = шаг строки
tsrc:		CP	4
			JP	C,.m
			CP	36
			JP	NC,.m2
			SUB	4
			LD	HL,MAP_V
			CALL	add_a
			LD	A,(f_r0)			; + 32 R0
			PUSH	HL
			LD	L,A
			LD	H,0
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			POP	DE
			ADD	HL,DE
			LD	DE,32
			RET
.m2:		SUB	32
.m:			LD	HL,MARG_T
			CALL	add_a
			LD	A,(f_r0)			; + 8 R0
			PUSH	HL
			LD	L,A
			LD	H,0
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			POP	DE
			ADD	HL,DE
			LD	DE,8
			RET
f_r0:		DB	0
fa_p:		DW	0
fb_p:		DW	0
cb_b:		DB	0
cb_rr:		DB	0
cb_y:		DB	0
cb_ny:		DB	0
cb_s:		DS	3
cb_ns:		DB	0
cb_nc:		DB	0
sf_src:		DW	0
sf_bk:		DW	0
sf_i:		DB	0
rr_room:	DW	0
rn_ptr:		DW	0
rn_left:	DB	0


; ---- столбец экрана rc_col (строки rc_lo..rc_hi целыми клетками): готовые клетки; где боец или оружие — в полосы,
; поверх них, на экран; каждый байт экрана пишется один раз ----
col_draw:	XOR	A					; полоса пола в 2 плоскостях (владелец 17.11): клетки полосы в прямоугольнике —
			LD	(sp_hi),A			; сборка в полосах C/E (CP_H+1, CP_H+2), бойцы и оружие туда же, затем на экран;
			LD	A,(band_ok)			; sp_lo..sp_hi — строки сборки (sp_hi = 0 — нет)
			OR	A
			JP	Z,.nb
			LD	A,(rc_lo)
			CP	BAND_I
			JP	NC,.nb
			LD	(sp_lo),A
			LD	A,(rc_hi)
			CP	BAND_I
			JP	C,.h
			LD	A,BAND_I-1
.h:			LD	(sp_hi),A
.nb:
			LD	A,(rc_hi)
			LD	(cd_i),A
			LD	A,(rc_col)			; карта: (столбец - 1) * 22 + строка — один раз на столбец, дальше +1
			LD	(cb_b),A			; (клетки столбца в карте подряд; владелец 15.11: «ускорь вывод»)
			LD	A,(rc_hi)
			RRCA
			RRCA
			RRCA
			AND	0x1F
			CPL
			ADD	A,25				; строка клетки = 24 - i / 8 (фон поднят на 8 строк, владелец 16.11)
			LD	(cb_rr),A
			CALL	cb_mapp
			LD	(cm_p),HL
cd_cell:	LD	HL,(cm_p)
			LD	A,(HL)
			INC	HL
			LD	(cm_p),HL
			LD	(cd_u),A			; F8..FF — клетка из полос 0/FF (cl_uni)
			LD	L,A
			LD	H,0
			LD	D,H
			LD	E,L
			ADD	HL,HL
			ADD	HL,DE
			LD	DE,cdesc
			ADD	HL,DE
			LD	(cd_p),HL
			LD	A,(cd_i)			; выше полосы пола — сразу на экран (владелец 17.11: «попробуем сборку убрать»)
			LD	B,A
			CP	BAND_I				; полоса пола под бойцами (sp_lo <= i <= sp_hi; sp_hi = 0 — нет): в полосы C/E
			JP	NC,.scr
			LD	A,(sp_hi)
			CP	B
			JP	C,.scr
			LD	A,(sp_lo)
			DEC	A
			CP	B
			JP	NC,.scr
			LD	A,(cd_u)
			CP	0xF8
			JP	NC,cu_strip
			LD	HL,(cd_p)			; A000 полосы пола пуста — её полоса не нужна
			INC	HL
			LD	(cd_p),HL
			LD	H,CP_H+1
			LD	L,B
			LD	A,1
			LD	(cd_st+1),A
			LD	B,2
			JP	cd_plc
.scr:		LD	A,(rc_col)
			ADD	A,0xA0
			LD	H,A
			LD	A,B
			ADD	A,32
			LD	L,A
			LD	A,0x20
.go:		LD	(cd_st+1),A
			LD	B,3
cd_plc:		LD	A,(cd_u)
			CP	0xF8
			JP	NC,cu_fill			; заливка клетки (fgap2.asm)
cd_pl:		PUSH	BC
			EX	DE,HL				; DE = куда
			LD	HL,(cd_p)
			LD	A,(HL)
			INC	HL
			LD	(cd_p),HL
			CP	2					; полосы 0 (нули) и 1 (FF) — 71 % плоскостей (модель rmodel.js): заливка
			JP	C,.fl
			CP	0xFF				; FF — дополнение полосы предыдущей плоскости (st_inv)
			JP	Z,.inv
			CP	NA					; st_addr на месте (без вызова)
			LD	BC,pool_a
			JP	C,.pa
			SUB	NA
			LD	BC,POOL_B
.pa:		LD	L,A
			LD	H,0
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,BC
			EX	DE,HL
			REPT	8
			LD	A,(DE)
			LD	(HL),A
			INC	DE
			DEC	L
			ENDR
			JP	.nx
.inv:		DEC	HL
			DEC	HL
			LD	A,(HL)				; номер полосы C
			CP	NA
			LD	BC,pool_a
			JP	C,.ia
			SUB	NA
			LD	BC,POOL_B
.ia:		LD	L,A
			LD	H,0
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,BC
			EX	DE,HL
			LD	B,8
.il:		LD	A,(DE)
			CPL
			LD	(HL),A
			INC	DE
			DEC	L
			DEC	B
			JP	NZ,.il
			JP	.nx
.fl:		EX	DE,HL
			CPL
			INC	A					; 0 -> 00, 1 -> FF
			REPT	8
			LD	(HL),A
			DEC	L
			ENDR
.nx:		LD	A,L
			ADD	A,8
			LD	L,A
			LD	A,H
cd_st:		ADD	A,0x20
			LD	H,A
			POP	BC
			DEC	B
			JP	NZ,cd_pl
cd_nx:		CALL	nz_tick
			LD	A,(cd_i)
			SUB	8
			LD	(cd_i),A
			LD	B,A
			LD	A,(rc_lo)
			DEC	A
			CP	B
			JP	NZ,cd_cell
			CALL	pg_set				; оружие и бойцы — поверх клеток (выше полосы пола — на экране, в ней — в полосах)
			CALL	ov_proj
			CALL	ov_actors
			JP	band_copy
cd_i:		DB	0
cd_u:		DB	0
cm_p:		DW	0
sp_lo:		DB	0
sp_hi:		DB	0
cd_p:		DW	0



; 8 строк: (DE) = (HL) << o | (BC) >> (6 - o); HL, BC — вниз по тайлам, E — вниз по полосе (цикл: только постройка)
			MACRO	BG8 shl, rr, rl, msk
			LD	A,E
			SUB	8
			LD	(.e+1),A
.l:			LD	A,(BC)
			IF	rr > 0
			REPT	rr
			RRCA
			ENDR
			ENDIF
			IF	rl > 0
			REPT	rl
			RLCA
			ENDR
			ENDIF
			AND	msk
			LD	(DE),A
			LD	A,(HL)
			IF	shl > 0
			REPT	shl
			ADD	A,A
			ENDR
			ENDIF
			EX	DE,HL
			OR	(HL)
			LD	(HL),A
			EX	DE,HL
			INC	HL
			INC	BC
			DEC	E
			LD	A,E
.e:			CP	0
			JP	NZ,.l
			RET
			ENDM
bg8_0:		BG8	0, 0, 2, 0x03
bg8_2:		BG8	2, 4, 0, 0x0F
bg8_4:		BG8	4, 2, 0, 0x3F
			INCLUDE	"gen/plfun.asm"

; ---- оружие (картинки 6 точек) в полосы плоскостей CP_H: позиция px (байт экрана px >> 3, сдвиг px & 7), 8 строк от Y вниз ----
ov_proj:	LD	HL,pcur				; 17.11: сначала столбец (без PUSH и маски для чужих столбцов)
			LD	B,3
.l:			LD	A,(HL)
			OR	A
			JP	Z,.n
			INC	HL
			LD	A,(HL)				; px
			DEC	HL
			OR	A
			JP	Z,.n
			LD	C,A
			RRCA
			RRCA
			RRCA
			AND	0x1F
			LD	D,A					; столбец
			LD	A,(rc_col)
			SUB	D
			JP	Z,.c0
			DEC	A
			JP	NZ,.n
			LD	A,C					; соседний справа: часть, ушедшая за байт
			AND	7
			CP	3
			JP	C,.n
			LD	E,0xFF				; маска — дополнение
			JP	.c1
.c0:		LD	E,0
.c1:		PUSH	HL
			PUSH	BC
			INC	HL
			LD	A,C
			AND	7
			LD	(op_s),A
			PUSH	HL
			LD	HL,msk_tab
			CALL	add_a
			LD	A,(HL)				; FF >> s
			XOR	E
			POP	HL
			LD	(op_m),A
			INC	HL
			LD	C,(HL)				; Y
			INC	HL
			LD	E,(HL)
			INC	HL
			LD	D,(HL)				; картинка
			LD	B,8
.r:			LD	A,(rc_hi)
			CP	C
			JP	C,.s
			LD	A,(rc_lo)
			DEC	A
			CP	C
			JP	NC,.s
			LD	A,(op_s)
			LD	L,A
			LD	A,(DE)
			INC	L
.rot:		DEC	L
			JP	Z,.rd
			RRCA
			JP	.rot
.rd:		LD	L,A
			LD	A,(op_m)
			AND	L
.j:			CALL	op_wb				; цвет 3: полоса пола со сборкой — в полосы, иначе на экран
.s:			INC	DE
			DEC	C
			DEC	B
			JP	NZ,.r
.x:			POP	BC
			POP	HL
.n:			LD	DE,5
			ADD	HL,DE
			DEC	B
			JP	NZ,.l
			RET

; ---- бойцы 5..0 (0 — сверху) поверх полос плоскостей столбца rc_col; потом столбец — на экран ----
; запись: видим, col0 (столбец экрана, со знаком), низ, верх, ширина в столбцах экрана, заголовок кадра (2), m<<7 | s.
; Столбец данных d при сдвиге s: в столбец экрана col0 + d — rotr(байт, s) & (FF >> s), в col0 + d + 1 — остаток.
; Перья: A &= ~M; C = C & ~M | P1; E = E & ~M | (P1 & P0) (M = P0 | P1)
ov_actors:	LD	HL,cur+8*5			; бойцы 5..0 указателем в HL, счётчик в B (17.11: без oa_p и PUSH на пропуск)
			LD	B,6
.k:			LD	A,(HL)
			OR	A
			JP	Z,.n
			INC	HL
			LD	A,(rc_col)
			SUB	(HL)				; d = столбец - col0
			INC	HL
			INC	HL
			INC	HL
			CP	(HL)				; d < ширины
			JP	C,.hit
			DEC	HL
			DEC	HL
			DEC	HL
			DEC	HL
.n:			LD	DE,-8
			ADD	HL,DE
			DEC	B
			JP	NZ,.k
			RET
.hit:		LD	(a_d),A
			DEC	HL
			LD	A,(HL)
			LD	(a_top0),A
			INC	HL
			PUSH	BC
			PUSH	HL
			INC	HL
			LD	E,(HL)
			INC	HL
			LD	D,(HL)
			INC	HL
			LD	A,(HL)
			AND	7
			LD	(a_s),A
			EX	DE,HL
			LD	(a_hdr),HL
			INC	HL
			LD	A,(HL)
			LD	(a_wv),A
			LD	A,(a_s)
			CALL	rot_patch
			LD	(a_m),A
			LD	A,(a_wv)			; свой столбец данных d (d < wv)
			LD	B,A
			LD	A,(a_d)
			CP	B
			JP	NC,.lo
			LD	C,A
			LD	A,(a_m)
			CALL	contrib
.lo:		LD	A,(a_s)				; остаток столбца d - 1
			OR	A
			JP	Z,.x
			LD	A,(a_d)
			OR	A
			JP	Z,.x
			DEC	A
			LD	C,A
			LD	A,(a_m)
			CPL
			CALL	contrib
.x:			CALL	nz_tick
			POP	HL
			POP	BC
			LD	DE,-4				; HL = запись + 4
			ADD	HL,DE
			JP	.n
; столбец данных C кадра a_hdr, маска A — в полосы плоскостей (строки rc_lo..rc_hi)
contrib:	LD	(ct_m1+1),A
			LD	(ct_m2+1),A
			LD	HL,(a_hdr)
			LD	DE,CPC_HDR
			ADD	HL,DE
			LD	A,C
			ADD	A,A
			ADD	A,A
			CALL	add_a
			LD	E,(HL)
			INC	HL
			LD	D,(HL)
			INC	HL
			LD	A,(HL)				; r0
			INC	HL
			LD	C,(HL)				; n
			INC	C
			DEC	C
			RET	Z
			LD	B,A
			LD	A,(a_top0)			; строки: верх - r0 .. верх - r0 - n + 1
			SUB	B
			LD	(a_top),A
			SUB	C
			INC	A
			LD	(a_bot),A
			LD	A,(a_top)			; i_s = min(верх, hi), i_e = max(низ, lo)
			LD	C,A
			LD	A,(rc_hi)
			CP	C
			JP	NC,cb_s1
			LD	C,A
cb_s1:		LD	A,(a_bot)
			LD	B,A
			LD	A,(rc_lo)
			CP	B
			JP	C,cb_s2
			LD	B,A
cb_s2:		LD	A,C
			CP	B
			RET	C
			SUB	B
			INC	A
			LD	B,A					; строк
			LD	A,(a_top)			; данные + 2 * (верх - i_s)
			SUB	C
			ADD	A,A
			EX	DE,HL
			CALL	add_a
			EX	DE,HL
			LD	A,(sp_hi)			; есть сборка полосы пола в этом столбце — строки i < BAND_I туда (ct_band)
			OR	A
			JP	NZ,ct_band
ct_scr:		LD	A,C
			ADD	A,32
			LD	L,A
ct_h:		LD	H,0					; страницы экрана столбца — pg_set
cb_r:			LD	A,(DE)				; P0
ct_r1:		NOP
			NOP
			NOP
			NOP
ct_m1:		AND	0xFF
			LD	C,A
			INC	DE
			LD	A,(DE)				; P1
ct_r2:		NOP
			NOP
			NOP
			NOP
ct_m2:		AND	0xFF
			INC	DE
			PUSH	DE
			LD	D,A
			OR	C
			JP	Z,cb_sk				; прозрачно
			CPL
			LD	E,A					; ~M
			AND	(HL)
			LD	(HL),A				; A000
ct_pc:		LD	H,0
			LD	A,E
			AND	(HL)
			OR	D
			LD	(HL),A				; C000
ct_pe:		LD	H,0
			LD	A,C
			AND	D					; телесное — перо 3 (P0 & P1)
			LD	C,A
			LD	A,E
			AND	(HL)
			OR	C
			LD	(HL),A				; E000
ct_pa:		LD	H,0
cb_sk:		POP	DE
			DEC	L
			DEC	B
			JP	NZ,cb_r
			RET
; клетка F8+биты в полосы C/E: бит 1 — C, бит 2 — E (B = i верха клетки)
cu_strip:	LD	L,B
			LD	H,CP_H+1
			RRCA
			RRCA
			LD	C,A
			SBC	A,A
			REPT	7
			LD	(HL),A
			DEC	L
			ENDR
			LD	(HL),A
			INC	H
			LD	A,C
			RRCA
			SBC	A,A
			REPT	7
			LD	(HL),A
			INC	L
			ENDR
			LD	(HL),A
			JP	cd_nx
; оружие (цвет 3): строка C, точки A; в полосе пола со сборкой — в полосы C/E, иначе на экран (op_w)
op_wb:		PUSH	AF
			LD	A,(sp_hi)
			OR	A
			JP	Z,.s
			LD	A,C
			CP	BAND_I
			JP	NC,.s
			LD	L,C
			LD	H,CP_H+1
			POP	AF
			PUSH	AF
			OR	(HL)
			LD	(HL),A
			INC	H
			POP	AF
			OR	(HL)
			LD	(HL),A
			RET
.s:			POP	AF
			JP	op_w
; собранная полоса пола столбца (строки sp_lo..min(sp_hi, BAND_I-1)) — на экран, C000 и E000
band_copy:	LD	A,(sp_hi)
			OR	A
			RET	Z
			CP	BAND_I
			JP	C,.h
			LD	A,BAND_I-1
.h:			LD	C,A					; верх
			LD	A,(sp_lo)
			LD	B,A
			LD	A,C
			SUB	B
			RET	C
			INC	A
			RRCA
			RRCA
			RRCA
			AND	0x1F
			LD	B,A					; клеток
			LD	A,(rc_col)
			ADD	A,0xC0
			LD	D,A
			LD	A,C
			ADD	A,32
			LD	E,A
			LD	L,C
			LD	H,CP_H+1
			PUSH	BC
			PUSH	DE
			CALL	.pl
			POP	DE
			POP	BC
			INC	H
			LD	A,D
			ADD	A,0x20
			LD	D,A
.pl:		REPT	8
			LD	A,(HL)
			LD	(DE),A
			DEC	L
			DEC	E
			ENDR
			DEC	B
			JP	NZ,.pl
			LD	L,C
			RET
a_d:		DB	0
a_bot:		DB	0
a_top:		DB	0
a_top0:		DB	0
a_s:		DB	0
a_m:		DB	0
a_wv:		DB	0
a_hdr:		DW	0




; простой: пока ждём кадр — шум (если есть) (из sound.asm — место)
snd_idle:	LD	A,(nz_ch)
			CP	3
			RET	NC
			JP	nz_bit
