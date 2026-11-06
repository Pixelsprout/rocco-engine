#!/bin/sh
# Pins the Odin and Roc that CI uses on this machine.
# scripts/linux/Dockerfile holds the one copy of the pins.
#
#   sh scripts/toolchain.sh check          Compare odin and roc on PATH with the pins.
#   sh scripts/toolchain.sh install        Download the pinned releases into ~/tools.
#   sh scripts/toolchain.sh path           Print the two pinned directories, PATH style.
#   sh scripts/toolchain.sh run <cmd...>   Run a command with the pinned compilers first on PATH.
#
# A local source build of Odin can carry the same dev-2026-08 tag and still
# differ from the release archive CI downloads. check compares the commit.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
tools=${ROCCO_TOOLS:-$HOME/tools}

pin() {
	sed -n "s/^ARG $1=//p" "$root/scripts/linux/Dockerfile"
}

odin_release=$(pin ODIN_RELEASE)
roc_nightly=$(pin ROC_NIGHTLY)

case "$(uname -s)-$(uname -m)" in
Darwin-arm64)
	odin_asset=odin-macos-arm64-$odin_release
	roc_asset=roc_nightly-macos_apple_silicon-$roc_nightly
	;;
Linux-x86_64)
	odin_asset=odin-linux-amd64-$odin_release
	roc_asset=roc_nightly-linux_x86_64-$roc_nightly
	;;
*)
	echo "toolchain.sh: no pinned download for $(uname -s)-$(uname -m). See README.md." >&2
	exit 2
	;;
esac

odin_dir=$tools/$odin_asset
roc_dir=$tools/$roc_asset

# The release archive is the only place the pinned Odin commit is written down.
odin_commit() {
	"$odin_dir/odin" version | sed -n 's/.*:\([0-9a-f]*\)$/\1/p'
}

download() {
	url=$1
	dir=$2
	tmp=$dir.partial
	rm -rf "$tmp"
	mkdir -p "$tmp"
	echo "== $url"
	curl -fsSL "$url" | tar xz -C "$tmp" --strip-components=1
	mv "$tmp" "$dir"
}

install() {
	mkdir -p "$tools"
	[ -x "$odin_dir/odin" ] ||
		download "https://github.com/odin-lang/Odin/releases/download/$odin_release/$odin_asset.tar.gz" "$odin_dir"
	[ -x "$roc_dir/roc" ] ||
		download "https://github.com/roc-lang/nightlies/releases/download/nightly-$roc_nightly/$roc_asset.tar.gz" "$roc_dir"
	"$odin_dir/odin" version
	"$roc_dir/roc" version
}

check() {
	status=0
	if [ ! -x "$odin_dir/odin" ] || [ ! -x "$roc_dir/roc" ]; then
		echo "toolchain.sh: the pinned compilers are not installed. Run: sh scripts/toolchain.sh install" >&2
		return 1
	fi
	want_odin=$(odin_commit)
	have_odin=$(odin version 2>/dev/null || echo "odin: not on PATH")
	case "$have_odin" in
	*"$want_odin") echo "odin ok: $have_odin" ;;
	*)
		echo "odin MISMATCH: PATH has '$have_odin', CI uses $odin_release ($want_odin)" >&2
		status=1
		;;
	esac
	have_roc=$(roc version 2>/dev/null || echo "roc: not on PATH")
	case "$have_roc" in
	*"$roc_nightly"*) echo "roc ok: $have_roc" ;;
	*)
		echo "roc MISMATCH: PATH has '$have_roc', CI uses nightly-$roc_nightly" >&2
		status=1
		;;
	esac
	if [ "$status" -ne 0 ]; then
		echo "Prefix commands with: sh scripts/toolchain.sh run" >&2
		echo "Or put these first on PATH: $odin_dir:$roc_dir" >&2
	fi
	return "$status"
}

cmd=${1:-check}
[ $# -eq 0 ] || shift
case "$cmd" in
check) check ;;
install) install ;;
path) echo "$odin_dir:$roc_dir" ;;
run)
	[ $# -gt 0 ] || { echo "usage: sh scripts/toolchain.sh run <command...>" >&2; exit 2; }
	PATH=$odin_dir:$roc_dir:$PATH
	export PATH
	exec "$@"
	;;
*)
	echo "usage: sh scripts/toolchain.sh [check|install|path|run <command...>]" >&2
	exit 2
	;;
esac
