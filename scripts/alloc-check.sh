#!/bin/sh
# Build each game under --opt=dev and --opt=speed, run it with no input and
# ROCCO_ALLOC_REPORT=1, and check every fixed step after the first 10: the
# game's expected allocs and as many deallocs, its expected reallocs and a
# constant live block count. cards expects 2 allocs: the box shell and the
# draws list. entity-game expects 3, because it also returns a colliders list.
# pong expects 13 allocs and 6 reallocs, because Ui.box concats and appends
# to build Scene.ui every frame.
# The host library must already be built for this machine. Each game opens a
# window. Do not type into it: a key press allocates the Input lists.
# RUN_PREFIX wraps each run, for example "xvfb-run -a" in the Linux image.
set -eu
cd "$(dirname "$0")/.."

FRAMES=240
SKIP=10
# eval "$(...)" would hide a build.roc failure from set -e.
target_lines=$(roc scripts/build.roc -- target)
eval "$target_lines"

log=$(mktemp)
trap 'rm -f "$log"' EXIT
failed=0

for entry in cards:2:0 entity-game:3:0 pong:13:6; do
	game=${entry%%:*}
	rest=${entry#*:}
	want=${rest%%:*}
	want_re=${rest##*:}
	for opt in dev speed; do
		bin="./${game}_alloc_${opt}${suffix}"
		# Exit 2 is warnings only, such as the dbg in packages/mesh. build.roc allows it too.
		set +e
		(cd "examples/$game" && roc build --target="$target" --opt="$opt" --output="$bin" main.roc) > "$log" 2>&1
		code=$?
		set -e
		if [ "$code" -ne 0 ] && [ "$code" -ne 2 ]; then
			cat "$log" >&2
			echo "FAIL: roc build for $game --opt=$opt exited with $code" >&2
			exit 1
		fi
		set +e
		(cd "examples/$game" && ROCCO_EXIT_AFTER_FRAMES=$FRAMES ROCCO_ALLOC_REPORT=1 ${RUN_PREFIX:-} "$bin") > "$log" 2>&1
		code=$?
		set -e
		if [ "$code" -ne 0 ]; then
			tail -20 "$log" >&2
			echo "FAIL: $game --opt=$opt exited with $code" >&2
			failed=1
			continue
		fi
		# Fields: alloc step=N allocs=N deallocs=N reallocs=N live=N step_us=F view_us=F
		if awk -v skip=$SKIP -v want="$want" -v want_re="$want_re" '
			$1 != "alloc" { next }
			{ for (i = 2; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] } }
			v["step"] <= skip { next }
			{
				checked++
				if (live == "") live = v["live"]
				if (v["allocs"] != want || v["deallocs"] != want || v["reallocs"] != want_re || v["live"] != live) {
					if (++bad <= 5) print "step " v["step"] ": allocs=" v["allocs"] " deallocs=" v["deallocs"] " reallocs=" v["reallocs"] " live=" v["live"] ", expected " want " " want " " want_re " " live > "/dev/stderr"
				}
				step_us += v["step_us"]; view_us += v["view_us"]
			}
			END {
				if (checked == 0) { print "no steps after the first " skip > "/dev/stderr"; exit 1 }
				printf "%d steps, live=%s, mean step %.1f us, mean view %.1f us\n", checked, live, step_us / checked, view_us / checked
				exit bad > 0
			}
		' "$log"; then
			echo "PASS: $game --opt=$opt"
		else
			echo "FAIL: $game --opt=$opt. Each extra alloc and dealloc pair is usually a held or pressed key: keep your hands off the game window." >&2
			failed=1
		fi
	done
done

exit $failed
