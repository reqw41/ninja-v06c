; sound.asm: озвучка Ninja «ровно как в Atari» (решение владельца 14.11.2026, docs/MUSIC.md). Перевод модели
; tools/atari/sound.py (вся звуковая система Atari: эффекты $2418, подыгрывание $24EA, свист, тикание $2BE8,
; песня $BBE6 -> проигрыватель $BC10 = tools/atari/music.py) на 8080. Регистры POKEY — виртуальные (pk),
; 6 вызовов на 5 кадров (60 Гц оригинала при 50 Гц Вектора). Каналы 1..3 -> счётчики ВИ53 0..2 (режим 3,
; делитель (AUDF+1)*47 от 1,5 МГц); голос звучит, пока громкость > 0; шум (искажения 0..8, кроме тонов A/C/E) —
; случайные биты на выход счётчика шумящего канала с частотой канала POKEY (как Bruce Lee: в прерывании и в
; простое, snd_idle); 4-й канал (свист, тикание) звучит на счётчике 2 поверх 3-го канала.
; Переменные Atari: $2405..$2417 = SV+адрес, $24E4..$24E9 = SW+адрес, песня $BD57.. = MB+адрес (gen/music.asm),
; нулевая страница $84..$8F = ZP+адрес.

ZP			EQU	zp_84 - 0x84
pk:			DS	9					; AUDF1 AUDC1 AUDF2 AUDC2 AUDF3 AUDC3 AUDF4 AUDC4 AUDCTL
zp_84:		DS	12					; порядок ($84), длительность ($87), позиция ($8A), нота ($8D) по каналам
snd_cc:		DB	0xFF				; $CC: 0 — песня, $FF — подыгрывание (враг в комнате)
snd_rt:		DB	0					; $14 (RTCLOK)
snd_9f5a:	DB	0					; тикание: осталось
snd_acc:	DB	0					; 6 вызовов на 5 кадров
snd_rnd:	DW	0xACE1				; RANDOM POKEY (своя последовательность, ГСЧ игры не трогает)
snd_on:		DB	1					; УС — звук вкл/выкл
snd_pause:	DB	1					; 1 — заставка/меню: драйвер стоит, тишина
; владелец 15.11: «все звуки как в атари 1 в 1» — свист (вход и случайный), шум у всех шумовых искажений,
; «тук» идола, тикание $2BE8 — ровно по коду Atari (tools/atari/sfx_iso.py)
nz_ch:		DB	0xFF				; счётчик шумящего канала (FF — шума нет)
	IFNDEF	P4_MODE
P4_MODE		EQU	3					; полином канала 4: 0 — тон основной частоты, 1 — биты, 2 — полбита (владелец 15.11: 4c и 4d норм), 3 — по громкости
	ENDIF
	IFNDEF	NZ_OVH
NZ_OVH		EQU	26					; служебная часть бита шума (витки)
	ENDIF
	IFNDEF	NZ_OVH4
NZ_OVH4		EQU	40
	ENDIF
	IFNDEF	NZW_SPAN
NZW_SPAN	EQU	2400					; свист: обработчик прерывания должен укладываться в кадр (59904; при 3000 — 75 тыс.: прерывания подряд и вложенные — «мусор в HUD»)
	ENDIF
	IFNDEF	AMBIENT
AMBIENT		EQU	0
	ENDIF
	IFNDEF	NZT_SPAN
NZT_SPAN	EQU	2200
	ENDIF
	IFNDEF	NZ_SPAN
NZ_SPAN		EQU	1800					; вспышка шума в прерывании (витки ≈ 24 такта); обработчик ≤ 55 тыс. из 59904 — замер tmp isr (владелец 15.11: «оборванный»)
	ENDIF
nz_dly:		DB	1					; задержка между битами шума, младший байт (витки по 16 тактов)
nz_dlh:		DB	0					; старший байт (полином 4 на низких частотах)
amb_k:		DB	0					; нота подыгрывания на счётчиках 0, 1 (AUDF; 0 — нет)
nz_thin:	DB	128					; вероятность единицы шума (/256)
mus_tt:		DB	0					; 1 — заставка: удары баса шумом
nz_isr:		DB	0					; 1 — nz_bit из прерывания (без EI)
nz_p4:		DB	0					; 1 — биты шума из 4-битного полинома (канал 4 Atari, искажение C)
p4s:		DB	0x0F					; задержка между битами шума (частота канала POKEY)
nz_rnd:		DW	0x7A31
nz_thr:		DB	0					; ширина единицы шума: 0 — весь бит; иначе nz_thr витков (тише)
mx:			DB	0
my:			DB	0
mpat:		DB	0
mptr:		DW	0

