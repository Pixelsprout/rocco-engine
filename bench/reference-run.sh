#!/bin/sh
# Runs the reference run of docs/BENCHMARKS.md: the sweep of every bench game
# and Odin twin, then one real-clock run of entity-game. Then it draws the
# charts and prints the headline figure.
#
# The summaries go to a new bench/results/<date>-<machine>/, dated on the day
# the run starts. The script stops if that directory already exists.
#
# REFERENCE_NS="64 128" runs only those N, to check the script. Such a run is
# not a reference run. Delete its directory after the check.
# REFERENCE_FORCE=1 starts the run although bench/machine.py --check fails.
set -eu
cd "$(dirname "$0")/.."

# One bench command per list runs its games and N in one shuffled order.
headless_games="model-size,model-size-tuned,model-size-twin,empty-step,colliders,colliders-twin"
windowed_games="draws,ui,mixed"
# Keep equal to sweep_ns in scripts/build.roc.
full_ns="64 128 256 512 1024 2048 4096 8192 16384"
real_clock_game=entity-game
# 120 warmup Frames and 2,000 measured Frames, as in a bench process.
real_clock_frames=2120

ns=${REFERENCE_NS:-$full_ns}

# On Windows, python3 is often the Microsoft Store alias, which runs nothing.
# The python.org installer puts python on PATH instead.
if python3 -c '' 2>/dev/null; then
	python=python3
else
	python=python
fi

# The game executable suffix and a path the game can open, as scripts/build.roc
# names them. Git Bash gives a POSIX path from pwd, and pwd -W gives the
# Windows path.
case $(uname -s) in
MINGW* | MSYS* | CYGWIN*)
	exe=.exe
	root=$(pwd -W)
	;;
Linux)
	exe=_linux.bin
	root=$PWD
	;;
*)
	exe=.bin
	root=$PWD
	;;
esac

if ! $python bench/machine.py --check; then
	if [ "${REFERENCE_FORCE:-0}" != 1 ]; then
		echo "reference-run: the machine is not ready. See docs/BENCHMARKS.md, \"Reference run\"." >&2
		exit 1
	fi
	echo "reference-run: REFERENCE_FORCE=1, so the run starts anyway." >&2
fi

slug=$($python -c 'import sys; sys.path.insert(0, "bench"); import datetime, machine; m = machine.machine(datetime.date.today()); print(m["date"] + "-" + m["slug"])')
results="bench/results/$slug"
if [ -e "$results" ]; then
	echo "reference-run: $results already exists. Move or delete it first." >&2
	exit 1
fi

# shellcheck disable=SC2086
roc scripts/build.roc bench "$headless_games" ${REFERENCE_NS:-}
# shellcheck disable=SC2086
roc scripts/build.roc bench "$windowed_games" ${REFERENCE_NS:-} --windowed

# bench writes its summaries to bench/out/results/. Write every summary again
# into $results, the committed directory of the day the run started.
runs=""
for game in $(echo "$headless_games,$windowed_games" | tr , ' '); do
	for n in $ns; do
		runs="$runs bench/out/$game/$game-$n.run.json"
	done
done
# shellcheck disable=SC2086
$python bench/analyse.py $runs --out-dir "$results"

roc scripts/build.roc host --release --spans
roc scripts/build.roc inputs --release
roc scripts/build.roc game "$real_clock_game"
csv="$root/bench/out/real-clock/$real_clock_game.csv"
mkdir -p "$(dirname "$csv")"
(cd "examples/$real_clock_game" && ROCCO_EXIT_AFTER_FRAMES=$real_clock_frames ROCCO_SPANS_CSV="$csv" "./$real_clock_game$exe")
$python bench/realclock.py "$csv" --game "$real_clock_game" --out "$results/real-clock/$real_clock_game.json"

$python bench/chart.py "$results"
for comparison in twin tuned colliders; do
	$python bench/compare_chart.py "$comparison" "$results"
done
$python bench/headline.py "$results" | tee "$results/headline.txt"

# A Spans host stops every run without ROCCO_SPANS_CSV and ROCCO_EXIT_AFTER_FRAMES,
# so put the debug host back.
roc scripts/build.roc all

echo "reference-run: the summaries are in $results and the charts in bench/out/charts/."
