; fgap3.asm: в шрифте на месте знаков 91..95 (игра их не печатает)
; клетка из полос 0/FF во всех плоскостях — номер F8 + id0 + 2 id1 + 4 id2 (без описателя, cd_pl: cu_fill)
cl_uni:		LD	HL,cb_s+2
			LD	A,(HL)
			CP	2
			JP	NC,cl_find
			ADD	A,A
			LD	B,A
			DEC	HL
			LD	A,(HL)
			CP	2
			JP	NC,cl_find
			ADD	A,B
			ADD	A,A
			LD	B,A
			DEC	HL
			LD	A,(HL)
			CP	2
			JP	NC,cl_find
			ADD	A,B
			OR	0xF8
			RET
