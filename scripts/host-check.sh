#!/bin/sh
# Check that the games do not rebuild the host library. Records the host
# library's hash and mtime and the generated glue's hash, regenerates the
# glue and links both games, then compares. A Model change in either game
# must pass this check, because the platform never names the game.
set -eu
cd "$(dirname "$0")/.."

case "$(uname -s)" in
	Darwin) lib=platform/targets/arm64mac/libhost.a ;;
	Linux) lib=platform/targets/x64glibc/libhost.a ;;
	*) echo "host-check: no rocco target for $(uname -s)" >&2; exit 2 ;;
esac
if [ ! -f "$lib" ]; then
	echo "host-check: $lib is missing. Run roc scripts/build.roc -- host first." >&2
	exit 2
fi

hash() { cksum < "$1"; }
mtime() { if [ "$(uname -s)" = Darwin ]; then stat -f %m "$1"; else stat -c %Y "$1"; fi; }

lib_hash=$(hash "$lib")
lib_mtime=$(mtime "$lib")
glue_hash=$(hash engine/roc_platform_abi.odin)

roc scripts/build.roc -- glue > /dev/null
roc scripts/build.roc -- game cards > /dev/null
roc scripts/build.roc -- game entity-game > /dev/null

failed=0
if [ "$(hash engine/roc_platform_abi.odin)" != "$glue_hash" ]; then
	echo "FAIL: the glue changed. The platform header is not the one the host was built from." >&2
	failed=1
fi
if [ "$(hash "$lib")" != "$lib_hash" ] || [ "$(mtime "$lib")" != "$lib_mtime" ]; then
	echo "FAIL: $lib changed while the games built." >&2
	failed=1
fi
if [ "$failed" -eq 0 ]; then
	echo "PASS: $lib and the glue did not change while both games built"
fi
exit $failed
