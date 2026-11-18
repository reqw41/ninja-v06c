# ninja-v06c

Порт **Ninja** (Mastertronic / Entertainment USA, 1986/1987) на **Vector-06C** (БК-клон, KR580VM80A @ 4/8 МГц, 512×192, 128 КБ ОЗУ, AY-3-8910).

## Что в `orig/`

| файл | что это |
|---|---|
| `emu-land-zip/Ninja (1987)(Entertainment USA).tap` | **Целевой образ.** Скачан с emu-land (id=68846). 48K, лента. |
| `emu-land-68846.bin` | сырой ответ emu-land (оказался zip-контейнером того же TAP), md5 `9d3a0330d569745edc7686cb0350ce52` |
| `7z/*.dsk`, `Ninja (UK) (1987) (Version MT0015).dsk` | 5 разных DSK-образов (md5 различны) — **не ZX**: это Amstrad CPC-издания (заголовки `MV - CPCEMU` / `EXTENDED CPC DSK File`, `PLUS3DOS` нет; в байтах `ACME HACKING`, `MEGAC FOR ENTERTAINMENT`, `BLACK SYSTEM`). Файлы `NINJA.BAS`, `NINJA2.BIN`, `NINJA3.BIN`. Распаковка: `tools/cpc_dsk.py` (основной код `NINJA3.BIN`, `$0040`, старт `$5672`). **Эталон оформления графики (палитра CPC) и музыки**, а также логики (сверка ближнего боя — MAIN_LOOP.md) |
| `spectrumcomputing/` | с spectrumcomputing.co.uk/entry/3433: `Ninja.tzx` (Ramsoft MakeTZX), `NINJAMAD.TAP` (= emu-land TAP), `Ninja(BUGFIX).tzx`, исходник багфикса, инструкция, экраны, карты — см. ниже |
| `zip-us/Ninja (1986)(Mastertronic)(US).atr` | **не ZX**: образ Atari 8-bit (6502-код в первых байтах). Тоже **эталон графики и музыки** (POKEY) |
| `Ninja.7z`, `Ninja (1986)(Mastertronic)(US).zip` | исходные архивы, из которых распакованы `7z/` и `zip-us/` (совпадают побайтно с теми, что в `~/Downloads`) |

## Разбор (SkoolKit 10.1)

```sh
python3 -m venv tools/.venv
tools/.venv/bin/python -m pip install skoolkit==10.1
tools/.venv/bin/python tools/build_skool.py
```

Скрипт извлекает последний блок из TAP в `build/zx/ram4000.bin`,
создаёт `build/zx/ninja.skool` по `src/ninja.ctl` и пересобирает дамп.
Проверка сравнивает размер и все 49 024 байта. Затем скрипт пишет
`build/zx/ninja.asm` и `build/zx/html/ninja/index.html`.

### Структура ленты

В TAP пять блоков с корректными контрольными суммами.

1. Заголовок BASIC `NINJA` с длиной 135 байт.
2. Данные загрузчика BASIC со строкой `Loading in 48k mode`.
3. Заголовок BASIC `NINJA` с длиной 55 байт.
4. Данные второй BASIC-программы с машинным кодом загрузчика.
5. Блок данных длиной `0xBF80` без заголовка. Его содержимое соответствует
   диапазону `0x4000..0xFF7F`, запрошенному загрузчиком по адресу `0x69F7`.

При прежних прогонах `tap2sna` загрузка останавливалась в ROM на `0x05F3`; с TZX и SkoolKit 10.1 она проходит до конца (см. «Точка входа»).
Для статического разбора скрипт берёт пятый блок напрямую.

### Загрузчик (разобран, достижим из `0x69DE`)

```
LOADER_2STAGE  0x69DE  LD HL,#EA00 / LD SP,#0000 / XOR A / OUT (#FE),A
                       LD HL,#4000 / LD DE,#4001 / LD BC,#1AFF / LD (HL),A / LDIR   ; очистка экрана
                       LD IX,#4000 / LD DE,#BF80 / LD A,#FF / SCF / CALL #0556  ; LOAD
LOAD_LOOP      0x6A25  ждёт нажатие, три LOAD через ROM (#04C2/#0556)
PAUSE          0x6A56  HALT / DJNZ
WAIT_KEYPRESS  0x6A5C  IN A,(#FE) / RRA / RET NC
```

### Что известно об игре (по строкам образа)

`0xF0AB` `WINNER`, `0xF0D1` `GAME OVER`, `0xDB44` `REDEFINE KEYS`,
комнаты: `0xD925` `TORII IN THE SEA`, `0xD94F` `SHIJO ENTRANCE`,
`0xD968` `AKUMAS CHAMBER`, `0xD9CF` `BIG GREEN DOOR`.
Плотный код: `0x7000-0xD700` и `0xE000-0xFFFF` (≈950 значимых байт на 1K).
`0x4000-0x57FF` — DFILE, `0x5800-0x5BFF` — атрибуты.

