#!/bin/sh
# Build each game under --opt=dev and --opt=speed, run it with no input and
# ROCCO_ALLOC_REPORT=1, and check every fixed step after the first 10: the
# game's expected allocs and as many deallocs, its expected reallocs and a
# constant live block count. Each count records what the game makes today.
# None is a target: a change that moves a count updates it here.
# Each entry is game:dev allocs:speed allocs:reallocs.
# cards expects 2 allocs and 1 realloc: the box shell and the cards list,
# which the concat after the Lights grows.
# entity-game expects 33 allocs and 4 reallocs under --opt=speed. view makes
# one list for the leaves of each entity, and List.keep_if makes one list for
# each root it keeps. Under --opt=dev, List.map copies the entity list in each
# of the 9 stages that map it, so it expects 42. With no input the player
# carries no drops, so it is no Group.
# pong expects 6 allocs and 1 realloc: the box shell, the nodes list, the ui
# list, the scoreboard's children and its two cells' children. The realloc
# is the concat that joins the scoreboard, the banner and the hints.
# tutorial/10-animation expects 14 allocs and 6 reallocs: its view builds the
# Nodes, the pickup Draws and Colliders, the HUD with its count text and the
# Loops, and each concat grows a list.
# The script rebuilds the host library with the host tracking allocator, and
# fails on a LEAK or BAD Free line in its report. It leaves that host library
# in place. The sokol and Clay inputs must
# already be in place for this machine. Each game opens a window. Do not type
# into it: a key press allocates the Input lists. A connected gamepad also
# allocates them, so the runs set ROCCO_NO_GAMEPADS=1.
# RUN_PREFIX wraps each run, for example "xvfb-run -a" in the Linux image.
set -eu
cd "$(dirname "$0")/.."

FRAMES=240
SKIP=10
# eval "$(...)" would hide a build.roc failure from set -e.
target_lines=$(roc scripts/build.roc -- target)
eval "$target_lines"

roc scripts/build.roc -- host --release --track-alloc

log=$(mktemp)
trap 'rm -f "$log"' EXIT
failed=0

for entry in cards:2:2:1 entity-game:42:33:4 pong:6:6:1 tutorial/10-animation:14:14:6; do
	game=${entry%%:*}
	rest=${entry#*:}
	want_dev=${rest%%:*}
	rest=${rest#*:}
	want_speed=${rest%%:*}
	want_re=${rest##*:}
	for opt in dev speed; do
		if [ "$opt" = dev ]; then want=$want_dev; else want=$want_speed; fi
		# tutorial/10-animation builds 10-animation_alloc_dev.
		bin="./${game##*/}_alloc_${opt}${suffix}"
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
		(cd "examples/$game" && ROCCO_EXIT_AFTER_FRAMES=$FRAMES ROCCO_ALLOC_REPORT=1 ROCCO_NO_GAMEPADS=1 ${RUN_PREFIX:-} "$bin") > "$log" 2>&1
		code=$?
		set -e
		if [ "$code" -ne 0 ]; then
			tail -20 "$log" >&2
			echo "FAIL: $game --opt=$opt exited with $code" >&2
			failed=1
			continue
		fi
		if grep -E '^(LEAK|BAD Free)' "$log" >&2; then
			echo "FAIL: $game --opt=$opt has a host leak or bad free" >&2
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
