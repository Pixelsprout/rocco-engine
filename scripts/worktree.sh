#!/bin/sh
# Makes a git worktree ready to build and test, on macOS.
#
#   sh scripts/worktree.sh new <path> <branch> [<base>]   Add a worktree, then set it up.
#   sh scripts/worktree.sh setup                          Set up the worktree this script is in.
#
# A new worktree starts with empty submodules and no built archives. Fill the
# submodules with real clones. A symlink to another checkout's submodule makes
# git status fail with "expected submodule path ... not to be a symbolic link".
set -eu

usage() {
	echo "usage: sh scripts/worktree.sh new <path> <branch> [<base>]" >&2
	echo "       sh scripts/worktree.sh setup" >&2
	exit 2
}

setup() {
	cd "$1"
	echo "== submodules in $1"
	git submodule update --init
	sh scripts/macos/build-sokol.sh
	sh scripts/macos/build-miniaudio.sh
	sh scripts/toolchain.sh run roc scripts/build.roc inputs
	sh scripts/toolchain.sh check || true
	echo "== ready: $1"
	echo "Next: sh scripts/toolchain.sh run roc scripts/build.roc host"
}

[ "$(uname -s)" = Darwin ] || {
	echo "worktree.sh: macOS only. See the Requirements table in README.md." >&2
	exit 2
}

case "${1:-}" in
new)
	[ $# -ge 3 ] || usage
	path=$2
	branch=$3
	base=${4:-HEAD}
	git worktree add -b "$branch" "$path" "$base"
	setup "$(cd "$path" && pwd)"
	;;
setup)
	setup "$(cd "$(dirname "$0")/.." && pwd)"
	;;
*) usage ;;
esac
