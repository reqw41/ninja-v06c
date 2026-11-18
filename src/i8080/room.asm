; Комнаты (перевод src/model/room.js): переход $F699, враги по комнатам $E336, постройка $EABC (поток, пол,
; дыры, идол, стены), разворот спрайтов $F925, расстановка $F97E/$FA3D, логическая часть вывода $E8AB.
; Указатели $E4C4/$E4DD/$E862/$FE25 — адреса Вектора.

; --- постройка комнаты --------------------------------------------------------------------------------
put_tile:	LD	HL,(zv_E4DD)		; $EBAB: тайл в карту, счётчик клеток -1
			LD	A,(zv_E4CB)
			LD	(HL),A
			INC	HL
			LD	(zv_E4DD),HL
			LD	HL,(zv_E4C8)
			DEC	HL
			LD	(zv_E4C8),HL
			RET
next_col:	LD	A,(zv_E4CA)		; $EB95: столбец 0..39, видны 4..35
			INC	A
			LD	(zv_E4CA),A
			CP	0x28
			JP	C,.v
			XOR	A
			LD	(zv_E4CA),A
			RET
.v:			CP	4
			RET	C
			CP	0x24
			RET	NC
			JP	put_tile
e4c8z:		LD	HL,(zv_E4C8)
			LD	A,H
			OR	L
			RET
; $F64C: поток тайлов ($FF тайл n — n+1 повторов) до конца счётчика
stream:		LD	HL,(zv_E4C4)
			LD	A,(HL)
			INC	HL
			LD	(zv_E4C4),HL
			CP	0xFF
			JP	Z,.rle
			LD	(zv_E4CB),A
			CALL	next_col
			CALL	e4c8z
			RET	Z
			JP	stream
.rle:		LD	A,(HL)
			LD	(zv_E4CB),A
			INC	HL
			LD	B,(HL)
			INC	HL
			LD	(zv_E4C4),HL
.r:			CALL	next_col
			CALL	e4c8z
			RET	Z
			LD	A,B
			SUB	1
			LD	B,A
			JP	NC,.r
			JP	stream
; $F131: стена 15 строк по 4 тайла (HL — источник шириной 40, DE — карта)
wall:		LD	(zv_E4C4),HL
			EX	DE,HL
			LD	(zv_E4DD),HL
			LD	B,15
.r:			LD	C,4
.c:			LD	HL,(zv_E4C4)
			LD	A,(HL)
			LD	(zv_E4CB),A
			INC	HL
			LD	(zv_E4C4),HL
			CALL	put_tile
			DEC	C
			JP	NZ,.c
			LD	HL,(zv_E4DD)
			LD	DE,0x1C
			ADD	HL,DE
			LD	(zv_E4DD),HL
			DEC	B				; у ZX источник шириной 40 (+$24 на строку), здесь — 4
			JP	NZ,.r
			RET
; $F107: нет выхода влево/вправо — стена
walls:		LD	A,(zv_E4BB)
			ADD	A,A
			ADD	A,A
			LD	HL,zv_D897
			CALL	add_a
			LD	A,(HL)
			OR	A
			PUSH	HL
			JP	NZ,.r
			LD	HL,wall_l
			LD	DE,0x8AF7-ZS
			CALL	wall
.r:			POP	HL
			INC	HL
			LD	A,(HL)
			OR	A
			RET	NZ
			LD	HL,wall_r
			LD	DE,0x8B13-ZS
			JP	wall
; $FDDC: дыры комнаты (X в потолке, X в полу)
holes:		LD	A,(zv_E4BB)
			ADD	A,A
			LD	HL,zv_DBB5
			CALL	add_a
			LD	A,(HL)
			LD	(zv_E4D9),A
			INC	HL
			LD	A,(HL)
			LD	(zv_E4DA),A
			LD	A,(zv_E4D9)
			OR	A
			JP	Z,.f
			LD	HL,zv_DBFF
			LD	(zv_FE25),HL
.f:			LD	A,(zv_E4DA)
			OR	A
			RET	Z
			LD	HL,zv_DBDF
			LD	(zv_FE25),HL
			RET
; $FAF3: перенос — идол в этой комнате; HL — его ячейка (иначе $E4C2)
idol_room:	LD	A,(zv_E4BB)
			INC	A
			LD	HL,zv_E4BC
			LD	B,6