; ---- HL = база + текущий канал mx (портит A) ----
xv:			LD	A,(mx)
			JP	add_a
; ---- A = случайный байт (Галуа 16) ----
snd_random:	PUSH	HL
			LD	HL,(snd_rnd)
			LD	A,H
			RRA
			LD	H,A
			LD	A,L
			RRA
			LD	L,A
			JP	NC,.n
			LD	A,H
			XOR	0xB4
			LD	H,A
.n:			LD	(snd_rnd),HL
			LD	A,L
			XOR	H
			POP	HL
			RET

; ---- кадр (из прерывания): 6 вызовов на 5 кадров, потом регистры -> ВИ53 ----
snd_frame:	LD	A,(snd_pause)
			OR	A
			JP	Z,.go
			LD	A,0xFF
			LD	(nz_ch),A
			JP	snd_silent
.go:		LD	A,(snd_acc)			; идол не мигает (владелец 16.11)
			ADD	A,6
.l:			CP	5
			JP	C,.e
			SUB	5
			PUSH	AF
			CALL	snd_vbi
			POP	AF
			JP	.l
.e:			LD	(snd_acc),A
			CALL	snd_out
			LD	A,(nz_ch)			; вспышка шума в прерывании (≈ 5000 тактов)
			CP	3
			RET	NC
			LD	HL,(nz_dly)			; битов = NZ_SPAN / (задержка + 26) (виток ≈ 24 такта, бит ≈ 26 витков сверху —
			LD	DE,NZ_OVH			; замер 15.11: при задержке 1 вспышка была 90 тыс. тактов, длиннее кадра)
			LD	A,(nz_p4)			; бит полинома дороже
			OR	A
			JP	Z,.ov
			LD	DE,NZ_OVH4
.ov:
			ADD	HL,DE
			EX	DE,HL
			CALL	nz_span
			LD	B,0
.dv:		INC	B
			LD	A,L
			SUB	E
			LD	L,A
			LD	A,H
			SBC	A,D
			LD	H,A
			JP	NC,.dv
			DEC	B					; битов — вниз (не больше вспышки), но хотя бы 1
			JP	NZ,.b1
			INC	B
.b1:		LD	A,1
			LD	(nz_isr),A
.nb:		CALL	nz_bit
			DEC	B
			JP	NZ,.nb
			XOR	A
			LD	(nz_isr),A
			RET

; ---- $1576: эффекты, подыгрывание, тикание; песня — если $CC >= 0 ----
snd_vbi:	LD	HL,snd_rt
			INC	(HL)
			LD	A,(SV+0x2416)		; $2418: «тук» на канале 1
			OR	A
			JP	Z,.cc
			DEC	A
			LD	(SV+0x2416),A
			OR	0xA0
			LD	(pk+1),A
			LD	A,8
			LD	(pk+0),A
.cc:		LD	A,(snd_cc)
			OR	A
			JP	P,.amb
			; владелец 15.11 («сократим число звуков»): случайного свиста в бою и подыгрывания нет ($24E8 не убывает)
.wh:		LD	A,(SV+0x2417)		; свист: канал 3 (шум, частота падает) + 4 (тон)
			OR	A
			JP	Z,.fx
			DEC	A
			LD	(SV+0x2417),A
			LD	(pk+4),A			; AUDF3 = n, AUDC3 = n >> 3 (шум), AUDC4 = $C0 | n >> 3, AUDF4 = $A0
			RRCA
			RRCA
			RRCA
			AND	0x1F
			LD	(pk+5),A
			OR	0xC0
			LD	(pk+7),A
			LD	A,0xA0
			LD	(pk+6),A
.fx:		LD	A,2					; эффекты боя: громкость += шаг, на 5 шаг -1; AUDF = громкость + база
			LD	(mx),A
.fl:		LD	HL,SV+0x240D
			CALL	xv
			LD	A,(HL)
			OR	A
			JP	Z,.fn
			LD	C,A
			PUSH	HL
			LD	HL,SV+0x2410
			CALL	xv
			LD	A,C
			ADD	A,(HL)
			POP	HL
			LD	(HL),A
			LD	C,A
			LD	A,(mx)
			ADD	A,A
			LD	HL,pk+1
			CALL	add_a
			LD	(HL),C
			DEC	HL
			LD	A,C
			CP	5
			JP	NZ,.f5
			PUSH	HL
			LD	HL,SV+0x2410
			CALL	xv
			LD	(HL),0xFF
			POP	HL
