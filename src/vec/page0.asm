; page0.asm: страница 0 (после старта свободна, кроме переходов 0000 и 0038; образ .r0m/.c00 распаковывается с 0000):
; звуковые помощники (место в нижней области — запас полос готовых клеток; пик в комнатах с идолом ≈ 210)
	IFDEF	P0_A
; заставка игры: после стартового экрана загрузчика (он ставит t_skip = 1) — сразу в игру, без ожидания огня
t_chk:		LD	HL,t_skip
			LD	A,(HL)
			LD	(HL),0
			OR	A
			RET	Z
			POP	HL
			JP	game
t_skip:		DB	0
; шаг 4-битного полинома POKEY (x^4 + x^3 + 1, период 15): CY = выходной бит; портит A
p4_step:	LD	A,(p4s)				; Галуа: сдвиг вправо, выпавшая 1 — XOR $0C (тот же период 15)
			OR	A
			RRA
			JP	NC,.n
			XOR	0x0C
			SCF
.n:			LD	(p4s),A
			RET
	IF	AMB_PH
; сдвиг фазы ноты подыгрывания: HL = делитель -> B = делитель * 13 / 256 - AMB_K витков (почти противофаза:
; полпериода = делитель тактов, виток ≈ 20 тактов), HL сохраняется
amb_n:		PUSH	HL
			LD	D,H
			LD	E,L
			ADD	HL,HL
			ADD	HL,DE
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,DE
			LD	A,H
			SUB	AMB_K
			LD	B,A
			POP	HL
			RET
	ENDIF

; длина вспышки шума в прерывании -> HL (витки): свист входа в комнату (владелец 15.11: «не похоже на шум» — вспышка
; 1/3 кадра на длинном звуке слышна жужжанием 50 Гц) — почти весь кадр (игра в это время строит комнату)
nz_span:	LD	HL,NZT_SPAN			; тиканье счёта (идол, враг повержен): своя вспышка — биты ~500 витков, при длинной
			LD	A,(nz_p4)			; обработчик длиннее кадра и прерывания теряются (владелец 18.11: «поточнее»); только
									; когда шумит полином 4 (при ударе в то же время — короткие биты, вспышка обычная)
			OR	A
			RET	NZ
			LD	HL,NZ_SPAN
			LD	A,(SV+0x2417)
			OR	A
			RET	Z
			LD	HL,NZW_SPAN			; и случайный свист в бою (владелец 15.11: «11_wrand.vec_long»)
			RET
	ELSE
; плотность шума канала (out_ch, sound.asm): L = младший байт адреса AUDC, B = AUDC; портит A, D
nz_dens:
			LD	A,128
			LD	(nz_thin),A
			LD	D,0					; эффект боя (замах, удар): единица шума — громкость * 6 витков, спад как у Atari (владелец 15.11:
			LD	A,L					; «замах тише», «звуки резкие»); прочее — полная
			SUB	low (pk+1)
			CP	6
	IF	P4_MODE == 3
			JP	Z,nzd_v				; канал 4 (тикание, полином) — тоже по громкости
	ENDIF
			JP	NC,nzd_th
			CP	4					; канал 3 во время свиста — тоже по громкости (n >> 3)
			JP	NZ,.nw
			LD	A,(SV+0x2417)
			OR	A
			JP	NZ,nzd_wv
			LD	A,4
.nw:		RRCA
			PUSH	HL
			LD	HL,SV+0x240D		; эффект на канале идёт
			CALL	add_a
			LD	A,(HL)				; громкость эффекта (шаг $2410 при ней не 0)
			OR	A
			POP	HL
			JP	Z,nzd_th
	IFNDEF	NO_P5
			PUSH	HL					; удар/замах — искажение 0 Atari: бит полинома 17 защёлкивается, только когда бит
			LD	HL,(nz_dly)			; полинома 5 = 1 (16 из 31) — смена битов вдвое реже делителя (владелец 18.11:
			ADD	HL,HL				; «поточнее»; замер: частота шума удара 458 против 304 у Atari)
			LD	(nz_dly),HL
			POP	HL
			LD	A,B					; единица — громкость * 12 витков (бит вдвое длиннее — та же доля бита)
			AND	0x0F
			LD	D,A
			ADD	A,A
			ADD	A,D
			ADD	A,A
			ADD	A,A
			LD	D,A
			JP	nzd_th
	ENDIF
nzd_v:		LD	A,B
			AND	0x0F
			LD	D,A
			ADD	A,A
			ADD	A,D
			ADD	A,A
			LD	D,A
			JP	nzd_th
