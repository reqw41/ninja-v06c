#!/bin/sh
# Run all trace scenarios headless and merge coverage into build/trace/all.
set -e
cd "$(dirname "$0")/.."
PY=tools/.venv/bin/python
SNAP=build/snap/ninja.z80
[ -f $SNAP ] || tools/.venv/bin/tap2sna.py orig/spectrumcomputing/Ninja.tzx/Ninja.tzx $SNAP
R="$PY tools/run_trace.py $SNAP"
T=build/trace
START="50-54:1,80-84:0"
# 1. scripted play (keyboard)
$R $T/s1_play --hist --frames 6000 --keys "$START,200-700:P,700-760:P+ENTER,760-900:O,900-960:O+ENTER,960-1000:Q,1000-1300:P,1300-1340:Q+P,1340-1400:A,1400-1450:A+ENTER,1450-2000:P,2000-2040:ENTER,2040-2500:O,2500-2600:Q,2600-3500:P,3500-3600:Q,3600-4500:O,4500-6000:P"
# 2. hero knocked out -> death -> GAME OVER -> key -> restart
$R $T/s2_death --hist --frames 2500 --keys "$START,200-620:P,1200-1210:P,1400-1410:1,1500-1505:0" \
   --at "700@ED29:E8A9=1;E8AA=0;E46D=1"
# 3. enemies knocked out (slots 1..5), score
$R $T/s3_ko --hist --frames 4000 --keys "$START,200-620:P,1500-2500:P,2600-3000:O" \
   --at "700@ED29:E8A9=1;E8AA=1;E47C=1" --at "1300@ED29:E8A9=1;E8AA=1;E47C=1" \
   --at "2000@ED29:E8A9=1;E8AA=2;E48B=1" --at "2800@ED29:E8A9=1;E8AA=1;E47C=1"
# 4. idol in the start room (ROOM=6 -> list holds 7)
$R $T/s4_idol --hist --frames 4000 --keys "$START,200-1500:P,1500-2500:O,2500-3200:P" \
   --at "150@FAF3:E4BC=07"
# 5. WINNER: 7 idols in room 4, then key -> restart
$R $T/s5_win --hist --frames 1500 --keys "$START,600-610:P,800-810:1,900-905:0" \
   --at "300@ED5D:E4CC=07;E4BA=04"
# 6. other control types: 2 Kempston, 3 Cursor, 4 Sinclair
$R $T/s6_kemp --hist --frames 600 --keys "50-54:2,80-84:0"
$R $T/s6_curs --hist --frames 1200 --keys "50-54:3,80-84:0,200-600:8,600-700:8+0,700-900:5,900-950:7"
$R $T/s6_sinc --hist --frames 1200 --keys "50-54:4,80-84:0,200-600:7,600-700:7+0,700-900:6,900-950:9"
# 7. redefine keys (5), then keyboard play with new keys
$R $T/s7_redef --hist --frames 2500 --keys "50-54:5,150-155:W,250-255:S,350-355:K,450-455:L,550-555:SPACE,700-704:1,800-804:0,1000-1600:L,1600-1700:L+SPACE"
# 8. pause (G) and abort (F)
$R $T/s8_pause --hist --frames 1500 --keys "$START,200-400:P,500-505:G,700-705:P,900-905:F"
# 9. long random walk through rooms, hero kept alive
$R $T/s9_rand --hist --frames 40000 --keys "$START,$($PY tools/randkeys.py 150 40000 1)" --poke 300-40000/50:E46D=0F \
   --shots $(seq -s, 1000 1000 39999)
# 10. floor hole: start in room 17 (poke 7 before ENTER_ROOM(1)), walk to X=18..20, crouch (down)
$R $T/s10_down --hist --frames 1600 --keys "$START,200-400:P,600-900:A" --at "0@ED1D:E4BA=07"
# 11. ceiling hole: start in room 8 (poke 3), stand at X=7..9, push up
$R $T/s11_up --hist --frames 1400 --keys "$START,200-205:P,400-700:Q" --at "0@ED1D:E4BA=03"
# 12. NOT original behaviour: CHECK_HITS fixed to test field +8 ($EF4F: B3 -> B4), enemies land hits
$R $T/s12_fixhits --hist --frames 1500 --keys "$START,200-620:P,900-905:1,1000-1004:0" --poke 0:EF4F=B4
# 13. long random walk, hero mortal (original rules): checks that the hero takes no damage.
#     Without the bug-1 fix this seed crashes at frame 3531 (interrupt during the PUSH fill
#     in CLEAR_SCREEN, see docs/MAIN_LOOP.md), so the BUGFIX.tzx patch (CALL $03F7) is applied.
$R $T/s13_mortal --hist --frames 30000 --keys "$START,$($PY tools/randkeys.py 150 30000 2)" --poke 0:E2CB=F7 --poke 0:F909=F7
$PY tools/merge_hist.py $T/all $T/s1_play $T/s2_death $T/s3_ko $T/s4_idol $T/s5_win \
   $T/s6_kemp $T/s6_curs $T/s6_sinc $T/s7_redef $T/s8_pause $T/s9_rand $T/s10_down $T/s11_up $T/s12_fixhits $T/s13_mortal