.f5:		PUSH	HL
			LD	HL,SV+0x2413
			CALL	xv
			LD	A,C
			ADD	A,(HL)
			POP	HL
			LD	(HL),A
.fn:		LD	A,(mx)
			DEC	A
			LD	(mx),A
			JP	P,.fl
.amb:
	IF	AMBIENT				; подыгрывание Atari $24EA (владелец 15.11: убрано; 18.11 место — под оружие в HUD)
			LD	HL,SW+0x24E7		; $24EA: подыгрывание (через вызов)
			DEC	(HL)
			JP	P,.tick
			LD	(HL),1
			LD	A,(SW+0x24E6)
			OR	A
			JP	NZ,.up
			LD	A,(SW+0x24E5)		; нота кончилась: громкость вниз
			OR	A
			JP	Z,.nn
			DEC	A
			LD	(SW+0x24E5),A
			OR	0xA0
			LD	(pk+5),A
			JP	.nn
.up:		LD	A,(SW+0x24E5)		; нота звучит: громкость вверх до 2
			CP	2
			JP	Z,.nn
			INC	A
			LD	(SW+0x24E5),A
			OR	0xA0
			LD	(pk+5),A
.nn:		LD	A,(SW+0x24E8)		; пока свист не идёт: новая нота после паузы
			OR	A
			JP	P,.tick
			LD	HL,SW+0x24E4
			DEC	(HL)
			JP	P,.tick
			CALL	snd_random
			AND	3
			LD	A,4
			JP	NZ,.pz
			CALL	snd_random
			AND	0x18
.pz:		LD	(SW+0x24E4),A
			CALL	snd_random			; шаг по пентатонике: -1, 0, +1, +2
			AND	3
			DEC	A
			LD	HL,SW+0x24E9
			ADD	A,(HL)
			AND	7
			LD	(HL),A
			LD	HL,SV+0x2405
			CALL	add_a
			LD	A,(HL)
			LD	(SW+0x24E6),A
			OR	A
			JP	Z,.tick
			LD	(pk+4),A
			LD	A,1
			LD	(SW+0x24E5),A
			LD	A,0xA1
			LD	(pk+5),A
	ENDIF
.tick:		LD	HL,snd_9f5a			; $2BE8: тикание счёта — AUDF4 = $60 - n (с заёмом), AUDC4 = $C4 (полином 4)
			LD	A,(HL)
			OR	A
			JP	Z,.mus
			DEC	(HL)
			LD	B,(HL)
			LD	A,B
			OR	A
			JP	Z,.t0
			LD	A,0x5F
			SUB	B
			LD	(pk+6),A
			LD	A,0xC4
.t0:		LD	(pk+7),A
.mus:		LD	A,(snd_cc)			; $BBE6: песня, только если $CC >= 0
			OR	A
			RET	M
			LD	A,(MB+0xBDBC)
			OR	A
			JP	P,.play
			AND	0x40				; $C0: заглушить и стоп
			RET	Z
			LD	HL,pk
			LD	B,9
			XOR	A
.z9:		LD	(HL),A
			INC	HL
			DEC	B
			JP	NZ,.z9
			LD	A,0x80
			LD	(MB+0xBDBC),A
			RET
.play:		AND	0x40				; $40: песня с начала
			JP	Z,mus_frame
			LD	HL,zp_84
			LD	B,12
			XOR	A
.z12:		LD	(HL),A
			INC	HL
			DEC	B
			JP	NZ,.z12
			LD	(MB+0xBDBC),A
			; дальше — mus_frame

; ---- $BC10: проигрыватель песни, один кадр (music.py Driver.frame) ----
mus_frame:	LD	HL,MB+0xBD9A
			INC	(HL)
			LD	A,2
			LD	(mx),A
.ch:		LD	HL,ZP+0x87			; длительность кончилась — следующая нота
			CALL	xv
			LD	A,(HL)
			OR	A
			JP	NZ,.env
.ord:		LD	HL,MB+0xBDFC
			CALL	xv
			LD	E,(HL)
			LD	HL,MB+0xBDFF
			CALL	xv
			LD	D,(HL)
			LD	HL,ZP+0x84
			CALL	xv
			LD	A,(HL)
			EX	DE,HL
			CALL	add_a
			LD	A,(HL)				; номер паттерна
			CP	0xFF
			JP	NZ,.pat
			LD	HL,ZP+0x87
			CALL	xv
			LD	(HL),0
			LD	HL,ZP+0x84
			CALL	xv
			LD	(HL),0
			LD	HL,ZP+0x8A
			CALL	xv
			LD	(HL),0
			JP	.ord