## Точка входа (найдена 14.11.2026)

Прежняя версия README утверждала, что репак обрезал блок 5 на 64 байта и вход потерян.
**Это неверно.** Лента с spectrumcomputing.co.uk (`orig/spectrumcomputing/Ninja.tzx`,
снята Ramsoft MakeTZX) содержит блок той же длины `#BF80`, и её код побайтно совпадает с
нашим TAP (`NINJAMAD.TAP` оттуда же = emu-land TAP, md5 `17f0119d…`). Копия загрузчика с
`#BFC0` на `0x6A64` — просто неиспользуемый остаток, а не след порчи.

`tap2sna.py` (без доп. опций) грузит ленту до конца и останавливается на `PC=0x5CEF`:

```
5CEF..5D2E  64 x NOP            ; RET после LOAD приходит сюда (SP=0, IM 1, EI)
5D2F        JP $D714
D714        JP $EBE9
EBE9        LD SP,$0000 / DI / LD A,R / LD ($DEF1),A / XOR A / LD ($E860),A
EBF6        CALL $DFE3          ; очистка атрибутов $5800..$5AFF (PUSH-заливка)
```

Значит, **вход игры — `$EBE9`** (через трамплин `$D714`). Снимок для трассировки:

```sh
tools/.venv/bin/tap2sna.py orig/spectrumcomputing/Ninja.tzx/Ninja.tzx build/snap/ninja.z80
tools/.venv/bin/trace.py -v --max-operations 200 build/snap/ninja.z80
```

## Багфиксы (`orig/spectrumcomputing/`)

`Ninja-BUGFIX-Patch_SourceCode.txt` (POKE от Bandit, файл Einar Saukas) описывает две ошибки
оригинала:

1. **Прерывания включаются не вовремя**, стирается место идола — игру нельзя пройти.
   Причина: звук через ROM `BEEPER` (`$03B5`) кончается `EI` (`$03F6`). Вызовы — в `$E2CA`
   (`LD HL,$02BC / LD DE,$0014`) и `$F908` (цикл с `LD DE,$0003`). Исправление по исходнику:
   `CALL $FF99` — обёртка `LD IY,$5C3A / CALL $03B5 / DI / RET`, ставится в `$FF99..$FFA1`
   кодом в NOP-зоне `$5CEF` и затирает себя.
2. **Номер текущей комнаты хранится в таблице врагов** (`$E4BA`); при множестве врагов в
   комнате он портится. Исправление — 22 правки `$BA→$BB` (ссылки `($E4BA)` → `($E4BB)`) по
   адресам `$EABD…$FDDD`, список в файле.

**Внимание:** скачанный `Ninja(BUGFIX).tzx` этому исходнику **не соответствует**. От
оригинала он отличается ровно двумя байтами: `CALL $03B5` → `CALL $03F7` в `$E2CA` и
`$F908`. `$03F7` — это `RET` в ROM, т.е. эти два звука просто выключены (EI не происходит).
Правки комнаты (`$E4BA→$E4BB`) в нём нет. Для порта брать **логику исходника**: на Векторе
своих ROM-вызовов нет, звук и так переписывается, а прерывания разрешать явно и в нужный
момент; таблицу врагов не пускать на ячейку комнаты.

## Что ещё скачано с spectrumcomputing.co.uk (entry 3433)

`Ninja.txt` (инструкция и управление), `load_Ninja.scr` (экран загрузки),
`ingame_Ninja.gif`, карты `map_Ninja.png`, `map_Ninja_2.png`, `map_Ninja.jpg`;
архивы `*.zip` и распакованные папки рядом.

## Главный цикл и отрисовка

Разобраны трассировкой: **`docs/MAIN_LOOP.md`**. Главный цикл `$ED23`, без HALT,
≈ 3,7 кадра на проход; ~75 % времени — отрисовка через двойной буфер `экран+$1B00`.
Разметка `src/ninja.ctl` генерируется `tools/gen_ctl.py` из карты выполнения.

## План порта

**`docs/PORT_PLAN.md`** — по образцу brucelee-v06c: 3 плоскости (8 цветов, палитра = цвета ZX),
управление и звук (CPC на ВИ53) как в Bruce Lee.

## Следующий шаг

1. Ветки прогнаны (`tools/coverage.sh`, 15 сценариев). Найдены ошибки оригинала:
   враги не попадают в ближнем бою (`$EF4F`, ошибка ZX-переноса — у CPC бьют), падение от прерываний в `CLEAR_SCREEN` —
   раздел «Ошибки оригинала» в MAIN_LOOP.md.
2. Проверить имена с `(?)`, расписать запись бойца.
3. ~~Вынуть данные~~ — `tools/extract_data.py` → `data/`, описание `docs/DATA.md`
   (21 комната сверена с игрой: карта и атрибуты 1:1). Дальше — порт отрисовки.
