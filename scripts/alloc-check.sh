#!/bin/sh
# Build each game under --opt=dev and --opt=speed, run it with no input and
# ROCCO_ALLOC_REPORT=1, and check every fixed step after the first 10:
# 2 allocs, 2 deallocs, 0 reallocs and a constant live block count.
# The host library must already be built for this machine. Each game opens a
# window. Do not type into it: a key press allocates the Input lists.
# RUN_PREFIX wraps each run, for example "xvfb-run -a" in the Linux image.
set -eu
cd "$(dirname "$0")/.."

FRAMES=240
SKIP=10
case "$(uname -s)" in
	Darwin) target=arm64mac; suffix=.bin ;;
	Linux) target=x64glibc; suffix=_linux.bin ;;
	*) echo "alloc-check: no rocco target for $(uname -s)" >&2; exit 2 ;;
esac

log=$(mktemp)
trap 'rm -f "$log"' EXIT
failed=0

for game in cards entity-game; do
	for opt in dev speed; do
		bin="./${game}_alloc_${opt}${suffix}"
		(cd "examples/$game" && roc build --target="$target" --opt="$opt" --output="$bin" main.roc > /dev/null)
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
		if awk -v skip=$SKIP '
			$1 != "alloc" { next }
			{ for (i = 2; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] } }
			v["step"] <= skip { next }
			{
				checked++
				if (live == "") live = v["live"]
				if (v["allocs"] != 2 || v["deallocs"] != 2 || v["reallocs"] != 0 || v["live"] != live) {
					if (++bad <= 5) print "step " v["step"] ": allocs=" v["allocs"] " deallocs=" v["deallocs"] " reallocs=" v["reallocs"] " live=" v["live"] ", expected 2 2 0 " live > "/dev/stderr"
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
			echo "FAIL: $game --opt=$opt" >&2
			failed=1
		fi
	done
done

exit $failed
