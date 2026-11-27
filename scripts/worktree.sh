#!/bin/sh
# Makes a git worktree ready to build and test, on macOS.
#
#   sh scripts/worktree.sh new <path> <branch> [<base>] [--task <id>]
#       Fetch origin, add a worktree on <base> (default origin/main), then set it up.
#       With --task, stop unless dex finds task <id> in the new worktree.
#   sh scripts/worktree.sh setup
#       Set up the worktree this script is in.
#
# A new worktree starts with empty submodules and no built archives. Fill the
# submodules with real clones. A symlink to another checkout's submodule makes
# git status fail with "expected submodule path ... not to be a symbolic link".
set -eu

usage() {
	echo "usage: sh scripts/worktree.sh new <path> <branch> [<base>] [--task <id>]" >&2
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

# A stale local main hides the tasks and commits that are on origin/main.
check_base_fresh() {
	git show-ref --verify --quiet "refs/heads/$1" || return 0
	upstream=$(git rev-parse --abbrev-ref --symbolic-full-name "$1@{upstream}" 2>/dev/null) || return 0
	behind=$(git rev-list --count "$1..$upstream")
	if [ "$behind" -gt 0 ]; then
		echo "worktree.sh: $1 is $behind commit(s) behind $upstream." >&2
		echo "Pull $1, or leave out <base> to use origin/main." >&2
		exit 1
	fi
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
	echo "worktree.sh: macOS only. See the Requirements table in CONTRIBUTING.md." >&2
	exit 2
}

case "${1:-}" in
new)
	shift
	task=
	set -- "$@" --end
	while [ "$1" != --end ]; do
		case "$1" in
		--task)
			[ "$2" != --end ] || usage
			task=$2
			shift 2
			;;
		-*) usage ;;
		*)
			set -- "$@" "$1"
			shift
			;;
		esac
	done
	shift
	[ $# -eq 2 ] || [ $# -eq 3 ] || usage
	path=$1
	branch=$2
	base=${3:-origin/main}
	if [ -n "$task" ] && ! command -v dex >/dev/null; then
		echo "worktree.sh: --task needs dex on PATH." >&2
		exit 1
	fi
	git fetch origin
	check_base_fresh "$base"
	# Without --no-track, a branch made from origin/main tracks main.
	git worktree add --no-track -b "$branch" "$path" "$base"
	if [ -n "$task" ] && ! (cd "$path" && dex show "$task" >/dev/null); then
		echo "worktree.sh: task $task is not on $base." >&2
		git worktree remove --force "$path"
		git branch -D "$branch" >/dev/null
		exit 1
	fi
	setup "$(cd "$path" && pwd)"
	;;
setup)
	setup "$(cd "$(dirname "$0")/.." && pwd)"
	;;
*) usage ;;
esac