.l:			CP	(HL)
			JP	Z,.y
			INC	HL
			DEC	B
			JP	NZ,.l
			OR	A
			RET
.y:			SCF
			RET
; $FAB3: идол у края по направлению ($E4DB — адрес на экране ZX, флаг «идол виден»)
idol_draw:	LD	A,(zv_E1F3)
			LD	HL,zv_FB06
			CALL	tword
			LD	(zv_E4DB),HL
			RET
; $EABC: постройка комнаты
room_build:	LD	A,(zv_E4BB)
			CP	1
			JP	NZ,.n1
			LD	A,0x30
			LD	(zv_E41E),A
	IFNDEF	VEC_CPC						; вид CPC: тайлы — свои (плотная таблица), тайл $A0 делает plat_room
			LD	HL,0xD50C-ZS
			LD	B,8
			XOR	A
.z:			LD	(HL),A
			INC	HL
			DEC	B
			JP	NZ,.z
	ENDIF
			JP	.s
.n1:		LD	A,0x28
			LD	(zv_E41E),A
	IFNDEF	VEC_CPC
			LD	HL,0xD4EC-ZS
			LD	DE,0xD50C-ZS
			LD	B,8
.cp:		LD	A,(HL)
			LD	(DE),A
			INC	HL
			INC	DE
			DEC	B
			JP	NZ,.cp
	ENDIF
.s:			LD	A,(zv_E4BB)			; поток комнаты (ZX0) -> ROOMBUF
			LD	HL,zv_D9DE
			CALL	tword
			LD	BC,ROOMBUF
			CALL	dzx0
			LD	HL,ROOMBUF
			LD	(zv_E4C4),HL
			LD	HL,0
			LD	(zv_E4DB),HL
			LD	A,0x27
			LD	(zv_E4CA),A
			LD	HL,0x01E0
			LD	(zv_E4C8),HL
			LD	HL,0x8AB7-ZS
			LD	(zv_E4DD),HL
			CALL	stream
			LD	HL,floor_s
			LD	(zv_E4C4),HL
			LD	HL,0x00C8
			LD	(zv_E4C8),HL
			LD	HL,0x8C8F-ZS
			LD	(zv_E4DD),HL
			LD	A,0x1B
			LD	(zv_E4CA),A
			CALL	stream
			CALL	holes
			CALL	idol_room
			CALL	C,idol_draw
			LD	A,(zv_E4BB)
			CP	10
			CALL	Z,idol_draw
	IFNDEF	VEC_CPC				; вид ×1.5: стены — в полях 0..3 / 36..39 (field.asm), карта ZX без стен
			CALL	walls
	ENDIF
			JP	plat_room

; --- $F925: развернуть 50 кадров (+$E864): каждая строка задом наперёд с обращением битов. ZX делает это
; через карту тайлов $8AB7 как буфер; здесь — обменом концов строки на месте (карту затем перестраивает
; постройка комнаты, итог тот же)
flip_frames:
	IFDEF	VEC_CPC
			RET							; Вектор: кадры CPC разворачиваются при выводе ($F924 — направление)
	ENDIF
			LD	A,0x31
.f:			PUSH	AF
			LD	HL,zv_DA0C
			CALL	tword
			EX	DE,HL
			LD	HL,(zv_E864)
			ADD	HL,DE
			LD	A,(HL)				; строк
			LD	(t_v),A
			INC	HL
			LD	A,(HL)				; ширина
			LD	(t_x),A
			INC	HL
.row:		PUSH	HL					; DE = конец строки
			LD	A,(t_x)
			DEC	A
			ADD	A,L
			LD	E,A
			LD	A,H
			ADC	A,0
			LD	D,A
			LD	B,high rev_tab
.sw:		LD	A,L					; HL < DE — обмен
			SUB	E
			LD	A,H
			SBC	A,D
			JP	NC,.mid
			LD	C,(HL)
			LD	A,(BC)
			PUSH	AF
			LD	A,(DE)
			LD	C,A
			LD	A,(BC)
			LD	(HL),A
			POP	AF
			LD	(DE),A
			INC	HL
			DEC	DE
			JP	.sw
.mid:		LD	A,L					; HL = DE — средний байт: обратить на месте (иначе HL = DE + 1)
			CP	E
			JP	NZ,.nx
			LD	C,(HL)
			LD	A,(BC)
			LD	(HL),A
