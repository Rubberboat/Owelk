#!/bin/sh
# CPU time Owelk uses with the desktop pet off and on, over the same stretch of time.
# OWELK_PET_FIRST=nap measures it asleep (breathing), the default sitting.
# Usage: tools/pet_cpu.sh [owelk binary] [seconds]   (OWELK_QPA=offscreen runs without showing windows)
set -eu
BIN=${1:-build/owelk.app/Contents/MacOS/owelk}
SECONDS_EACH=${2:-90}
measure() {
    dir=$(mktemp -d)
    # A first launch makes the store; then the pet is switched on or left off in its settings.
    "$BIN" --data-dir "$dir" --smoke-test >/dev/null 2>&1 || true
    sqlite3 "$dir/owelk.sqlite3" "INSERT OR REPLACE INTO settings(key,value) VALUES('pet.enabled','$1')"
    if [ -n "${OWELK_QPA:-}" ]; then export QT_QPA_PLATFORM=$OWELK_QPA; fi
    "$BIN" --data-dir "$dir" >/dev/null 2>&1 &
    pid=$!
    sleep 8   # start up
    kill -0 $pid 2>/dev/null || { echo "pet.enabled=$1: Owelk quit during start-up"; return; }
    start=$(ps -o time= -p $pid | awk -F'[:.]' '{print $1*60+$2+$3/100}')
    sleep "$SECONDS_EACH"
    kill -0 $pid 2>/dev/null || { echo "pet.enabled=$1: Owelk quit while measuring"; return; }
    end=$(ps -o time= -p $pid | awk -F'[:.]' '{print $1*60+$2+$3/100}')
    rss=$(ps -o rss= -p $pid)
    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
    rm -rf "$dir"
    echo "pet.enabled=$1: $(echo "$end $start $SECONDS_EACH" | awk '{printf "%.2f s CPU in %d s = %.2f %%", $1-$2, $3, ($1-$2)/$3*100}'), memory ${rss} KB"
}
# OWELK_SKIP_OFF=1 measures only with the pet on.
[ -n "${OWELK_SKIP_OFF:-}" ] || measure 0
measure 1
