#!/bin/sh
# Ninja CPC in a MAME window with sound (disk MT0015). Menu: 0 start, 1 keyboard, 2 joystick.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec mame cpc6128 \
  -rompath "${CPC_ROMPATH:-$HOME/projects/knightlore-research/cpc/roms}" \
  -flop1 "$ROOT/orig/Ninja (UK) (1987) (Version MT0015).dsk" \
  -script "$ROOT/tools/cpc/boot_window.lua" -skip_gameinfo -window -nomaximize \
  -cfg_directory "$ROOT/build/cpcrun/cfg_window" -nvram_directory "$ROOT/build/cpcrun/nv_window" "$@"