.pat:		LD	(mpat),A
			LD	HL,MB+0xBE02
			CALL	add_a
			LD	E,(HL)
			LD	A,(mpat)
			LD	HL,MB+0xBE0D
			CALL	add_a
			LD	D,(HL)
			EX	DE,HL
			LD	(mptr),HL
			LD	HL,ZP+0x8A
			CALL	xv
			LD	A,(HL)
			LD	(my),A
.cmd:		CALL	pbyte				; команды (байт >= $80)
			LD	C,A
			AND	0x80
			JP	Z,.note
			LD	A,C
			AND	0x0F
			JP	NZ,.c1
			CALL	pnext				; 0: инструмент
			LD	HL,MB+0xBDA6
			JP	.cst
.c1:		CP	1
			JP	NZ,.c2
			CALL	pnext				; 1: мерцание вкл (величина)
			LD	HL,MB+0xBDB2
			CALL	.cst0
			LD	HL,MB+0xBDAF
			LD	C,1
			JP	.cset
.c2:		CP	2
			JP	NZ,.c3
			LD	HL,MB+0xBDAF		; 2: мерцание выкл
			LD	C,0
			JP	.cset
.c3:		CP	3
			JP	NZ,.c4
			CALL	pnext				; 3: транспозиция
			LD	HL,MB+0xBDA0
			JP	.cst
.c4:		CP	4
			JP	NZ,.c5
			LD	HL,MB+0xBDAC		; 4: шум
			LD	C,0x80
			JP	.cset
.c5:		CP	5
			JP	NZ,.c6
			LD	HL,MB+0xBDAC		; 5: тон
			LD	C,0xA0
			JP	.cset
.c6:		CP	6
			JP	NZ,.c7
			LD	HL,MB+0xBDB9		; 6: арпеджио вкл
			LD	C,1
			JP	.cset
.c7:		CP	7
			JP	NZ,.cnx
			LD	HL,MB+0xBDB9		; 7: арпеджио выкл
			LD	C,0
.cset:		CALL	xv
			LD	(HL),C
.cnx:		LD	HL,my
			INC	(HL)
			JP	.cmd
.cst:		CALL	.cst0
			JP	.cnx
.cst0:		LD	C,A					; A — байт параметра -> (HL + канал)
			CALL	xv
			LD	(HL),C
			RET
.note:		LD	A,C					; нота: длительность $BD67[b & $1F], номер — следующий байт
			LD	HL,MB+0xBD9D
			CALL	.cst0
			LD	A,C
			AND	0x1F
			LD	HL,MB+0xBD67
			CALL	add_a
			LD	C,(HL)
			LD	HL,ZP+0x87
			CALL	xv
			LD	(HL),C
			LD	HL,my
			INC	(HL)
			LD	A,(HL)
			LD	C,A
			LD	HL,ZP+0x8A
			CALL	xv
			LD	(HL),C
			CALL	pbyte
			LD	C,A
			LD	HL,MB+0xBDA0
			CALL	xv
			LD	A,(HL)
			ADD	A,C
			LD	C,A
			LD	HL,ZP+0x8D
			CALL	xv
			LD	(HL),C
			LD	A,C
			LD	HL,MB+0xBD6C
			CALL	add_a
			LD	C,(HL)
			LD	HL,MB+0xBDA3
			CALL	xv
			LD	(HL),C
			CALL	set_audf
			LD	HL,MB+0xBDA9
			CALL	xv
			LD	(HL),0
			LD	HL,ZP+0x8A			; позиция +1; конец паттерна — следующий в порядке
			CALL	xv
			INC	(HL)
			LD	A,(HL)
			LD	(my),A
			CALL	pbyte
			CP	0xFF
			JP	NZ,.env
			LD	HL,ZP+0x8A
			CALL	xv
			LD	(HL),0
			LD	HL,ZP+0x84
			CALL	xv
			INC	(HL)
.env:		LD	HL,MB+0xBDA6		; огибающая громкости инструмента
			CALL	xv
			LD	A,(HL)
			LD	E,A
			LD	HL,MB+0xBDCC
			CALL	add_a
			LD	D,(HL)
			LD	A,E
			LD	HL,MB+0xBDC6
			CALL	add_a
			LD	E,(HL)
			LD	HL,MB+0xBDA9
			CALL	xv
			LD	A,(HL)
			EX	DE,HL
			CALL	add_a
			LD	A,(HL)
			CP	0xFF
			JP	Z,.flk
			LD	C,A
			EX	DE,HL
			INC	(HL)
			LD	HL,MB+0xBDAC
			CALL	xv
			LD	A,C
			OR	(HL)
			LD	C,A
			LD	A,(mx)
			ADD	A,A
			LD	HL,pk+1
			CALL	add_a
			LD	(HL),C
