app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.23.0/GNN5tt2gKdX4dhawg4915C4YB193woHFdcCkz31fhGxv.tar.zst", roc: "nightly-2026-09-27-a3ce7f1" }

import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Path
import pf.Stderr
import pf.Stdout
import Keys

Mode : [Debug, Release]

Step : [Inputs(Mode), Glue, Host(Mode), Game(Str), Shaders, Font, Keys, Target]

parse : List(Str) -> Try(List(Step), [Usage])
parse = |args| match args {
	["inputs"] => Ok([Inputs(Debug)])
	["inputs", "--release"] => Ok([Inputs(Release)])
	["glue"] => Ok([Glue])
	["host"] => Ok([Host(Debug)])
	["host", "--release"] => Ok([Host(Release)])
	["game", name] => Ok([Game(name)])
	["shaders"] => Ok([Shaders])
	["font"] => Ok([Font])
	["keys"] => Ok([Keys])
	["target"] => Ok([Target])
	["all"] => Ok(all_steps(Debug))
	["all", "--release"] => Ok(all_steps(Release))
	_ => Err(Usage)
}

all_steps : Mode -> List(Step)
all_steps = |mode| [Glue, Host(mode), Inputs(mode), Game("cards"), Game("entity-game"), Game("pong"), Game("kula")]

mode_name : Mode -> Str
mode_name = |mode| match mode {
	Debug => "debug"
	Release => "release"
}

# extra_inputs names what inputs copies besides the sokol and Clay archives.
Target : {
	roc_target : Str,
	dir : Str,
	host_lib : Str,
	sokol_platform : Str,
	lib_ext : Str,
	exe : Str,
	extra_inputs : [MacSdk, WindowsSdk, LinuxSystem],
}

Machine : { arch : [X86, X64, ARM, AARCH64, OTHER(Str)], os : [LINUX, MACOS, WINDOWS, OTHER(Str)] }

target_for : Machine -> Try(Target, [UnsupportedMachine])
target_for = |machine| match (machine.os, machine.arch) {
	(MACOS, AARCH64) => Ok(make_target("arm64mac", "libhost.a", "macos_arm64_metal", ".a", ".bin", MacSdk))
	(LINUX, X64) => Ok(make_target("x64glibc", "libhost.a", "linux_x64_gl", ".a", "_linux.bin", LinuxSystem))
	(WINDOWS, X64) => Ok(make_target("x64win", "host.lib", "windows_x64_d3d11", ".lib", ".exe", WindowsSdk))
	_ => Err(UnsupportedMachine)
}

make_target : Str, Str, Str, Str, Str, [MacSdk, WindowsSdk, LinuxSystem] -> Target
make_target = |roc_target, host_lib, sokol_platform, lib_ext, exe, extra_inputs| {
	roc_target,
	dir: "platform/targets/${roc_target}",
	host_lib,
	sokol_platform,
	lib_ext,
	exe,
	extra_inputs,
}

# The check scripts eval these lines, so they must stay shell-safe.
target_lines : Target -> Str
target_lines = |target| "target=${target.roc_target}\nsuffix=${target.exe}\nhost_lib=${target.dir}/${target.host_lib}"

Run : { program : Str, args : List(Str), cwd : Str }

# The glue cache can return the output of an older glue/OdinGlue.roc.
glue_run : Run
glue_run = { program: "roc", args: ["glue", "--no-cache", "glue/OdinGlue.roc", "./engine", "platform/main.roc"], cwd: "." }

host_run : Target, Mode -> Run
host_run = |target, mode| {
	opt = match mode {
		Debug => []
		Release => ["-o:speed"]
	}
	{
		program: "odin",
		args: ["build", "engine", "-build-mode:static", "-out:${target.dir}/${target.host_lib}"].concat(opt).concat(["-debug", "-vet", "-strict-style"]),
		cwd: ".",
	}
}