.nx:		POP	HL
			LD	A,(t_x)
			CALL	add_a
			LD	A,(t_v)
			DEC	A
			LD	(t_v),A
			JP	NZ,.row
			POP	AF
			DEC	A
			JP	P,.f
			RET

; --- $E336: враги во всех комнатах ------------------------------------------------------------------------
place_enemies: LD	HL,zv_DA85
			LD	B,0x69
			XOR	A
.z:			LD	(HL),A
			INC	HL
			DEC	B
			JP	NZ,.z
			LD	HL,zv_DA70
			LD	DE,zv_DA85
			LD	C,21
.r:			LD	B,(HL)
			INC	HL
			PUSH	HL
			PUSH	DE
			LD	A,B
			OR	A
			JP	Z,.e
.k:			LD	A,B
			CP	1
			JP	Z,.put
			CALL	random
			CP	0xBF
			JP	NC,.sk
.put:		CALL	random
			AND	0x18
			RRCA
			RRCA
			RRCA
			OR	A
			JP	Z,.put
			ADD	A,0xF0
			LD	(DE),A
			INC	DE
.sk:		DEC	B
			JP	NZ,.k
.e:			POP	HL
			LD	DE,5
			ADD	HL,DE
			EX	DE,HL
			POP	HL
			DEC	C
			JP	NZ,.r
			RET

; --- $FA3D: оружие DE (флаг HL) — в случайное место -----------------------------------------------------
proj_place:	LD	(HL),0
.l:			LD	A,(zv_E4BB)
			CP	4
			JP	Z,.rnd
			LD	HL,(zv_E862)		; $FA8F: у ZX смотрит только первый слот
			LD	A,(HL)
			AND	0xF0
			LD	C,0
			JP	Z,.c
			INC	C
.c:			LD	HL,zv_E888
			LD	B,3
.f:			LD	A,(HL)
			CP	7
			JP	C,.f1
			LD	(HL),0xFF
.f1:		INC	HL
			DEC	B
			JP	NZ,.f
			LD	HL,7
			ADD	HL,DE
			LD	(HL),C
			LD	A,C
			OR	A
			JP	NZ,.rnd
			LD	A,0xFF
			LD	(zv_E88B),A		; ZX: (HL) после цикла = $E88B
			LD	(HL),0
			LD	HL,10
			ADD	HL,DE
			LD	(HL),0
			RET
.rnd:		CALL	random
			AND	0x1F
			CP	3
			JP	C,.l
			CP	0x1B
			JP	NC,.l
			EX	DE,HL
			LD	(HL),A			; +0
			INC	HL
			LD	(HL),0x1E		; +1
			INC	HL
			LD	(HL),A			; +2
			INC	HL
			LD	(HL),0x1E		; +3
			INC	HL
			CALL	random
			AND	1
			LD	(HL),A			; +4
			INC	HL
			LD	(HL),0			; +5
			INC	HL
			INC	HL
			LD	(HL),1			; +7
			INC	HL
			INC	HL
			INC	HL
			LD	(HL),0x1E		; +A
			EX	DE,HL
			RET

; --- $F97E: бойцы новой комнаты ------------------------------------------------------------------------
place_actors: LD	A,0xFF
			LD	(zv_E8A1),A
			LD	A,0x22
			LD	(zv_E462),A
			LD	A,8
			LD	(zv_E46A),A
			LD	A,(zv_E1F3)
			LD	HL,zv_F97C
			CALL	add_a
			LD	A,(HL)
			LD	(zv_E461),A
			LD	DE,zv_E88E
			LD	B,1
.l:			LD	A,B
			CALL	rec_a
			LD	(t_rec),HL
			LD	A,8
			CALL	fld
			LD	A,(HL)
			CP	3
			JP	Z,.n
			LD	A,0x0D
			CALL	fld
			LD	A,(HL)
			LD	(DE),A
			INC	DE
			CP	0xFF
			JP	NZ,.t
			LD	HL,zv_FA6E		; $F96F + $FF (байт кода ZX)
			JP	.g
.t:			LD	HL,zv_F96F
			CALL	add_a
.g:			LD	C,(HL)
			LD	A,9
			CALL	fld
			LD	(HL),C
			LD	A,0x0C
			CALL	fld
			LD	A,(HL)
			OR	A
			JP	NZ,.x
			LD	A,9
			CALL	fld
			LD	(HL),7
			LD	A,8
			CALL	fld
			LD	(HL),0xFF