.flk:		LD	HL,MB+0xBDAF		; мерцание: на чётных кадрах нота ниже на величину
			CALL	xv
			LD	A,(HL)
			OR	A
			JP	Z,.arp
			LD	A,(MB+0xBD9A)
			AND	1
			LD	A,0
			JP	NZ,.f1
			LD	HL,MB+0xBDB2
			CALL	xv
			LD	A,(HL)
.f1:		LD	C,A
			LD	HL,ZP+0x8D
			CALL	xv
			LD	A,(HL)
			SUB	C
			LD	HL,MB+0xBD6C
			CALL	add_a
			LD	C,(HL)
			CALL	set_audf
.arp:		LD	HL,MB+0xBDB9		; арпеджио: AUDF = база + $BDBD[i] (до $1F)
			CALL	xv
			LD	A,(HL)
			OR	A
			JP	Z,.dur
.al:		LD	HL,MB+0xBDB6
			CALL	xv
			LD	A,(HL)
			INC	(HL)
			LD	HL,MB+0xBDBD
			CALL	add_a
			LD	A,(HL)
			CP	0x1F
			JP	NZ,.av
			LD	HL,MB+0xBDB6
			CALL	xv
			LD	(HL),0
			JP	.al
.av:		LD	C,A
			LD	HL,MB+0xBDA3
			CALL	xv
			LD	A,(HL)
			ADD	A,C
			LD	C,A
			CALL	set_audf
.dur:		LD	HL,ZP+0x87
			CALL	xv
			DEC	(HL)
			LD	A,(mx)
			DEC	A
			LD	(mx),A
			JP	P,.ch
			RET
; байт паттерна: A = (mptr + my); pnext — следующий (my + 1)
pnext:		LD	HL,my
			INC	(HL)
pbyte:		LD	HL,(mptr)
			LD	A,(my)
			CALL	add_a
			LD	A,(HL)
			RET
; AUDF канала mx = C
set_audf:	LD	A,(mx)
			ADD	A,A
			LD	HL,pk
			CALL	add_a
			LD	(HL),C
			RET

; ---- события игры (из логики, plat_sound: A = SND_*) ----
plat_sound:	PUSH	HL
			PUSH	DE
			PUSH	BC
			DI
			LD	C,A
			AND	0xF0
			CP	SND_SW0
			JP	Z,.sw
			CP	SND_HIT0
			JP	Z,.hit
			CP	SND_KO
			JP	Z,.ko
			CP	SND_IDOL
			JP	Z,.idol
			CP	SND_ROOM
			JP	Z,.room
			JP	.e
.sw:		JP	.e					; замах и бросок — без звука (владелец 15.11)
.fxs:		LD	A,(mx)				; AUDC = 2X, AUDF = B
			ADD	A,A
			LD	C,A
			LD	HL,pk
			CALL	add_a
			LD	(HL),B
			INC	HL
			LD	(HL),C
			LD	A,1					; $24CB: подыгрывание — пауза
			LD	(SW+0x24E8),A
			XOR	A
			LD	(SW+0x24E6),A
			JP	.e
.hit:		LD	A,C					; $24B6: затухающий шум от 16, AUDF $40
			AND	1
			LD	(mx),A
			LD	HL,SV+0x2410
			CALL	xv
			LD	(HL),0xFE
			LD	HL,SV+0x240D
			CALL	xv
			LD	(HL),0x10
			LD	B,0x40
			JP	.fxs
.idol:		LD	A,0x0F				; $2CC6: «тук» (чистый тон AUDF 8, громкость 15..0); 200 тиков — нет
			LD	(SV+0x2416),A			; (владелец 15.11: идол — короткий звук)
			XOR	A
			JP	.tk
.ko:		LD	A,(zv_E8AA)			; $1DC7: тиков по типу бойца — $1DC4[тип] = 40/80/60/140
			LD	HL,zv_E88D
			CALL	add_a
			LD	A,(HL)
			AND	3
			LD	HL,ko_ticks
			CALL	add_a
			LD	A,(HL)
.tk:		LD	(snd_9f5a),A
			JP	.e
.room:		LD	A,0x3F				; $1655: свист + $24D6 (заглушить всё)
			LD	(SV+0x2417),A
			CALL	snd_mute
.e:			EI
			POP	BC
			POP	DE
			POP	HL
			RET
; $24D6: AUDC1..AUDCTL = 0
snd_mute:	LD	HL,pk+1
			LD	B,8
			XOR	A
.l:			LD	(HL),A
			INC	HL
			DEC	B
			JP	NZ,.l
			RET