# A game under games/ wins over an example of the same name.
game_dirs : Str -> List(Str)
game_dirs = |name| ["games/${name}", "examples/${name}"]

game_run : Target, Str, Str -> Run
game_run = |target, dir, name| {
	program: "roc",
	args: ["build", "--target=${target.roc_target}", "--output=./${name}${target.exe}", "main.roc"],
	cwd: dir,
}

shaders_run : Run
shaders_run = {
	program: "sokol-shdc",
	args: ["-i", "engine/shaders/basic.glsl", "-o", "engine/shader_basic.odin", "-l", "metal_macos:glsl430:hlsl5", "-f", "sokol_odin"],
	cwd: ".",
}

# The tool binary goes in build/ so it stays out of the checkout.
font_run : Run
font_run = {
	program: "odin",
	args: ["run", "scripts/font_bake", "-out:build/font_bake", "--", "scripts/fonts/AtkinsonHyperlegible-Regular.ttf", "engine/font_baked.odin"],
	cwd: ".",
}

Copy : { from : Str, to : Str }

# platform/main.roc names sokol_<part><ext>, so the copy drops the mode.
sokol_copies : Target, Mode -> List(Copy)
sokol_copies = |target, mode| ["app", "gfx", "glue", "log"].map(
	|part| {
		built = "sokol_${part}_${target.sokol_platform}_${mode_name(mode)}${target.lib_ext}"
		{ from: "sokol-odin/sokol/${part}/${built}", to: "${target.dir}/sokol_${part}${target.lib_ext}" }
	},
)

clay_odin_dir : Str
clay_odin_dir = "clay/bindings/odin/clay-odin"

# Clay ships one prebuilt archive per OS beside its Odin bindings. x64win does not link Clay yet.
clay_copies : Target -> List(Copy)
clay_copies = |target| match target.extra_inputs {
	MacSdk => [clay_copy("macos-arm64", target)]
	LinuxSystem => [clay_copy("linux", target)]
	WindowsSdk => []
}

clay_copy : Str, Target -> Copy
clay_copy = |os_dir, target| { from: "${clay_odin_dir}/${os_dir}/clay.a", to: "${target.dir}/clay.a" }

compiler_rt_copy : Str, Target -> Copy
compiler_rt_copy = |resource_dir, target| {
	from: "${resource_dir}/lib/darwin/libclang_rt.osx.a",
	to: "${target.dir}/libclang_rt.osx.a",
}

windows_sdk_libs : List(Str)
windows_sdk_libs = ["kernel32.lib", "user32.lib", "gdi32.lib", "shell32.lib", "ole32.lib", "d3d11.lib", "dxgi.lib"]

windows_sdk_copies : Str, Target -> List(Copy)
windows_sdk_copies = |sdk_dir, target| windows_sdk_libs.map(|lib| { from: "${sdk_dir}/um/x64/${lib}", to: "${target.dir}/${lib}" })

# Debian and Ubuntu, then Fedora, then Arch. Each keeps Scrt1.o, the CRT
# objects and the shared libraries in one directory.
linux_lib_dirs : List(Str)
linux_lib_dirs = ["/usr/lib/x86_64-linux-gnu", "/usr/lib64", "/usr/lib"]

# found holds the candidates that contain Scrt1.o. The first in linux_lib_dirs wins.
linux_lib_dir_from : List(Str) -> Try(Str, [NoLibDir])
linux_lib_dir_from = |found| match linux_lib_dirs.keep_if(|dir| found.contains(dir)).first() {
	Ok(dir) => Ok(dir)
	Err(_) => Err(NoLibDir)
}

# lld records the soname as DT_NEEDED, so copy the versioned files, not the dev symlinks.
linux_libs : List(Str)
linux_libs = ["Scrt1.o", "crti.o", "crtn.o", "libc.so.6", "libm.so.6", "libX11.so.6", "libXi.so.6", "libXcursor.so.1", "libGL.so.1"]

