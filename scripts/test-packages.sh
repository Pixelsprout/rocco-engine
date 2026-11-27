#!/bin/sh
# Type-checks and tests each package. CI runs it in the Linux image, and
# pre-push runs it when a file under packages/ changes.
set -eu
cd "$(dirname "$0")/.."

# TextCorpus.roc is not exposed from packages/ui/main.roc, so roc test on the
# package skips its expects.
for file in packages/*/main.roc packages/ui/TextCorpus.roc; do
	echo "== roc check $file"
	roc check "$file"
	echo "== roc test $file"
	roc test "$file"
done
