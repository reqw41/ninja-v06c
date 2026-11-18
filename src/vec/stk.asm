; stk.asm: низ страницы стека 9F00..9FAF (стек уходит вглубь не больше 50 байт — замер 15.11, 30 000 кадров)

; ---- полоса пола в 2 плоскостях (владелец 17.11): строки C..C-B+1 — выше BAND_I на экран (ct_scr), ниже — в полосы
; C/E (CP_H+1 / CP_H+2, байт на строку i): C = C & ~M | P1, E = E & ~M | (P1 & P0); A000 полосы пола пуста ----
ct_band:	LD	A,C
			CP	BAND_I
			JP	C,cs_go				; всё в полосе
			SUB	BAND_I-1			; строк выше полосы
			CP	B
			JP	NC,ct_scr			; всё выше
			PUSH	BC
			LD	B,A
			CALL	ct_scr
			POP	BC
			LD	A,C
			SUB	BAND_I-1
			LD	C,A
			LD	A,B
			SUB	C
			LD	B,A					; строк в полосе
			LD	C,BAND_I-1
cs_go:		LD	L,C
			LD	H,CP_H+1
			LD	A,(ct_m1+1)			; маска FF — без сдвига: цикл без вращений и масок (−48 тактов на строку)
			INC	A
			JP	Z,cs0_r
			DEC	A
			LD	(cs_m1+1),A
			LD	(cs_m2+1),A
cs_r:		LD	A,(DE)				; P0
cs_r1:		NOP
			NOP
			NOP
			NOP
cs_m1:		AND	0xFF
			LD	C,A
			INC	DE
			LD	A,(DE)				; P1
cs_r2:		NOP
			NOP
			NOP
			NOP
cs_m2:		AND	0xFF
			INC	DE
			PUSH	DE
			LD	D,A
			OR	C
			JP	Z,.sk
			CPL
			LD	E,A
			AND	(HL)
			OR	D
			LD	(HL),A				; C
			INC	H
			LD	A,C
			AND	D
			LD	C,A
			LD	A,E
			AND	(HL)
			OR	C
			LD	(HL),A				; E
			DEC	H
.sk:		POP	DE
			DEC	L
			DEC	B
			JP	NZ,cs_r
			RET
cs0_r:		LD	A,(DE)				; P0
			LD	C,A
			INC	DE
			LD	A,(DE)				; P1
			INC	DE
			PUSH	DE
			LD	D,A
			OR	C
			JP	Z,.sk
			CPL
			LD	E,A
			AND	(HL)
			OR	D
			LD	(HL),A				; C
			INC	H
			LD	A,C
			AND	D
			LD	C,A
			LD	A,E
			AND	(HL)
			OR	C
			LD	(HL),A				; E
			DEC	H
.sk:		POP	DE
			DEC	L
			DEC	B
			JP	NZ,cs0_r
			RET
	IF	EX_D
; из plat_hudinit (место — 18.11): оружие в HUD перерисовать (A = FF), имена, отложенные на экране APPROACHING, —
; напечатать (nm_replay, field_lo.asm)
hi_rst:		LD	(wh_last),A
			JP	nm_replay
	ENDIF
msk_tab:	DB	0xFF,0x7F,0x3F,0x1F,0x0F,0x07,0x03,0x01	; field.asm (rot_patch); из sound.asm — место (19.11)