.x:			LD	HL,zv_F972
			LD	A,(zv_E1F3)
			OR	A
			JP	Z,.x1
			LD	HL,zv_F977
.x1:		LD	A,(zv_E8A1)
			INC	A
			LD	(zv_E8A1),A
			CALL	add_a
			LD	C,(HL)
			LD	HL,(t_rec)
			LD	(HL),C
			INC	HL
			LD	(HL),0x22
			LD	A,0x0C
			CALL	fld
			LD	A,(HL)
			OR	A
			JP	Z,.n
			LD	A,8
			CALL	fld
			LD	(HL),0
.n:			INC	B
			LD	A,B
			CP	6
			JP	NZ,.l
			LD	B,1
.m:			LD	A,B
			CALL	rec_a
			LD	(t_rec),HL
			LD	A,8
			CALL	fld
			LD	A,(HL)
			CP	3
			JP	Z,.mn
			LD	A,0x0C
			CALL	fld
			LD	A,(HL)
			OR	A
			JP	NZ,.m1
			LD	A,8
			CALL	fld
			LD	(HL),0xFF
			JP	.mn
.m1:		LD	A,0x0E
			CALL	fld
			LD	A,(HL)
			CP	0xFF
			JP	NZ,.mn
			LD	A,8
			CALL	fld
			LD	(HL),2
.mn:		INC	B
			LD	A,B
			CP	6
			JP	NZ,.m
			RET

; --- $F699: в соседнюю комнату по направлению A (0 влево, 1 вправо, 2 вверх, 3 вниз); A = 0 — выхода нет --
next_room:	LD	(t_dir),A
			LD	C,A
			LD	A,(zv_E4BB)
			ADD	A,A
			ADD	A,A
			ADD	A,C
			LD	HL,zv_D897
			CALL	add_a
			LD	A,(HL)
			OR	A
			RET	Z
			DEC	A
			LD	(zv_E4BB),A
			LD	HL,zv_D8EB
			CALL	add_a
			LD	A,(HL)
			LD	(zv_DB8E),A
			CALL	plat_approach		; очистка экрана, APPROACHING <имя>
			LD	A,SND_ROOM
			CALL	plat_sound
			LD	A,(t_dir)
			CP	2
			CALL	NC,place_enemies
			LD	A,(t_dir)
			LD	(zv_E85C),A
			CP	2
			JP	NC,.e70a
			LD	HL,zv_E1F3
			CP	(HL)
			JP	Z,.dir
			LD	A,(zv_F924)
			XOR	1
			LD	(zv_F924),A
			LD	HL,0x2140
			LD	(zv_E864),HL
			CALL	flip_frames
			LD	HL,0
			LD	(zv_E864),HL
			CALL	flip_frames
			LD	A,(zv_E1F3)
			OR	A
			LD	HL,zv_FA8B
			LD	DE,zv_FA87
			JP	Z,.c
			EX	DE,HL
.c:			PUSH	DE
			LD	DE,zv_DCE3
			CALL	cp4
			POP	HL
			LD	DE,zv_DCDE
			CALL	cp4
.dir:		LD	A,(t_dir)
			LD	(zv_E1F3),A
.e70a:		LD	HL,(zv_E862)		; энергия врагов старой комнаты — в её таблицу
			LD	B,1
.e:			PUSH	HL
			LD	A,B
			CALL	rec_a
			LD	(t_rec),HL
			LD	A,8
			CALL	fld
			LD	A,(HL)
			CP	3
			JP	Z,.en
			LD	A,3
			CALL	fld
			LD	(HL),3
			LD	A,0x0C
			CALL	fld
			LD	A,(HL)
			LD	(HL),0
			ADD	A,A
			ADD	A,A
			ADD	A,A
			ADD	A,A
			LD	C,A
			POP	HL
			PUSH	HL
			LD	A,(HL)
			AND	3
			ADD	A,C
			LD	(HL),A
.en:		POP	HL
			INC	HL
			INC	B
			LD	A,B
			CP	6
			JP	NZ,.e
			LD	B,1
.s3:		LD	A,B
			CALL	rec_a
			LD	DE,8
			ADD	HL,DE
			LD	(HL),3
			INC	B
			LD	A,B
			CP	6
			JP	NZ,.s3
			LD	HL,zv_E88E
			LD	B,5
			XOR	A
