#!/usr/bin/env bash
# Two Godot players against the Tower Siege server (tower-siege/server): one hosts, the other
# joins as guest. Checks the guest's road reaches the host, the host's result reaches both, and
# the server's trophies and clans work. Then two more matches where the guest's connection
# drops and then the host's: the match pauses and carries on when they're back.
# Used by .github/workflows/tower-siege-godot.yml.
#   tower-siege-godot/tests/online_match.sh GODOT_BINARY [PORT]
set -u
GODOT="$1"
PORT="${2:-9091}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
PORT=$PORT DATA_FILE="$OUT/data.json" DATABASE_URL= node "$ROOT/tower-siege/server/server.js" > "$OUT/server.log" 2>&1 &
SERVER=$!
sleep 1
# The first player starts searching, so it waits in the queue and hosts
timeout 120 "$GODOT" --headless --path "$ROOT/tower-siege-godot" -s tests/online.gd -- --server=ws://127.0.0.1:$PORT --name=Ann --clan=AA > "$OUT/ann.log" 2>&1 &
ANN=$!
for i in $(seq 1 90); do grep -q "GD SEARCHING" "$OUT/ann.log" && break; sleep 1; done
timeout 120 "$GODOT" --headless --path "$ROOT/tower-siege-godot" -s tests/online.gd -- --server=ws://127.0.0.1:$PORT --name=Bob --clan=BB > "$OUT/bob.log" 2>&1
wait $ANN
# Reconnecting: the guest drops, then (in a new match) the host drops
run_pair() { # host-log host-args guest-log guest-args
  timeout 120 "$GODOT" --headless --path "$ROOT/tower-siege-godot" -s tests/online.gd -- --server=ws://127.0.0.1:$PORT $2 > "$OUT/$1.log" 2>&1 &
  local H=$!
  for i in $(seq 1 90); do grep -q "GD SEARCHING" "$OUT/$1.log" && break; sleep 1; done
  timeout 120 "$GODOT" --headless --path "$ROOT/tower-siege-godot" -s tests/online.gd -- --server=ws://127.0.0.1:$PORT $4 > "$OUT/$3.log" 2>&1
  wait $H
}
run_pair cat "--name=Cat --clan=CC --peer-drops" dan "--name=Dan --clan=DD --drop"
run_pair eve "--name=Eve --clan=EE --drop" fay "--name=Fay --clan=FF --peer-drops"
kill $SERVER 2>/dev/null || true
echo "--- host (Ann)"; grep -a "^GD" "$OUT/ann.log" | grep -v "^GD MAP"
echo "--- guest (Bob)"; grep -a "^GD" "$OUT/bob.log" | grep -v "^GD MAP"
for n in cat dan eve fay; do echo "--- $n"; grep -a "^GD\|SCRIPT ERROR" "$OUT/$n.log" | grep -v "^GD MAP"; done
fail=0
check() { if grep -a -q "$2" "$OUT/$1.log"; then echo "PASS $3"; else echo "FAIL $3"; fail=1; fi; }
check ann "GD MATCH true role=host" "Ann hosts"
check bob "GD MATCH true role=guest" "Bob joins as guest"
check bob "GD GUEST_ROAD true" "The guest's road reaches the host and its soldiers march"
check ann "GD HOST_SAW_ROAD true" "The host sees the guest's road"
check ann "GD RESULT true title=Victory! trophies=30" "The host wins and gets 30 trophies"
check dan "GD DROPPED true" "The guest's connection drops and its match pauses"
check cat "GD WAITED true" "The host waits for the guest"
check dan "GD RESUMED true role=guest" "The guest gets back into the match"
check cat "GD PEER_BACK true" "The host carries on when the guest is back"
check dan "GD GUEST_ROAD true" "After reconnecting, the guest's road still reaches the host"
check dan "GD RESULT true title=Defeat" "The reconnected guest gets the result"
check eve "GD RESUMED true role=host" "The host gets back into the match after its connection drops"
check fay "GD PEER_BACK true" "The guest carries on when the host is back"
check eve "GD HOST_SAW_ROAD true" "After reconnecting, the host still gets the guest's road"
check fay "GD RESULT true title=Defeat" "The guest gets the result from the reconnected host"
check bob "GD RESULT true title=Defeat trophies=0" "The guest sees Defeat"
check ann "GD CLAN clan" "Clans work"
[ "$(grep -a -h "^GD MAP" "$OUT/ann.log")" = "$(grep -a -h "^GD MAP" "$OUT/bob.log")" ] && echo "PASS Same map on both" || { echo "FAIL Same map on both"; fail=1; }
LOGS="$OUT/ann.log $OUT/bob.log $OUT/cat.log $OUT/dan.log $OUT/eve.log $OUT/fay.log"
if grep -a -q "SCRIPT ERROR" $LOGS; then echo "FAIL Script errors"; grep -a -A2 "SCRIPT ERROR" $LOGS | head -20; fail=1; fi
exit $fail