linux_copies : Str, Target -> List(Copy)
linux_copies = |lib_dir, target| linux_libs.map(|lib| { from: "${lib_dir}/${lib}", to: "${target.dir}/${lib}" })

# Same rule as basic-cli's find_windows_sdk_lib_dir: the highest version wins.
newest_sdk : List(Str) -> Try(Str, [NoSdk])
newest_sdk = |names| {
	best : Try((U64, Str), [NoSdk])
	best = names.fold(
		Err(NoSdk),
		|acc, name| match (version_key(name), acc) {
			(Err(_), _) => acc
			(Ok(key), Err(_)) => Ok((key, name))
			(Ok(key), Ok((best_key, _))) => if key > best_key {
				Ok((key, name))
			} else {
				acc
			}
		},
	)
	best.map_ok(|(_, name)| name)
}

# Four dot-separated parts of at most five digits each fit in a U64.
version_key : Str -> Try(U64, [NotVersion])
version_key = |name| {
	parts = Str.split_on(name, ".")
	if parts.len() != 4 {
		Err(NotVersion)
	} else {
		parts.fold(
			Ok(0),
			|acc, part| match (acc, U64.from_str(part)) {
				(Ok(key), Ok(n)) => if n < 100_000 {
					Ok(key * 100_000 + n)
				} else {
					Err(NotVersion)
				}
				_ => Err(NotVersion)
			},
		)
	}
}

usage : Str
usage =
	\\Usage: roc scripts/build.roc -- <command>
	\\
	\\  inputs          copy sokol, Clay, compiler-rt or SDK libraries into platform/targets/<target>/
	\\  glue            regenerate engine/roc_platform_abi.odin
	\\  host            build the engine into platform/targets/<target>/
	\\  game <name>     link games/<name>, or else examples/<name>, against the platform
	\\  shaders         regenerate engine/shader_basic.odin, if sokol-shdc is on PATH
	\\  font            regenerate engine/font_baked.odin from scripts/fonts/, if odin is on PATH
	\\  keys            regenerate platform/Key.roc from the sokol Keycode enum
	\\  target          print the Roc target, the binary suffix and the host library for this machine
	\\  all             glue, host, inputs, game cards, game entity-game, game pong,
	\\                  game kula
	\\
	\\inputs, host and all take --release to use the release sokol archives and build
	\\the host with -o:speed. Without it they use debug.
	\\
	\\Run from the repository root. The target is the machine running the script.

main! : List(OsStr) => Try({}, [Exit(I32)])
main! = |args| {
	steps = match parse(args.map(OsStr.display)) {
		Ok(found) => found
		Err(Usage) => {
			Stderr.line!(usage) ?? {}
			return Err(Exit(2))
		}
	}
	target = match target_for(Env.platform!()) {
		Ok(found) => found
		Err(UnsupportedMachine) => fail!("This machine has no rocco target. Use macOS arm64, Linux x64 or Windows x64.")?
	}
	if !(Path.utf8("platform/main.roc").is_file!() ?? Bool.False) {
		fail!("Run the script from the repository root.")?
	}
	for step in steps {
		match run_step!(step, target) {
			Ok({}) => {}
			Err(Failed(message)) => fail!(message)?
			Err(err) => fail!(Str.inspect(err))?
		}
	}
	Ok({})
}

fail! : Str => Try(a, [Exit(I32)])
fail! = |message| {
	Stderr.line!("build: ${message}") ?? {}
	Err(Exit(1))
}