.z5:		LD	(HL),A
			INC	HL
			DEC	B
			JP	NZ,.z5
			LD	(zv_E8A4),A
			LD	A,(zv_E1F3)
			LD	HL,zv_FA85
			CALL	add_a
			LD	A,(HL)
			LD	(zv_E46F),A
			LD	B,A
			LD	C,3
			CALL	print_name
			LD	A,(zv_E4BB)
			CP	4
			JP	Z,.f800
			LD	L,A
			LD	H,0
			LD	D,H
			LD	E,L
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,DE
			LD	DE,zv_DA85
			ADD	HL,DE
			LD	(zv_E862),HL
			LD	B,1
.t:			PUSH	HL
			LD	A,B
			CALL	rec_a
			LD	(t_rec),HL
			POP	HL
			LD	A,(HL)
			PUSH	HL
			OR	A
			JP	NZ,.t1
			LD	A,8
			CALL	fld
			LD	(HL),3
			JP	.t2
.t1:		LD	C,A
			AND	3
			DEC	A
			LD	D,A
			LD	A,0x0D
			CALL	fld
			LD	(HL),D
			LD	A,8
			CALL	fld
			LD	(HL),2
			LD	A,C
			RRCA
			RRCA
			RRCA
			RRCA
			AND	0x0F
			LD	D,A
			LD	A,0x0C
			CALL	fld
			LD	(HL),D
			LD	A,D
			OR	A
			JP	NZ,.t2
			LD	A,0x0D
			CALL	fld
			LD	(HL),0xFF
			LD	A,8
			CALL	fld
			LD	(HL),0xFF
.t2:		POP	HL
			INC	HL
			INC	B
			LD	A,B
			CP	6
			JP	NZ,.t
			LD	A,(zv_E46F)
			LD	C,A
			LD	E,0
			LD	B,1
.u:			LD	A,B
			CALL	rec_a
			LD	(t_rec),HL
			LD	A,8
			CALL	fld
			LD	A,(HL)
			CP	3
			JP	Z,.un
			LD	A,0x0C
			CALL	fld
			LD	A,(HL)
			OR	A
			JP	Z,.uff
			LD	A,E
			CP	C
			JP	NZ,.u1
			INC	A
.u1:		CP	3
			JP	NC,.uff
			LD	E,A
			LD	D,A
			LD	A,0x0E
			CALL	fld
			LD	(HL),D
			LD	A,8
			CALL	fld
			LD	(HL),0
			PUSH	BC
			PUSH	DE
			LD	A,0x0E
			CALL	fld
			LD	B,(HL)
			LD	A,0x0D
			CALL	fld
			LD	C,(HL)
			CALL	print_name
			POP	DE
			POP	BC
			INC	E
			JP	.un
.uff:		LD	A,0x0E
			CALL	fld
			LD	(HL),0xFF
.un:		INC	B
			LD	A,B
			CP	6
			JP	NZ,.u
.f800:		LD	A,0x2A
			LD	(zv_E3A3),A
			LD	A,(zv_E4BB)
			LD	HL,zv_F694
			LD	B,5
.g:			CP	(HL)
			JP	Z,.g2
			INC	HL
			DEC	B
			JP	NZ,.g
			JP	.g3
.g2:		LD	A,0x2C
			LD	(zv_E3A3),A
.g3:		CALL	room_build
			LD	C,0				; оружие: лежит/улетело — новое место
.p:			LD	A,C
			CALL	proj_j
			LD	(t_pj),HL
			LD	A,C
			LD	HL,zv_E888
			CALL	add_a
			LD	(t_flag),HL
			LD	A,(HL)
			LD	(t_v),A
			CP	7
			JP	C,.p1
			LD	(HL),0
			LD	HL,(t_pj)
			LD	DE,6
			ADD	HL,DE
			LD	(HL),0
.p1:		LD	HL,(t_pj)
			LD	DE,7
			ADD	HL,DE
			LD	(HL),0
			LD	A,(t_v)
			INC	A
			CALL	Z,.pp
			LD	A,(t_v)
			OR	A
			CALL	Z,.pp
			INC	C
			LD	A,C
			CP	3
			JP	NZ,.p
			CALL	plat_hudinit		; $F5CB: цвета строк HUD, SCORE / IDOLS
			CALL	score_hud
			LD	B,5				; вводы врагов
