; Платформа для сверки (tools/run80.js): ввод и случайность — из очередей эталона через особые порты,
; звук — записи в порт; вывод — пустой.
;   OUT E5,A + IN E0 — чтение порта ZX (A = старший байт адреса, младший FE); OUT E7 + IN E0 — Kempston ($1F)
;   IN E1 — LD A,R; OUT E2,id — звуковое событие (SND_*); OUT E4,n — «не моделируется»
SND_SW0		EQU	0x10			; звуковые события (озвучка Atari, docs/MUSIC.md)
SND_SW1		EQU	0x11
SND_HIT0	EQU	0x20
SND_HIT1	EQU	0x21
SND_KO		EQU	0x30
SND_IDOL	EQU	0x40
SND_ROOM	EQU	0x50

; A = старший байт порта ZX -> A = байт клавиатуры ZX
zx_in:		OUT	(0xE5),A
			IN	A,(0xE0)
			RET
zx_kemp:	OUT	(0xE7),A
			IN	A,(0xE0)
			RET
plat_ldar:	IN	A,(0xE1)
			RET
plat_sound:	OUT	(0xE2),A
			RET
plat_game_over:	LD	A,1
			OUT	(0xE4),A
plat_winner:	LD	A,2
			OUT	(0xE4),A
plat_menu:	LD	A,3
			OUT	(0xE4),A
; вывод (на Векторе — свой): кадр поля во время подъёма, постройка комнаты, надписи
plat_draw:
plat_room:
plat_clear:
plat_approach:
plat_name:
plat_hud:
plat_hudinit:
plat_bar:
			RET