run_step! : Step, Target => Try({}, _)
run_step! = |step, target| match step {
	Inputs(mode) => inputs!(target, mode)
	Glue => exec!(glue_run)
	Host(mode) => {
		Path.utf8(target.dir).create_all!()?
		exec!(host_run(target, mode))
	}
	# roc build exits 2 when it wrote the binary with warnings and no errors.
	# The dbg in packages/mesh is such a warning, and roc has no flag to hide it.
	Game(name) => {
		dir = find_game_dir!(name) ? |_| Failed("Neither games/${name}/main.roc nor examples/${name}/main.roc exists.")
		exec_allowing!(game_run(target, dir, name), [2])
	}
	Shaders =>
		if Cmd.check_available!(shaders_run.program) {
			exec!(shaders_run)
		} else {
			Stdout.line!("== shaders: sokol-shdc is not on PATH, keeping the committed engine/shader_basic.odin")
		}
	Font =>
		if Cmd.check_available!(font_run.program) {
			Path.utf8("build").create_all!()?
			# The tool writes only after a full bake, so a failed run leaves the committed file whole.
			# On Linux it fails until Odin's stb libraries are built.
			match exec!(font_run) {
				Ok({}) => Ok({})
				Err(_) => Stdout.line!("== font: the bake tool did not run, keeping the committed engine/font_baked.odin")
			}
		} else {
			Stdout.line!("== font: odin is not on PATH, keeping the committed engine/font_baked.odin")
		}
	Keys => keys!()
	Target => Stdout.line!(target_lines(target))
}

find_game_dir! : Str => Try(Str, [NoGame])
find_game_dir! = |name| {
	for dir in game_dirs(name) {
		if Path.utf8("${dir}/main.roc").is_file!() ?? Bool.False {
			return Ok(dir)
		}
	}
	Err(NoGame)
}

exec! : Run => Try({}, _)
exec! = |run| exec_allowing!(run, [])

exec_allowing! : Run, List(I32) => Try({}, _)
exec_allowing! = |run, ok_codes| {
	Stdout.line!("== ${run.program} ${Str.join_with(run.args, " ")}")?
	cmd = Cmd.new_str(run.program).args(run.args.map(OsStr.from_str)).cwd(Path.utf8(run.cwd))
	match cmd.exec_cmd!() {
		Ok({}) => Ok({})
		Err(ExecCmdFailed({ exit_code, .. })) =>
			if List.contains(ok_codes, exit_code) {
				Ok({})
			} else {
				Err(Failed("${run.program} exited with ${exit_code.to_str()}"))
			}
		Err(other) => Err(other)
	}
}

key_module_path : Str
key_module_path = "platform/Key.roc"

keys! : () => Try({}, _)
keys! = || {
	Stdout.line!("== keys: ${Keys.sokol_app_path} -> ${key_module_path}")?
	source = Path.utf8(Keys.sokol_app_path).read_utf8!() ? |_| Failed("${Keys.sokol_app_path} is missing. Run git submodule update --init.")
	keys = match Keys.parse_keycodes(source) {
		Ok(found) => found
		Err(NoKeycodeEnum) => return Err(Failed("${Keys.sokol_app_path} has no Keycode enum."))
		Err(BadKeycodeLine(line)) => return Err(Failed("${Keys.sokol_app_path} has a Keycode line that is not NAME = code: ${line}"))
	}
	Path.utf8(key_module_path).write_utf8!(Keys.key_module(keys))
}

copy! : Copy => Try({}, _)
copy! = |file| Path.copy!(Path.utf8(file.from), Path.utf8(file.to))

