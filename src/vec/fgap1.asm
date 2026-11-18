; fgap1.asm: в шрифте на месте знаков 33..47 (игра их не печатает)
; сдвиг A (0..7) -> вращения в contrib; A = FF >> s
rot_patch:	LD	HL,rp_last
			CP	(HL)
			JP	Z,.m
			LD	(HL),A
			LD	HL,rp_codes
			ADD	A,A
			ADD	A,A
			CALL	add_a
			LD	DE,ct_r1
			CALL	.c4
			LD	DE,ct_r2
			CALL	.c4
			LD	DE,cs_r1			; и в цикл полосы пола (cs_go)
			CALL	.c4
			LD	DE,cs_r2
			CALL	.c4
			LD	A,(rp_last)
.m:			LD	HL,msk_tab
			JP	add_a_ld
.c4:		PUSH	HL
			LD	B,4
.c:			LD	A,(HL)
			LD	(DE),A
			INC	HL
			INC	DE
			DEC	B
			JP	NZ,.c
			POP	HL
			RET
add_a_ld:	CALL	add_a
			LD	A,(HL)
			RET
rp_last:	DB	0
rp_codes:	DB	0,0,0,0				; s = 0
			DB	0x0F,0,0,0			; 1: RRCA
			DB	0x0F,0x0F,0,0		; 2: RRCA x 2
			DB	0x0F,0x0F,0x0F,0	; 3: RRCA x 3
			DB	0x0F,0x0F,0x0F,0x0F	; 4: RRCA x 4
			DB	0x07,0x07,0x07,0	; 5: RLCA x 3
			DB	0x07,0x07,0,0		; 6: RLCA x 2
			DB	0x07,0,0,0			; 7: RLCA