nzd_wv:		PUSH	HL					; свист: громкость — WH_TH 0: доля бита громкость / 8; 1, 2: редкостью единиц
			LD	HL,(nz_dly)			; высота как у Atari (владелец 18.11: вариант 4; 15.11 было «ниже» — бит вдвое длиннее)
			LD	A,L
			OR	H
			JP	Z,nzd_w0
			LD	A,H
			OR	A
			LD	A,L
			JP	Z,nzd_wl
			LD	A,255
nzd_wl:
	IF	WH_TH
			LD	A,B					; громкость редкостью единиц: вероятность ~ громкость² (у Atari 7..0)
			AND	0x0F
			JP	Z,nzd_w0
			LD	D,A
			LD	B,A
			XOR	A
nzd_sq:		ADD	A,D
			DEC	B
			JP	NZ,nzd_sq
		IF	WH_TH == 3
			LD	A,D					; по таблице громкости
			LD	HL,wh_tab
			ADD	A,L
			LD	L,A
			LD	A,(HL)
		ELSEIF	WH_TH == 2
			LD	A,D					; линейно: громкость * 18
			ADD	A,A
			ADD	A,A
			ADD	A,A
			ADD	A,D
			ADD	A,A
		ELSE
			LD	D,A					; громкость² * 2,5
			ADD	A,A
			LD	B,A
			LD	A,D
			OR	A
			RRA
			ADD	A,B
		ENDIF
			LD	(nz_thin),A
			LD	D,0
			POP	HL
			JP	nzd_th
		IF	WH_TH == 3
wh_tab:		DB	0,WT1,WT2,WT3,WT4,WT5,WT6,WT7
		ENDIF
	ELSE
			LD	E,A
			LD	D,0
			LD	H,D
			LD	L,D
			LD	A,B
			AND	0x0F
			JP	Z,nzd_w0
			LD	B,A
nzd_wm:		ADD	HL,DE
			DEC	B
			JP	NZ,nzd_wm
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			LD	A,H
			OR	A
			JP	NZ,nzd_w1
	ENDIF
nzd_w0:		INC	A
nzd_w1:		LD	D,A
			POP	HL
nzd_th:		JP	nz_trd				; ширина единицы (sound.asm: не длиннее половины бита)
ko_ticks:	DB	40,80,60,140			; $1DC4: тиков счёта за поверженного по типу

; «тук» идола (владелец 15.11: «тук короче, чем у Atari» — у Atari громкость гаснет 15..0): чистый тон AUDF 8
; (делитель 9*47 = 423) на счётчиках 0 и 1 сразу, второй запущен позже на (14 - громкость) * 1,5 витка: сумма выходов
; — тон с громкостью |cos| сдвига (в противофазе — тишина); каналы 1, 2 Atari на это время — только «тук»
thud_out:	LD	A,(pk+1)			; громкость 14..0
			AND	0x0F
			CPL
			ADD	A,15				; 14 - v
			LD	B,A					; витков (14 - v) * 1,5 + 1: противофаза (423 такта) — при громкости 0
			OR	A
			RRA
			ADD	A,B
			INC	A
			LD	B,A
			LD	HL,423
; тон с делителем HL на счётчиках 0 и 1, второй — позже на B витков (громкость сдвигом фазы)
ph_out:		LD	A,0x36				; только из прерывания (DI/EI не трогать)				; счётчик 0: режим 3
			OUT	(0x08),A
			LD	A,L
			OUT	(0x0B),A
			LD	A,H
			OUT	(0x0B),A
.d:			DEC	B
			JP	NZ,.d
			LD	A,0x76				; счётчик 1: режим 3 — позже
			OUT	(0x08),A
			LD	A,L
			OUT	(0x0A),A
			LD	A,H
			OUT	(0x0A),A
			LD	HL,0xFFFF			; потом счётчики 0, 1 — перепрограммировать
			LD	(vi_last),HL
			LD	(vi_last+2),HL
			RET
	IF	AMB_PH
; нота подыгрывания: A = AUDF -> делитель (AUDF+1)*47 на счётчиках 0, 1 почти в противофазе (amb_n)
amb_go:		LD	L,A
			LD	H,0
			INC	HL
			LD	E,L
			LD	D,H
			ADD	HL,HL
			ADD	HL,DE
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			ADD	HL,HL
			LD	A,L
			SUB	E
			LD	L,A
			LD	A,H
			SBC	A,D
			LD	H,A
			CALL	amb_n
			JP	ph_out
	ENDIF

	ENDIF
