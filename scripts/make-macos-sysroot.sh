#!/bin/sh
# Build the sysroot that Roc's linker reads to add -framework flags.
#
# Usage: make-macos-sysroot.sh <platform-dir>/targets/macos-sysroot
#
# Two things here are not obvious and both are load-bearing.
#
# 1. Roc does not pass -syslibroot to ld64.lld, so an absolute re-export path
#    inside a .tbd resolves against the real filesystem, where the dylib does
#    not exist. Every re-export is stripped, and the frameworks that were
#    re-exported are linked directly instead. That is what the closure below is.
# 2. Roc's discovery only emits -framework, never -l, so libobjc is presented
#    as objc.framework. Its install name still says /usr/lib/libobjc.A.dylib,
#    which is what the loader records at runtime.
#
# Regenerate after an Xcode update. The output is derived from the installed
# SDK and must not be committed.
set -eu

OUT=${1:?usage: make-macos-sysroot.sh <path-to-macos-sysroot>}
SDK=$(xcrun --show-sdk-path)
FW=$SDK/System/Library/Frameworks

# Frameworks the engine names, before re-exports are followed.
SEED="AppKit Cocoa CoreFoundation CoreGraphics Foundation Metal QuartzCore"

# Follow re-exports until the set stops growing. Linking a framework that is
# only there to satisfy a re-export costs nothing.
closure=$SEED
while :; do
	grown=$closure
	for f in $closure; do
		[ -f "$FW/$f.framework/$f.tbd" ] || continue
		found=$(awk '
			/^reexported-libraries:/         { inblock = 1; next }
			inblock && /^[ \t]/             { print; next }
			                                 { inblock = 0 }
		' "$FW/$f.framework/$f.tbd" |
			sed -n "s|.*/System/Library/Frameworks/\([A-Za-z0-9_+]*\)\.framework/.*|\1|p" |
			sort -u)
		for n in $found; do
			case " $grown " in *" $n "*) ;; *) grown="$grown $n" ;; esac
		done
	done
	[ "$grown" = "$closure" ] && break
	closure=$grown
done

rm -rf "$OUT"
mkdir -p "$OUT/usr/lib"
cp "$SDK/usr/lib/libSystem.tbd" "$OUT/usr/lib/"

strip_reexports() {
	# A .tbd can hold several YAML documents, so the block ends at the first
	# line that is not indented -- not at the next top-level key.
	awk '
		/^reexported-libraries:/                { skip = 1; next }
		skip && (/^[ \t]/ || /^[ \t]*$/)      { next }
		                                        { skip = 0; print }
	' "$1" > "$2"
}

count=0
for f in $closure; do
	[ -f "$FW/$f.framework/$f.tbd" ] || { echo "skip $f: no stub in SDK" >&2; continue; }
	mkdir -p "$OUT/System/Library/Frameworks/$f.framework"
	strip_reexports "$FW/$f.framework/$f.tbd" "$OUT/System/Library/Frameworks/$f.framework/$f.tbd"
	count=$((count + 1))
done

mkdir -p "$OUT/System/Library/Frameworks/objc.framework"
strip_reexports "$SDK/usr/lib/libobjc.tbd" "$OUT/System/Library/Frameworks/objc.framework/objc.tbd"
count=$((count + 1))

echo "$OUT: $count frameworks"
echo "$closure objc" | tr ' ' '\n' | sort | tr '\n' ' '
echo
