#!/bin/sh
# Сборка Ninja для Вектора-06Ц (docs/PORT_PLAN.md). Пока — логика на i8080 для сверки (этап 3).
# Нужны: Python 3, Node.js, sjasmplus 1.24 (tools/sjasmplus или в PATH), cc (для tools/zx0), ~/projects/vector06js (ядро i8080 для стенда).
#   ./build.sh          — сборка build/l80/logic.bin (логика для сверки), build/vec/ninja.bin (игра), rom/Ninja-v06c.*
#   ./build.sh check    — и сверки: JS-модель и i8080 с эталонами ZX, экран Вектора с экраном ZX (tools/vecstep.js)
set -e
cd "$(dirname "$0")"
SJASM=$PWD/tools/sjasmplus; [ -x "$SJASM" ] || SJASM=$(command -v sjasmplus) || { echo 'нет sjasmplus'; exit 1; }
export SJASM
[ -x tools/zx0/zx0 ] || cc -O2 -o tools/zx0/zx0 tools/zx0/zx0.c tools/zx0/compress.c tools/zx0/optimize.c tools/zx0/memory.c
mkdir -p build/l80
[ -f build/zx/ram4000.bin ] || tools/.venv/bin/python tools/build_skool.py
python3 -I tools/mkl80.py
asm() { (cd "$1" && "$SJASM" --nologo --i8080 --sym="../../$2.sym" $4 "$3") > "$2.log" 2>&1 || { cat "$2.log"; exit 1; }
        grep -E "^> " "$2.log" || true; ! grep -q "error:" "$2.log" || { grep error "$2.log"; exit 1; }; }
asm src/i8080 build/l80/logic logic.asm
mkdir -p build/vec
# песня Atari (и шрифт CPC в mkfont.py) — из материалов оригинала (data/, не в публичном репозитории); без них — готовые src/vec/gen
python3 -I tools/mkfont.py >/dev/null
[ -f data/music/atari_bc00.bin ] && python3 -I tools/mksound.py >/dev/null
asm src/vec build/vec/ninja main.asm
[ ! -f build/vec/font_zx.asm ] || asm src/vec build/vec/ninja_t main.asm -DTESTFONT	# шрифт ZX — только для сверки экрана
PY=python3; [ -x tools/.venv/bin/python ] && PY=tools/.venv/bin/python
$PY -W ignore -I tools/mksplash.py			# rom/Ninja-v06c.r0m и .c00: заставка, стартовый экран, игра (нужен Pillow)
if [ "$1" = check ]; then
  [ -f build/golden/g0_play.jsonl.gz ] || tools/goldens.sh
  node tools/model_run.js build/golden/g*.jsonl.gz | sed 's/^/модель: /'
  node tools/run80.js build/golden/g*.jsonl.gz | sed 's/^/i8080:  /'
  for g in build/golden/g*.jsonl.gz; do node tools/vecstep.js "$g" --max 0 | sed 's/^/экран:  /'; done
fi