; новая игра: песня с начала ($BBE0)
; заставка (меню): песня с начала, шумовые удары баса есть (в игре — нет: MUS_NZ)
snd_title:	DI
			XOR	A
			LD	(snd_pause),A
			LD	(snd_cc),A
			INC	A
			LD	(mus_tt),A
			LD	A,0x40
			LD	(MB+0xBDBC),A
			EI
			RET
snd_newgame: DI
			XOR	A
			LD	(mus_tt),A
			LD	A,0x40
			LD	(MB+0xBDBC),A
			XOR	A
			LD	(SV+0x2417),A
			LD	(snd_9f5a),A
			EI
			RET
; режим: враг в комнате или начисляются очки — подыгрывание ($CC = $FF), иначе песня ($1716/$174B)
; Отложенные очки ($E4C2) песню не держат (владелец 18.11: «после взятия сокровища долгая пауза до мелодии»): у ZX/
; Вектора они уходят в счёт по 2 за проход (идол 200 — ~8 с), у Atari счёт идёт вместе с тиканьем (200 тиков — 3,3 с)
snd_mode:	LD	C,0xFF
			LD	A,(snd_9f5a)		; $173C: песня — только когда тикание кончилось
			OR	A
			JP	NZ,.s
			LD	B,5
.l:			LD	A,B
			CALL	rec_a
			LD	DE,8
			ADD	HL,DE
			LD	A,(HL)
			OR	A
			JP	Z,.s				; есть активный враг
			DEC	B
			JP	NZ,.l
			LD	C,0
.s:			LD	A,C
			LD	(snd_cc),A
			RET

; ---- виртуальный POKEY -> ВИ53 (каждый кадр) ----
; канал k (0..2) -> счётчик k; канал 4 с громкостью — на счётчике 2 вместо канала 3, а канал 3 тогда — на счётчике 1,
; если канал 2 молчит (свист: шум канала 3 + жужжание канала 4)
snd_out:	LD	A,0xFF
			LD	(nz_ch),A
			LD	A,(snd_on)
			OR	A
			JP	Z,snd_silent
	IF	AMB_PH
			LD	A,(pk+1)			; подыгрывание (владелец 15.11: «вариант Atari, приглуши»): нота канала 3 с громкостью
			LD	B,A					; 1..2 при молчащих каналах 1, 2 — на счётчиках 0 и 1 почти в противофазе (тихо)
			LD	A,(pk+3)
			OR	B
			AND	0x0F
			JP	NZ,.na
			LD	A,(pk+5)
			SUB	0xA1
			CP	2
			JP	NC,.na
			LD	A,(pk+4)
			LD	HL,amb_k
			CP	(HL)
			LD	(HL),A
			CALL	NZ,amb_go
			LD	C,2					; счётчик 2 — только канал 4
			LD	HL,pk+6
			JP	out_ch
.na:		XOR	A
			LD	(amb_k),A
	ENDIF
			LD	C,0
			LD	A,(SV+0x2416)		; «тук» идола: счётчики 0 и 1 — затухание сдвигом фазы (thud_out)
			OR	A
			JP	Z,.c0
			CALL	thud_out
			LD	C,2
			JP	.c2
.c0:		LD	HL,pk
			CALL	out_ch
			INC	C
			LD	HL,pk+2				; счётчик 1: канал 2; если звучит канал 4, а канал 2 молчит — канал 3
			LD	A,(pk+7)
			AND	0x0F
			JP	Z,.c1
			LD	A,(pk+3)
			AND	0x0F
			JP	NZ,.c1
			LD	HL,pk+4
.c1:		CALL	out_ch
			INC	C
.c2:		LD	HL,pk+4				; счётчик 2: канал 4, если звучит, иначе канал 3
			LD	A,(pk+7)
			AND	0x0F
			JP	Z,out_ch
			LD	HL,pk+6
; голос: HL = AUDF канала, C = счётчик. Громкость 0 — тишина; чистый тон (AUDC бит 7 и бит 5) — делитель
; (AUDF+1)*47; полином 4 (биты 7,6 и не 5): у песни (каналы 1..3, бас) — как тон, у канала 4 (свист, тикание) —
; тон на основной частоте полинома (период 15 тактов): делитель (AUDF+1)*352; иначе шум — биты на счётчик
out_ch:		LD	E,(HL)				; AUDF
			INC	HL
			LD	A,(HL)				; AUDC
			LD	B,A
			AND	0x0F
			JP	Z,.off
			LD	A,B
			AND	0x80
			JP	Z,.nz
			LD	A,B
			AND	0x20
			JP	NZ,.tone
			LD	A,B
			AND	0x40
			JP	Z,.nz
			LD	A,L
			CP	low (pk+7)
			JP	NZ,.tone
	IF	P4_MODE == 4
			JP	.tone				; полином как чистый тон (AUDF+1)*47
	ENDIF
	IF	P4_MODE && P4_MODE < 4
			LD	D,1					; владелец 15.11: «хрипло через полином, как у Atari» — генератор шума свободен:
			LD	A,(nz_ch)			; биты полинома 4
			INC	A
			JP	Z,.nzp
	ENDIF
			JP	.off				; занят (свист: шум канала 3) — жужжание канала 4 молчит (владелец 15.11 выбрал 9b)
