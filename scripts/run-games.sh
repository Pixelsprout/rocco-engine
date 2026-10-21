#!/bin/sh
# Run each named game for FRAMES frames and check that it exits with 0 and
# prints exactly one "Frame Count: FRAMES" line on stdout. Each game must
# already be linked for this machine. The check reads stdout only: sokol can
# end a long stderr line with no newline, which would hide the line.
# RUN_PREFIX wraps each run, for example "xvfb-run -a" in the Linux image.
# A game in a subfolder, such as tutorial/01-window, runs 01-window.bin.
set -eu
cd "$(dirname "$0")/.."

if [ "$#" -lt 2 ]; then
	echo "Usage: scripts/run-games.sh FRAMES GAME..." >&2
	exit 2
fi
frames=$1
shift

# eval "$(...)" would hide a build.roc failure from set -e.
target_lines=$(roc scripts/build.roc -- target)
eval "$target_lines"

log=$(mktemp)
err=$(mktemp)
trap 'rm -f "$log" "$err"' EXIT
expected="Frame Count: $frames"

for game in "$@"; do
	echo "== run $game for $frames frames"
	dir=examples/$game
	set +e
	(cd "$dir" && ROCCO_EXIT_AFTER_FRAMES=$frames ${RUN_PREFIX:-} "./${game##*/}${suffix}") > "$log" 2> "$err"
	code=$?
	set -e
	frame_count_lines=$(grep -c '^Frame Count: ' "$log" || true)
	if [ "$code" -ne 0 ] || [ "$frame_count_lines" -ne 1 ] || ! grep -qx "$expected" "$log"; then
		tail -40 "$err" >&2
		tail -40 "$log" >&2
		echo "FAIL: $game exit=$code, frame count lines=$frame_count_lines, expected '$expected'" >&2
		exit 1
	fi
	echo "PASS: $game exit=0, $expected"
done
