#!/bin/sh
# Runs the draws bench game in windowed Lockstep at each N, writes a summary per
# run and draws bench/out/draws.svg. One process per configuration, in a fixed
# order: the full protocol replaces this sweep when it lands.
set -eu
cd "$(dirname "$0")/.."

ns=${*:-64 128 256 512 1024 2048 4096 8192 16384}
for n in $ns; do
	roc scripts/build.roc bench draws "$n" --windowed
	python3 bench/analyse.py "bench/out/draws-$n.csv"
done
python3 bench/draws_chart.py bench/out