.nz:
	IF	MUS_NZ
			LD	A,(mus_tt)			; на заставке удары баса — шумом
			OR	A
			JP	NZ,.nzs
			LD	A,(snd_cc)			; песня (владелец 15.11: «музыку без ударов баса»): шум баса —
			OR	A
		IF	MUS_NZ == 1
			JP	P,.off				; молчит
		ELSE
			JP	P,.tone				; тон той же высоты
		ENDIF
	ENDIF
.nzs:		LD	D,0
.nzp:		LD	A,(nz_ch)			; шум: первый шумящий канал — биты на его счётчик
			INC	A
			JP	NZ,.off
			LD	A,C
			LD	(nz_ch),A
			LD	A,D
			LD	(nz_p4),A
			PUSH	HL
			CALL	nz_setd
			POP	HL
			CALL	nz_dens
	IF	P4_MODE == 2
			LD	A,(nz_p4)			; полином: единица — половина бита
			OR	A
			JP	Z,.p4h
			LD	HL,(nz_dly)
			LD	A,H
			CP	2					; бит длиннее 511 витков: половина не влезает в байт — 255 (было 1, 2, 4...:
			LD	A,255				; иглы вместо единиц, тиканье идола пропадало — владелец 18.11)
			JP	NC,.p4w
			LD	A,H
			RRA
			LD	A,L
			RRA
			JP	NZ,.p4w
			INC	A
.p4w:		LD	(nz_thr),A
.p4h:
	ENDIF
			LD	HL,vi_last			; счётчик занят шумом: при возврате к тону — перепрограммировать
			LD	A,C
			ADD	A,A
			CALL	add_a
			LD	(HL),0xFF
			INC	HL
			LD	(HL),0xFF
			RET
.tone:		LD	D,0					; HL = (AUDF+1)*47
			INC	DE
			LD	H,D
			LD	L,E
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL				; 16
			PUSH	HL
			ADD	HL,HL				; 32
			EX	DE,HL				; DE = 32x, HL = x
			EX	(SP),HL				; HL = 16x, (SP) = x
			ADD	HL,DE				; 48x
			POP	DE
			LD	A,L
			SUB	E
			LD	L,A
			LD	A,H
			SBC	A,D
			LD	H,A					; 47x
			JP	vi_set
.off:		LD	HL,0
			JP	vi_set
; счётчик C (0..2) = делитель HL (0 — тишина); перепрограммируется только при смене
vi_set:		PUSH	BC
			LD	A,C
			ADD	A,A
			LD	B,A
			PUSH	HL
			LD	HL,vi_last
			LD	A,B
			CALL	add_a
			POP	DE					; DE = делитель
			LD	A,(HL)
			CP	E
			JP	NZ,.ch
			INC	HL
			LD	A,(HL)
			DEC	HL
			CP	D
			JP	Z,.x
.ch:		LD	(HL),E
			INC	HL
			LD	(HL),D
			LD	A,C					; управляющее слово: счётчик << 6
			RRCA
			RRCA
			LD	B,A
			LD	A,D
			OR	E
			JP	Z,.sil
			LD	A,B
			OR	0x36				; режим 3, младший и старший байт
			OUT	(0x08),A
			LD	A,0x0B				; порт счётчика: 0 -> 0B, 1 -> 0A, 2 -> 09
			SUB	C
			LD	(.p1+1),A
			LD	(.p2+1),A
			LD	A,E
.p1:		OUT	(0x0B),A
			LD	A,D
.p2:		OUT	(0x0B),A
.x:			POP	BC
			RET
.sil:		LD	A,B
			OR	0x30				; режим 0 без счёта — выход внизу
			OUT	(0x08),A
			POP	BC
			RET