inputs! : Target, Mode => Try({}, _)
inputs! = |target, mode| {
	Stdout.line!("== ${mode_name(mode)} inputs for ${target.roc_target}")?
	Path.utf8(target.dir).create_all!()?
	for file in sokol_copies(target, mode) {
		copy!(file) ? |_| Failed("${file.from} is missing. Build it with sokol's build_clibs script for this OS.")
	}
	for file in clay_copies(target) {
		copy!(file) ? |_| Failed("${file.from} is missing. Run git submodule update --init.")
	}
	match target.extra_inputs {
		MacSdk => {
			out = Cmd.new("xcrun").args(["clang", "-print-resource-dir"]).exec_output!()?
			copy!(compiler_rt_copy(Str.trim(out.stdout_utf8), target))
		}
		WindowsSdk => {
			program_files = Env.var_str!("ProgramFiles(x86)") ? |_| Failed("ProgramFiles(x86) is not set, so the Windows SDK cannot be found.")
			lib_root = "${program_files}/Windows Kits/10/Lib"
			entries = Path.utf8(lib_root).list!() ? |_| Failed("${lib_root} does not exist. Install the Windows SDK.")
			names = entries.map(|entry| entry.filename().map_ok(Path.display) ?? "")
			sdk = newest_sdk(names) ? |_| Failed("${lib_root} has no SDK version directory.")
			for file in windows_sdk_copies("${lib_root}/${sdk}", target) {
				copy!(file)?
			}
			Ok({})
		}
		LinuxSystem => {
			var $found = []
			for dir in linux_lib_dirs {
				if Path.utf8("${dir}/Scrt1.o").is_file!() ?? Bool.False {
					$found = $found.append(dir)
				}
			}
			lib_dir = linux_lib_dir_from($found) ? |_| Failed("No Scrt1.o in ${Str.join_with(linux_lib_dirs, ", ")}. Install the C development package, for example libc6-dev or glibc.")
			Stdout.line!("== system libraries from ${lib_dir}")?
			for file in linux_copies(lib_dir, target) {
				copy!(file) ? |_| Failed("${file.from} is missing. Install the X11, Xi, Xcursor and GL libraries. scripts/linux/Dockerfile lists the Ubuntu packages.")
			}
			Ok({})
		}
	}
}

expect parse(["inputs"]) == Ok([Inputs(Debug)])
expect parse(["inputs", "--release"]) == Ok([Inputs(Release)])
expect parse(["glue"]) == Ok([Glue])
expect parse(["host"]) == Ok([Host(Debug)])
expect parse(["host", "--release"]) == Ok([Host(Release)])
expect parse(["game", "cards"]) == Ok([Game("cards")])
expect parse(["shaders"]) == Ok([Shaders])
expect parse(["all"]) == Ok([Glue, Host(Debug), Inputs(Debug), Game("cards"), Game("entity-game"), Game("pong"), Game("kula")])
expect parse(["all", "--release"]) == Ok([Glue, Host(Release), Inputs(Release), Game("cards"), Game("entity-game"), Game("pong"), Game("kula")])
expect parse(["glue", "--release"]) == Err(Usage)
expect parse(["inputs", "--debug"]) == Err(Usage)
expect parse([]) == Err(Usage)
expect parse(["game"]) == Err(Usage)
expect parse(["host", "extra"]) == Err(Usage)
expect parse(["deploy"]) == Err(Usage)

mac = { arch: AARCH64, os: MACOS }

linux = { arch: X64, os: LINUX }

windows = { arch: X64, os: WINDOWS }

expect target_for(mac).map_ok(|target| target.roc_target) == Ok("arm64mac")
expect target_for(linux).map_ok(|target| target.roc_target) == Ok("x64glibc")
expect target_for(windows).map_ok(|target| target.roc_target) == Ok("x64win")
expect target_for({ arch: X64, os: MACOS }) == Err(UnsupportedMachine)
expect target_for({ arch: X64, os: OTHER("freebsd") }) == Err(UnsupportedMachine)

expect glue_run == { program: "roc", args: ["glue", "--no-cache", "glue/OdinGlue.roc", "./engine", "platform/main.roc"], cwd: "." }

expect {
	run = target_for(mac).map_ok(|target| host_run(target, Debug))
	run == Ok({ program: "odin", args: ["build", "engine", "-build-mode:static", "-out:platform/targets/arm64mac/libhost.a", "-debug", "-vet", "-strict-style"], cwd: "." })
}

