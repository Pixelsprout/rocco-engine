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

headless_games="model-size model-size-tuned model-size-twin empty-step colliders colliders-twin"
windowed_games="draws ui mixed"
# Keep equal to sweep_ns in scripts/build.roc.
full_ns="64 128 256 512 1024 2048 4096 8192 16384"
real_clock_game=entity-game
# 120 warmup Frames and 2,000 measured Frames, as in a bench process.
real_clock_frames=2120

ns=${REFERENCE_NS:-$full_ns}

if ! python3 bench/machine.py --check; then
	if [ "${REFERENCE_FORCE:-0}" != 1 ]; then
		echo "reference-run: the machine is not ready. See docs/BENCHMARKS.md, \"Reference run\"." >&2
		exit 1
	fi
	echo "reference-run: REFERENCE_FORCE=1, so the run starts anyway." >&2
fi

slug=$(python3 -c 'import sys; sys.path.insert(0, "bench"); import datetime, machine; m = machine.machine(datetime.date.today()); print(m["date"] + "-" + m["slug"])')
results="bench/results/$slug"
if [ -e "$results" ]; then
	echo "reference-run: $results already exists. Move or delete it first." >&2
	exit 1
fi
mkdir -p bench/results
before=$(ls bench/results)

sweep() {
	game=$1
	shift
	if [ -z "${REFERENCE_NS:-}" ]; then
		roc scripts/build.roc bench "$game" "$@"
	else
		for n in $ns; do
			roc scripts/build.roc bench "$game" "$n" "$@"
		done
	fi
}

for game in $headless_games; do
	sweep "$game"
done
for game in $windowed_games; do
	sweep "$game" --windowed
done

# bench writes to the directory of the day each sweep starts. Write every
# summary again into $results, so a run past midnight stays in one directory.
runs=""
for game in $headless_games $windowed_games; do
	for n in $ns; do
		runs="$runs bench/out/$game/$game-$n.run.json"
	done
done
# shellcheck disable=SC2086
python3 bench/analyse.py $runs --out-dir "$results"
for dir in bench/results/*; do
	name=$(basename "$dir")
	if [ "$dir" != "$results" ] && ! echo "$before" | grep -qx "$name"; then
		rm -r "$dir"
	fi
done

roc scripts/build.roc host --release --spans
roc scripts/build.roc inputs --release
roc scripts/build.roc game "$real_clock_game"
csv="$PWD/bench/out/real-clock/$real_clock_game.csv"
mkdir -p "$(dirname "$csv")"
(cd "examples/$real_clock_game" && ROCCO_EXIT_AFTER_FRAMES=$real_clock_frames ROCCO_SPANS_CSV="$csv" "./$real_clock_game.bin")
python3 bench/realclock.py "$csv" --game "$real_clock_game" --out "$results/real-clock/$real_clock_game.json"

python3 bench/chart.py "$results"
for comparison in twin tuned colliders; do
	python3 bench/compare_chart.py "$comparison" "$results"
done
python3 bench/headline.py "$results" | tee "$results/headline.txt"

# A Spans host stops every run without ROCCO_SPANS_CSV, so put the debug host back.
roc scripts/build.roc all

echo "reference-run: the summaries are in $results and the charts in bench/out/charts/."
