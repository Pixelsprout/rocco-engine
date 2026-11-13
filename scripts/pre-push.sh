#!/bin/sh
# Runs the checks that catch CI failures before a push.
# .githooks/pre-push calls it with --hook and git's ref lines on stdin.
#
#   sh scripts/pre-push.sh           Check the changes since origin/main.
#   sh scripts/pre-push.sh <base>    Check the changes since <base>.
#
# The checks read the working tree, not the pushed commits.
# Skip them once with git push --no-verify.
set -eu
cd "$(dirname "$0")/.."

# The pinned compilers go first on PATH when they are installed.
PATH=$(sh scripts/toolchain.sh path 2>/dev/null || true):$PATH
export PATH
sh scripts/toolchain.sh check >/dev/null 2>&1 ||
	echo "pre-push: odin or roc differs from the CI pins. Run: sh scripts/toolchain.sh check" >&2

zero=0000000000000000000000000000000000000000
changed=$(mktemp)
trap 'rm -f "$changed"' EXIT

if [ "${1:-}" = --hook ]; then
	while read -r _ local_sha _ remote_sha; do
		[ "$local_sha" != "$zero" ] || continue
		if [ "$remote_sha" = "$zero" ]; then
			base=$(git merge-base origin/main "$local_sha" 2>/dev/null || echo "")
		else
			base=$remote_sha
		fi
		if [ -n "$base" ] && git cat-file -e "$base" 2>/dev/null; then
			git diff --name-only "$base" "$local_sha" >>"$changed"
		else
			git ls-files >>"$changed"
		fi
	done
else
	git diff --name-only "${1:-origin/main}...HEAD" >>"$changed"
fi

touches() {
	grep -Eq "$1" "$changed"
}

if touches '\.odin$'; then
	# A file such as platform_linux.odin compiles only for its own OS, so check
	# every package for every CI target.
	for package in $(git ls-files '*.odin' | sed 's|/[^/]*$||' | sort -u); do
		targets="darwin_arm64 linux_amd64 windows_amd64"
		defines=
		case "$package" in
		# font_bake is a local tool. It links vendor:stb, which the Odin
		# release ships prebuilt only for the OS it runs on.
		scripts/font_bake) targets=native ;;
		# The fixture is Windows only, and engine.g_gpu_timing exists only with
		# this define. CI builds it the same way.
		scripts/gpu-timing-check)
			targets=windows_amd64
			defines=-define:ROCCO_D3D_GPU_TIMING=true
			;;
		# The web host assumes 32-bit Roc layouts.
		spikes/web-link/host | spikes/web-arenas/host) targets=freestanding_wasm32 ;;
		# Only build.sh adds the generated ABI file. The CI web job builds it.
		spikes/web-pong/host) targets= ;;
		# These packages compile only inside the engine slice that
		# spikes/web-ui/build.sh writes. The CI web job builds it.
		spikes/web-ui/*) targets= ;;
		# These name the engine through the slice collection, which
		# spikes/web-lit/build.sh sets. The CI web job builds the page.
		spikes/web-lit/*) targets= ;;
		# wasm32 builds take the heap arenas, so check that target too.
		engine/arenas) targets="$targets freestanding_wasm32" ;;
		esac
		for target in $targets; do
			if [ "$target" = native ]; then
				echo "== odin check $package"
				odin check "$package" -no-entry-point -vet -strict-style $defines
				continue
			fi
			echo "== odin check $package -target:$target${defines:+ $defines}"
			odin check "$package" -no-entry-point -vet -strict-style $defines -target:"$target"
		done
	done
fi

# Games link against the committed macOS sysroot, which lacks some libc
# symbols, such as snprintf. CI builds every archive fresh. A local archive
# built before its sources changed can hide a link error, so rebuild it.
if [ "$(uname -s)" = Darwin ] &&
	touches '^(engine/|platform/|glue|sokol-odin|miniaudio|clay|scripts/(macos|miniaudio)/|scripts/build\.roc)'; then
	if touches '^(sokol-odin|miniaudio|scripts/(macos|miniaudio)/)'; then
		sh scripts/macos/build-sokol.sh
		sh scripts/macos/build-miniaudio.sh
	fi
	roc scripts/build.roc host
	roc scripts/build.roc inputs
	roc scripts/build.roc game tutorial/01-window || {
		echo "pre-push: the game link failed. CI's macOS job fails the same way." >&2
		exit 1
	}
fi

echo "pre-push: checks passed"