vi_last:	DW	1,1,1
; задержка бита шума канала с AUDF = E: бит раз в 47*(AUDF+1) тактов -> 3*(AUDF+1) - 8 витков (не меньше 1),
; 16 бит -> nz_dly/nz_dlh; портит A, D, HL
; оружие в руках героя (владелец 18.11: «информацию о количестве оружия на руках», «максимум три предмета — проще
; их иконки помещать в HUD»): строка счёта, столбцы 27..29 — значки подряд (нож — как на полу, сюрикен — крест),
; остальные пусты. Каждый проход, рисует только при смене набора
wpn_hud:	LD	HL,zv_E888
			LD	DE,zv_E866+4
			LD	BC,0x0300			; B — оружий, C — набор: по 2 бита (0 нет, 1 сюрикен, 3 нож), оружие 0 — старшие
.l:			LD	A,C
			ADD	A,A
			ADD	A,A
			LD	C,A
			LD	A,(HL)				; владелец 1 — герой
			DEC	A
			JP	NZ,.n
			LD	A,(DE)				; +4: картинка — 0 сюрикен ($FF62), иначе нож
			INC	C
			OR	A					; (после INC C — иначе флаг Z от него и всегда нож; 19.11)
			JP	Z,.n
			INC	C
			INC	C
.n:			INC	HL
			PUSH	HL
			LD	HL,11
			ADD	HL,DE
			EX	DE,HL
			POP	HL
			DEC	B
			JP	NZ,.l
			LD	HL,wh_last
			LD	A,C
			CP	(HL)
			RET	Z
			LD	(HL),A
			LD	HL,23*32+27
			LD	B,3
.d:			LD	A,C
			ADD	A,A
			ADD	A,A
			LD	C,A
			AND	0xC0
			JP	Z,.sk
			LD	DE,p6_lie
			CP	0xC0
			JP	Z,.dr
			LD	DE,p6_ff62
.dr:		CALL	.put
.sk:		DEC	B
			JP	NZ,.d
.cl:		LD	A,L					; остальные столбцы до 29 — пусто
			CP	low (23*32+30)
			RET	NC
			LD	DE,zero8
			CALL	.put
			JP	.cl
.put:		LD	(pr_cell),HL
			PUSH	HL
			PUSH	BC
			LD	BC,AMAP				; цвет — как оружие на поле: перо 3 на сером (владелец 19.11)
			ADD	HL,BC
			LD	(HL),0x0B
			CALL	cell_draw
			POP	BC
			POP	HL
			INC	HL
			RET
wh_last:	DB	0xFF
; собранные идолы — значками в строке счёта, столбцы 16..22 (владелец 18.11: «при сборе указывать не число, а иконками»,
; как в ST); оранжевые на сером. Число за игру только растёт, новая игра — HUD заново (plat_hudinit)
idol_hud:	LD	A,(zv_E4CC)
			OR	A
			RET	Z
			LD	B,A
			LD	HL,23*32+16
.l:			PUSH	BC
			PUSH	HL
			LD	(pr_cell),HL
			LD	BC,AMAP
			ADD	HL,BC
			LD	(HL),0x0A
			LD	DE,idol_ico
			CALL	cell_draw
			POP	HL
			POP	BC
			INC	HL
			DEC	B
			JP	NZ,.l
			RET
; ширина единицы шума D (0 — весь бит) -> nz_thr, не длиннее половины бита (владелец 18.11: «ещё точнее» — тиканье
; идола на коротких битах: импульс длиннее бита, выход не опускался — вдвое громче Atari)
nz_trd:		PUSH	HL
			LD	HL,(nz_dly)
			LD	A,H
			OR	A
			JP	NZ,.ok
			LD	A,L
			RRA
			CP	D
			JP	NC,.ok
			LD	D,A
.ok:		POP	HL
			LD	A,D
			LD	(nz_thr),A
			RET
nz_setd:	LD	L,E
			LD	H,0
			INC	HL
			LD	D,H
			LD	A,L
			ADD	HL,HL
			ADD	A,L
			LD	L,A
			LD	A,H
			ADC	A,D
			LD	H,A					; 3x
			LD	A,L
			SUB	8
			LD	L,A
			LD	A,H
			SBC	A,0
			LD	H,A
			JP	C,.one
			OR	L
			JP	NZ,.st
.one:		LD	HL,1
.st:		LD	(nz_dly),HL
			RET
op_s:		DB	0					; ov_proj (field.asm): место
op_m:		DB	0
; полоса 0 — пустая: корзины CB_BK только что обнулены — это и есть 8 нулевых байтов
cb_z0:		LD	HL,CB_BK
			JP	st_find
snd_silent:	LD	C,0
.l:			LD	HL,0
			CALL	vi_set
			INC	C
			LD	A,C
			CP	3
			JP	NZ,.l
			RET