.i:			LD	HL,zv_E88D
			CALL	add_b
			LD	A,(HL)
			LD	C,A
			AND	0xF0
			LD	A,0x2C
			JP	Z,.is
			LD	A,C
			AND	3
			CP	3
			JP	Z,.in
			CP	2
			LD	A,0x21
			JP	Z,.is
			LD	A,C
			AND	3
			CP	1
			LD	A,0x15
			JP	Z,.is
			LD	A,0x1C
.is:		PUSH	AF
			LD	HL,zv_E1ED
			CALL	add_b
			POP	AF
			LD	(HL),A
.in:		DEC	B
			JP	NZ,.i
			LD	HL,zv_E4CD
			LD	B,6
			XOR	A
.ph:		LD	(HL),A
			INC	HL
			DEC	B
			JP	NZ,.ph
			CALL	animate_all
			CALL	place_actors
			XOR	A
			LD	(zv_E893),A
			LD	A,(zv_E4DA)
			OR	A
			JP	Z,.nh
			SUB	5
			LD	(zv_E89F),A
			ADD	A,10
			LD	(zv_E8A0),A
			JP	.rt
.nh:		LD	(zv_E8A0),A
			DEC	A
			LD	(zv_E89F),A
.rt:		LD	A,5
			RET
.pp:		PUSH	BC
			LD	HL,(t_pj)
			EX	DE,HL
			LD	HL,(t_flag)
			CALL	proj_place
			POP	BC
			RET

; $EAA7: строка HUD — число идолов
score_hud:	LD	A,(zv_E4CC)
			ADD	A,0x30
			LD	(zv_DB7F),A
			JP	plat_hud

; --- $E8AB (логическая часть): стереть/нарисовать оружие ($F21B/$F1B4 — только флаги +A), полёт и
; попадания ($F277); вывод — платформа. A на выходе — состояние бойца 5 (его читает $EF24)
draw:		XOR	A				; флаги вывода оружия: стёрто / нарисовано в этом проходе
			LD	HL,pj_er
			LD	B,6
.zf:		LD	(HL),A
			INC	HL
			DEC	B
			JP	NZ,.zf
			LD	C,0
.e:			LD	A,C
			CALL	proj_j
			LD	(t_pj),HL
			LD	DE,10
			ADD	HL,DE
			LD	A,(HL)
			OR	A
			JP	Z,.en
			LD	HL,(t_pj)
			INC	HL
			LD	A,(HL)
			CP	0x20
			JP	NC,.e1
			LD	A,C
			LD	HL,zv_E888
			CALL	add_a
			LD	A,(HL)
			OR	A
			JP	Z,.en
.e1:		LD	A,C				; стёрто в этом проходе (для вывода Вектора)
			LD	HL,pj_er
			CALL	add_a
			LD	(HL),1
			LD	HL,(t_pj)
			LD	A,(HL)
			OR	A
			JP	Z,.e0
			CP	0x20
			JP	C,.en
.e0:		LD	HL,(t_pj)
			LD	DE,10
			ADD	HL,DE
			LD	(HL),0
.en:		INC	C
			LD	A,C
			CP	3
			JP	NZ,.e
			CALL	projectiles
			LD	C,0
.d:			LD	A,C
			CALL	proj_j
			LD	(t_pj),HL
			LD	DE,10
			ADD	HL,DE
			LD	A,(HL)
			OR	A
			JP	Z,.dn
			LD	HL,(t_pj)
			INC	HL
			LD	A,(HL)
			CP	0x1E
			JP	Z,.d1
			LD	DE,6
			ADD	HL,DE
			LD	A,(HL)
			OR	A
			JP	Z,.dn
.d1:		LD	HL,(t_pj)
			LD	A,(HL)
			CP	0x20
			JP	NC,.d2
			LD	A,C
			LD	HL,pj_dr
			CALL	add_a
			LD	(HL),1
			LD	A,1
.d2:		LD	HL,(t_pj)
			LD	DE,10
			ADD	HL,DE
			LD	(HL),A
.dn:		INC	C
			LD	A,C
			CP	3
			JP	NZ,.d
			CALL	plat_draw
			LD	A,(zv_E4B4)
			RET

; обращение битов байта (для $F925)
			ALIGN	256
rev_tab:
.x = 0
			DUP	256
			DB	((.x&1)<<7)|((.x&2)<<5)|((.x&4)<<3)|((.x&8)<<1)|((.x&16)>>1)|((.x&32)>>3)|((.x&64)>>5)|((.x&128)>>7)
.x = .x + 1
			EDUP