expect {
	run = target_for(mac).map_ok(|target| host_run(target, Release))
	run == Ok({ program: "odin", args: ["build", "engine", "-build-mode:static", "-out:platform/targets/arm64mac/libhost.a", "-o:speed", "-debug", "-vet", "-strict-style"], cwd: "." })
}

expect {
	# basic-cli names the Windows host host.lib, which is what lld-link looks for.
	out = target_for(windows).map_ok(|target| host_run(target, Debug).args.get(3))
	out == Ok(Ok("-out:platform/targets/x64win/host.lib"))
}

expect {
	run = target_for(mac).map_ok(|target| game_run(target, "examples/cards", "cards"))
	run == Ok({ program: "roc", args: ["build", "--target=arm64mac", "--output=./cards.bin", "main.roc"], cwd: "examples/cards" })
}

expect {
	run = target_for(mac).map_ok(|target| game_run(target, "games/kula", "kula"))
	run == Ok({ program: "roc", args: ["build", "--target=arm64mac", "--output=./kula.bin", "main.roc"], cwd: "games/kula" })
}

expect game_dirs("kula") == ["games/kula", "examples/kula"]

expect {
	out = target_for(windows).map_ok(|target| game_run(target, "examples/cards", "cards").args.get(2))
	out == Ok(Ok("--output=./cards.exe"))
}

expect {
	copies = target_for(mac).map_ok(|target| sokol_copies(target, Debug))
	copies.map_ok(|all| all.first()) == Ok(Ok({ from: "sokol-odin/sokol/app/sokol_app_macos_arm64_metal_debug.a", to: "platform/targets/arm64mac/sokol_app.a" }))
}

expect {
	copies = target_for(mac).map_ok(|target| sokol_copies(target, Release))
	copies.map_ok(|all| all.first()) == Ok(Ok({ from: "sokol-odin/sokol/app/sokol_app_macos_arm64_metal_release.a", to: "platform/targets/arm64mac/sokol_app.a" }))
}

expect {
	copies = target_for(linux).map_ok(|target| sokol_copies(target, Release))
	copies.map_ok(|all| all.last()) == Ok(Ok({ from: "sokol-odin/sokol/log/sokol_log_linux_x64_gl_release.a", to: "platform/targets/x64glibc/sokol_log.a" }))
}

expect target_for(mac).map_ok(|target| sokol_copies(target, Debug).len()) == Ok(4)

expect target_for(mac).map_ok(clay_copies) == Ok([{ from: "clay/bindings/odin/clay-odin/macos-arm64/clay.a", to: "platform/targets/arm64mac/clay.a" }])
expect target_for(linux).map_ok(clay_copies) == Ok([{ from: "clay/bindings/odin/clay-odin/linux/clay.a", to: "platform/targets/x64glibc/clay.a" }])
expect target_for(windows).map_ok(|target| clay_copies(target).len()) == Ok(0)

expect {
	names = target_for(windows).map_ok(|target| sokol_copies(target, Debug).map(|file| file.to))
	names == Ok([
		"platform/targets/x64win/sokol_app.lib",
		"platform/targets/x64win/sokol_gfx.lib",
		"platform/targets/x64win/sokol_glue.lib",
		"platform/targets/x64win/sokol_log.lib",
	])
}

expect {
	copies = target_for(windows).map_ok(|target| sokol_copies(target, Release))
	copies.map_ok(|all| all.first()) == Ok(Ok({ from: "sokol-odin/sokol/app/sokol_app_windows_x64_d3d11_release.lib", to: "platform/targets/x64win/sokol_app.lib" }))
}

expect parse(["font"]) == Ok([Font])
expect font_run.args == ["run", "scripts/font_bake", "-out:build/font_bake", "--", "scripts/fonts/AtkinsonHyperlegible-Regular.ttf", "engine/font_baked.odin"]

expect shaders_run.args == ["-i", "engine/shaders/basic.glsl", "-o", "engine/shader_basic.odin", "-l", "metal_macos:glsl430:hlsl5", "-f", "sokol_odin"]

