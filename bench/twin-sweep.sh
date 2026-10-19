#!/bin/sh
# Runs the Roc bench game, its Odin twin and the empty step through the bench
# protocol, then draws bench/out/twin.svg from the latest results. With no
# arguments each game runs the full sweep. Given N values, each game runs the
# protocol at each N alone.
set -eu
cd "$(dirname "$0")/.."

for game in model-size model-size-twin empty-step; do
	if [ "$#" -eq 0 ]; then
		roc scripts/build.roc bench "$game"
	else
		for n in "$@"; do
			roc scripts/build.roc bench "$game" "$n"
		done
	fi
done
python3 bench/twin_chart.py
