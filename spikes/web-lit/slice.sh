#!/bin/sh
# Copies the engine into a wasm32 slice at $1/engine. The slice leaves out
# the files that need an OS, a socket, audio or the game loop. It moves the
# ../ imports onto the rocco collection and reads files through webos.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
out=$1
mkdir -p "$out"
odin_root=$(odin root)

# core:image and core:image/png build their file loaders on every OS but js,
# and those import core:os. The slice copies both packages with the js files
# in their place, under names that build on every target.
mkdir -p "$out/image/png"
for path in "$odin_root"/core/image/*.odin "$odin_root"/core/image/png/*.odin; do
	case $path in
	*_os.odin | */example.odin) continue ;;
	esac
	sub=${path#"$odin_root"/core/image/}
	case $sub in
	*_js.odin) sub=${sub%_js.odin}_web.odin ;;
	esac
	sed -e 's#"core:image"#"slice:image"#' "$path" > "$out/image/$sub"
done

mkdir -p "$out/engine"
out=$out/engine
for path in "$root"/engine/*.odin; do
	file=$(basename "$path")
	case $file in
	*_test.odin | *_darwin.odin | *_linux.odin | *_windows.odin | capture_clock_other.odin) continue ;;
	app.odin | main.odin | host.odin | frame.odin | seam.odin | config.odin | run_mode.odin) continue ;;
	bridge*.odin | gamepad*.odin | audio.odin | miniaudio.odin | speaker.odin | voice.odin) continue ;;
	capture.odin | debug_camera.odin | exit_after_frames.odin | screenshot.odin) continue ;;
	input.odin | pointer.odin | key_tag.odin | key_tags.odin | shader_reload.odin) continue ;;
	esac
	# core:fmt has no eprint procedures on freestanding wasm, so the log
	# lines go to slice_eprint*. The slice builds without -vet, so an import
	# that the rename leaves unused is no error.
	sed -e 's#"\.\./#"rocco:#' \
		-e 's#^import "arenas"$#import "rocco:engine/arenas"#' \
		-e 's#^import "core:os"$#import os "spike:webos"#' \
		-e 's#"core:image/png"#"slice:image/png"#' \
		-e 's#fmt\.eprint#slice_eprint#g' \
		-e 's#fmt\.print#slice_print#g' \
		"$path" > "$out/$file"
done
cp "$here/slice/"*.odin "$out/"
