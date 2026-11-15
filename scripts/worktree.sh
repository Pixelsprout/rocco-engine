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

# Stops setup when a submodule is missing or empty. git submodule update can
# exit 0 and still leave an empty folder, and the build fails much later.
submodule_problems() {
	git submodule status | while read -r line; do
		path=$(echo "$line" | awk '{print $2}')
		case "$line" in
		-*) echo "  $path is not cloned." ;;
		*) [ -n "$(ls -A "$path" 2>/dev/null | grep -vx .git)" ] || echo "  $path is empty. Run: git -C $path checkout -f HEAD -- ." ;;
		esac
	done
}

check_submodules() {
	problems=$(submodule_problems)
	if [ -n "$problems" ]; then
		echo "worktree.sh: the submodules are not ready:" >&2
		echo "$problems" >&2
		echo "If a clone failed, run git submodule update --init outside the sandbox." >&2
		exit 1
	fi
}

setup() {
	cd "$1"
	echo "== submodules in $1"
	echo "The clone can use SSH. If it seems stuck, approve the SSH key prompt (1Password)."
	git submodule update --init
	check_submodules
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
