#!/bin/sh
# Runs the Roc bench game, its Odin twin and the empty step at each N, writes a
# summary per run and draws bench/out/twin.svg. One process per configuration,
# in a fixed order: the full protocol replaces this sweep when it lands.
set -eu
cd "$(dirname "$0")/.."

ns=${*:-64 128 256 512 1024 2048 4096 8192 16384}
for n in $ns; do
	for game in model-size model-size-twin empty-step; do
		roc scripts/build.roc bench "$game" "$n"
		python3 bench/analyse.py "bench/out/$game-$n.csv"
	done
done
python3 bench/twin_chart.py bench/out