expect target_for(mac).map_ok(|target| target.extra_inputs) == Ok(MacSdk)
expect target_for(linux).map_ok(|target| target.extra_inputs) == Ok(LinuxSystem)
expect target_for(windows).map_ok(|target| target.extra_inputs) == Ok(WindowsSdk)

expect {
	# The Linux image mounts the checkout, so the Mac binary must survive a Linux build.
	out = target_for(linux).map_ok(|target| game_run(target, "examples/entity-game", "entity-game").args.get(2))
	out == Ok(Ok("--output=./entity-game_linux.bin"))
}

expect {
	names = target_for(linux).map_ok(|target| linux_copies("/usr/lib/x86_64-linux-gnu", target).map(|file| file.to))
	names == Ok([
		"platform/targets/x64glibc/Scrt1.o",
		"platform/targets/x64glibc/crti.o",
		"platform/targets/x64glibc/crtn.o",
		"platform/targets/x64glibc/libc.so.6",
		"platform/targets/x64glibc/libm.so.6",
		"platform/targets/x64glibc/libX11.so.6",
		"platform/targets/x64glibc/libXi.so.6",
		"platform/targets/x64glibc/libXcursor.so.1",
		"platform/targets/x64glibc/libGL.so.1",
	])
}

expect {
	copies = target_for(linux).map_ok(|target| linux_copies("/usr/lib/x86_64-linux-gnu", target))
	copies.map_ok(|all| all.first()) == Ok(Ok({ from: "/usr/lib/x86_64-linux-gnu/Scrt1.o", to: "platform/targets/x64glibc/Scrt1.o" }))
}

expect newest_sdk(["10.0.19041.0", "10.0.22621.0", "10.0.20348.0"]) == Ok("10.0.22621.0")
expect newest_sdk(["10.0.9.0", "10.0.10.0"]) == Ok("10.0.10.0")
expect newest_sdk(["wdf", "10.0.22621.0"]) == Ok("10.0.22621.0")
expect newest_sdk(["wdf"]) == Err(NoSdk)
expect newest_sdk([]) == Err(NoSdk)

expect {
	copies = target_for(windows).map_ok(|target| windows_sdk_copies("C:/Kits/10/Lib/10.0.22621.0", target))
	copies.map_ok(|all| all.first()) == Ok(Ok({ from: "C:/Kits/10/Lib/10.0.22621.0/um/x64/kernel32.lib", to: "platform/targets/x64win/kernel32.lib" }))
}

expect {
	copy = target_for(mac).map_ok(|target| compiler_rt_copy("/Xcode/usr/lib/clang/21", target))
	copy == Ok({ from: "/Xcode/usr/lib/clang/21/lib/darwin/libclang_rt.osx.a", to: "platform/targets/arm64mac/libclang_rt.osx.a" })
}

expect linux_lib_dir_from(["/usr/lib/x86_64-linux-gnu", "/usr/lib"]) == Ok("/usr/lib/x86_64-linux-gnu")
expect linux_lib_dir_from(["/usr/lib"]) == Ok("/usr/lib")
expect linux_lib_dir_from(["/usr/lib64", "/usr/lib"]) == Ok("/usr/lib64")
expect linux_lib_dir_from([]) == Err(NoLibDir)

expect parse(["keys"]) == Ok([Keys])

expect parse(["target"]) == Ok([Target])
expect target_for(mac).map_ok(target_lines) == Ok("target=arm64mac\nsuffix=.bin\nhost_lib=platform/targets/arm64mac/libhost.a")
expect target_for(linux).map_ok(target_lines) == Ok("target=x64glibc\nsuffix=_linux.bin\nhost_lib=platform/targets/x64glibc/libhost.a")
expect target_for(windows).map_ok(target_lines) == Ok("target=x64win\nsuffix=.exe\nhost_lib=platform/targets/x64win/host.lib")
