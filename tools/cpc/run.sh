#!/bin/sh
# Headless MAME run of Ninja CPC (MT0015 disk): tools/cpc/run.sh OUTDIR [mame args]
# env as in tools/cpc/play.lua. ROMs: $CPC_ROMPATH or ~/projects/knightlore-research/cpc/roms
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$1"; shift
mkdir -p "$OUT"
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy mame cpc6128 \
  -rompath "${CPC_ROMPATH:-$HOME/projects/knightlore-research/cpc/roms}" \
  -flop1 "$ROOT/orig/Ninja (UK) (1987) (Version MT0015).dsk" \
  -script "$ROOT/tools/cpc/play.lua" -skip_gameinfo -nothrottle -sound none -video soft \
  -snapshot_directory "$OUT/snap" -cfg_directory "$OUT/cfg" -nvram_directory "$OUT/nv" "$@" 2>&1 | grep -v -i opengl
