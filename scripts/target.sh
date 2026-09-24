# Sourced by the check scripts. Sets the Roc target, the game binary suffix
# and the host library for the machine, as scripts/build.roc names them.
case "$(uname -s)" in
	Darwin) target=arm64mac; suffix=.bin; host_lib=platform/targets/arm64mac/libhost.a ;;
	Linux) target=x64glibc; suffix=_linux.bin; host_lib=platform/targets/x64glibc/libhost.a ;;
	*) echo "$(basename "$0"): no rocco target for $(uname -s)" >&2; exit 2 ;;
esac
