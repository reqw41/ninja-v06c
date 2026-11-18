#!/bin/sh
# ZX goldens for the port (docs/PORT_PLAN.md stage 1): one step per main-loop pass, port fixes on.
# Output: build/golden/*.jsonl.gz (+ *.map executed addresses); regenerate any time (deterministic).
set -e
cd "$(dirname "$0")/.."
PY=tools/.venv/bin/python
G="$PY tools/golden.py"
O=build/golden
mkdir -p $O
[ -f build/snap/ninja.z80 ] || tools/.venv/bin/tap2sna.py orig/spectrumcomputing/Ninja.tzx/Ninja.tzx build/snap/ninja.z80
# '1' held 20 frames every 300: starts the game from the menu, restarts after GAME OVER / WINNER;
# in play '1' is not a control key
restart() { seq "$1" 300 "$2" | awk '{printf "%s%d-%d:1", (NR>1?",":""), $1, $1+20}'; }
rnd() { $PY tools/randkeys.py 150 "$1" "$2"; }

$G $O/g0_play.jsonl.gz  --map $O/g0_play.map  --frames 2000 --keys "50-54:1,200-700:P,700-760:P+ENTER,760-900:O,900-960:O+ENTER,960-1000:Q,1000-1300:P,1300-1340:Q+P,1340-1400:A,1400-1450:A+ENTER,1450-2000:P,2000-2040:ENTER,2040-2500:O,2500-2600:Q,2600-3500:P,3500-3600:Q,3600-4500:O,4500-8000:P"
$G $O/g1_tour.jsonl.gz  --map $O/g1_tour.map  --frames 12000 --tour 25 --keys "50-54:1,$(restart 300 12000),$(rnd 12000 11)"
$G $O/g2_rand.jsonl.gz  --map $O/g2_rand.map  --frames 30000 --keys "50-54:1,$(restart 300 30000),$(rnd 30000 1)"
$G $O/g3_rand.jsonl.gz  --map $O/g3_rand.map  --frames 30000 --keys "50-54:1,$(restart 300 30000),$(rnd 30000 2)"
# idols: every IDOL_ROOMS entry = start room (4+1), random play there; then 7 idols in room 4 -> WINNER
$G $O/g4_idols.jsonl.gz --map $O/g4_idols.map --frames 8000 --keys "50-54:1,$(restart 300 8000),$(rnd 8000 3)" \
   --at-step "3:E4BC=05;E4BD=05;E4BE=05;E4BF=05;E4C0=05;E4C1=05" --at-step "400:E4CC=07"
# 6th idol ($F5B2: opens 17 -> 10): idols already 5, the first pickup in room 4 makes 6, the next 7 -> WINNER
$G $O/g7_idol6.jsonl.gz --map $O/g7_idol6.map --frames 6000 --keys "50-54:1,$(restart 300 6000),$(rnd 6000 4)" \
   --at-step "3:E4BC=05;E4BD=05;E4BE=05;E4BF=05;E4C0=05;E4C1=05;E4CC=05"
# enemy queue ($EF02): room 7 with 4 enemies (17 left -> 7), two forced knockouts: the second one brings
# the waiting 4th enemy (state 2) into the freed name slot
$G $O/g8_queue.jsonl.gz --map $O/g8_queue.map --frames 3000 --keys "50-54:1,$(restart 300 3000),$(rnd 3000 5)" \
   --at-step "3:DAA8=F1;DAA9=F2;DAAA=F3;DAAB=F1;E4BB=11;E461=01" \
   --at-step "10:E47C=00;E8A8=01;EE8C=FF;E8AA=01" --at-step "40:E48B=00;E8A8=01;EE8C=FF;E8AA=02"
# controls: 2 Kempston, 3 Cursor (5678 + 0), 4 Sinclair (67890), 5 redefine W S K L SPACE
$G $O/g5_kemp.jsonl.gz  --map $O/g5_kemp.map  --frames 1500 --keys "50-54:2,80-84:0,$(restart 600 1500)"
$G $O/g5_curs.jsonl.gz  --map $O/g5_curs.map  --frames 2000 --keys "50-54:3,80-84:0,200-600:8,600-700:8+0,700-900:5,900-950:7,950-1500:8"
$G $O/g5_sinc.jsonl.gz  --map $O/g5_sinc.map  --frames 2000 --keys "50-54:4,80-84:0,200-600:7,600-700:7+0,700-900:6,900-950:9,950-1500:7"
$G $O/g5_redef.jsonl.gz --map $O/g5_redef.map --frames 3000 --keys "50-54:5,150-155:W,250-255:S,350-355:K,450-455:L,550-555:SPACE,700-704:1,800-804:0,1000-1600:L,1600-1700:L+SPACE,1700-2500:K"
# start with '0' (default controls), pause (G), abort to menu (F)
$G $O/g6_pause.jsonl.gz --map $O/g6_pause.map --frames 2000 --keys "50-54:0,200-400:P,500-505:G,700-705:P,900-905:F,1000-1020:1,1100-1500:P"
# the original game (no fixes, interrupts on) for comparison
$G $O/o0_play.jsonl.gz  --map $O/o0_play.map  --frames 8000 --orig --keys "50-54:1,$(restart 300 8000),200-700:P,700-760:P+ENTER,760-900:O,900-960:O+ENTER,1450-2000:P,2600-3500:P,4500-8000:P"
cat $O/g*.map | sort -u > $O/all.map
echo "logic coverage: $(wc -l < $O/all.map) RAM addresses (fixed-game goldens)"
