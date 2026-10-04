#!/usr/bin/env bash
# Two Godot players against the Tower Siege server (tower-siege/server): one hosts, the other
# joins as guest. Checks the guest's road reaches the host, the host's result reaches both, and
# the server's trophies and clans work. Used by .github/workflows/tower-siege-godot.yml.
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
kill $SERVER 2>/dev/null || true
echo "--- host (Ann)"; grep -a "^GD" "$OUT/ann.log" | grep -v "^GD MAP"
echo "--- guest (Bob)"; grep -a "^GD" "$OUT/bob.log" | grep -v "^GD MAP"
fail=0
check() { if grep -a -q "$2" "$OUT/$1.log"; then echo "PASS $3"; else echo "FAIL $3"; fail=1; fi; }
check ann "GD MATCH true role=host" "Ann hosts"
check bob "GD MATCH true role=guest" "Bob joins as guest"
check bob "GD GUEST_ROAD true" "The guest's road reaches the host and its soldiers march"
check ann "GD HOST_SAW_ROAD true" "The host sees the guest's road"
check ann "GD RESULT true title=Victory! trophies=30" "The host wins and gets 30 trophies"
check bob "GD RESULT true title=Defeat trophies=0" "The guest sees Defeat"
check ann "GD CLAN clan" "Clans work"
[ "$(grep -a -h "^GD MAP" "$OUT/ann.log")" = "$(grep -a -h "^GD MAP" "$OUT/bob.log")" ] && echo "PASS Same map on both" || { echo "FAIL Same map on both"; fail=1; }
if grep -a -q "SCRIPT ERROR" "$OUT/ann.log" "$OUT/bob.log"; then echo "FAIL Script errors"; grep -a -A2 "SCRIPT ERROR" "$OUT/ann.log" "$OUT/bob.log" | head -20; fail=1; fi
exit $fail
