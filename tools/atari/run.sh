#!/bin/sh
# Headless MAME run of Ninja Atari 8-bit (Mastertronic US ATR): tools/atari/run.sh OUTDIR [machine] [mame args]
# NINJA_SECONDS must stay < 300 (MAME skips the bad-checksum warning only then). ROMs: $A8_ROMPATH or ~/projects/tony-a8/roms. env as in tools/atari/pokey.lua
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$1"; shift
MACH="${1:-a800xl}"; [ $# -gt 0 ] && shift
mkdir -p "$OUT"
NINJA_LOG="${NINJA_LOG:-$OUT/pokey.log}" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy mame "$MACH" \
  -rompath "${A8_ROMPATH:-$HOME/projects/tony-a8/roms}" \
  -flop1 "$ROOT/orig/zip-us/Ninja (1986)(Mastertronic)(US).atr" \
  -script "$ROOT/tools/atari/pokey.lua" -skip_gameinfo -nothrottle -sound none -video soft -seconds_to_run ${NINJA_SECONDS:-299} \
  -snapshot_directory "$OUT/snap" -cfg_directory "$OUT/cfg" -nvram_directory "$OUT/nv" "$@" 2>&1 | grep -v -i -E "opengl|checksum|expected|found:|warning"
