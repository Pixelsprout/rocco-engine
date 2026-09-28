app [main!] { roc: "nightly-2026-09-12-220fd47", pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.23.0-rc1/3hT3SoHZ6qbEsa9qVFLUW3547U5LeoNd1KbpqLpz4r1i.tar.zst" }

import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Path
import pf.Stderr
import pf.Stdout

Step : [Inputs, Glue, Host, Game(Str), Shaders, Keys]

parse : List(Str) -> Try(List(Step), [Usage])
parse = |args| match args {
	["inputs"] => Ok([Inputs])
	["glue"] => Ok([Glue])
	["host"] => Ok([Host])
	["game", example] => Ok([Game(example)])
	["shaders"] => Ok([Shaders])
	["keys"] => Ok([Keys])
	["all"] => Ok([Glue, Host, Inputs, Game("cards"), Game("entity-game")])
	_ => Err(Usage)
}

# extra_inputs names what inputs copies besides the sokol archives.
Target : {
	roc_target : Str,
	dir : Str,
	host_lib : Str,
	sokol_suffix : Str,
	exe : Str,
	extra_inputs : [MacSdk, WindowsSdk, LinuxSystem],
}

Machine : { arch : [X86, X64, ARM, AARCH64, OTHER(Str)], os : [LINUX, MACOS, WINDOWS, OTHER(Str)] }

target_for : Machine -> Try(Target, [UnsupportedMachine])
target_for = |machine| match (machine.os, machine.arch) {
	(MACOS, AARCH64) => Ok(make_target("arm64mac", "libhost.a", "macos_arm64_metal_debug.a", ".bin", MacSdk))
	(LINUX, X64) => Ok(make_target("x64glibc", "libhost.a", "linux_x64_gl_debug.a", "_linux.bin", LinuxSystem))
	(WINDOWS, X64) => Ok(make_target("x64win", "host.lib", "windows_x64_d3d11_debug.lib", ".exe", WindowsSdk))
	_ => Err(UnsupportedMachine)
}

make_target : Str, Str, Str, Str, [MacSdk, WindowsSdk, LinuxSystem] -> Target
make_target = |roc_target, host_lib, sokol_suffix, exe, extra_inputs| {
	roc_target,
	dir: "platform/targets/${roc_target}",
	host_lib,
	sokol_suffix,
	exe,
	extra_inputs,
}

Run : { program : Str, args : List(Str), cwd : Str }

glue_run : Run
glue_run = { program: "roc", args: ["glue", "glue/OdinGlue.roc", "./engine", "platform/main.roc"], cwd: "." }

host_run : Target -> Run
host_run = |target| {
	program: "odin",
	args: ["build", "engine", "-build-mode:static", "-out:${target.dir}/${target.host_lib}", "-debug", "-vet", "-strict-style"],
	cwd: ".",
}

game_run : Target, Str -> Run
game_run = |target, example| {
	program: "roc",
	args: ["build", "--target=${target.roc_target}", "--output=./${example}${target.exe}", "main.roc"],
	cwd: "examples/${example}",
}

shaders_run : Run
shaders_run = {
	program: "sokol-shdc",
	args: ["-i", "engine/shaders/basic.glsl", "-o", "engine/shader_basic.odin", "-l", "metal_macos:glsl430:hlsl5", "-f", "sokol_odin"],
	cwd: ".",
}

Copy : { from : Str, to : Str }

sokol_copies : Target -> List(Copy)
sokol_copies = |target| ["app", "gfx", "glue", "log"].map(|part| {
	name = "sokol_${part}_${target.sokol_suffix}"
	{ from: "sokol-odin/sokol/${part}/${name}", to: "${target.dir}/${name}" }
})

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
	best = names.fold(Err(NoSdk), |acc, name| match (version_key(name), acc) {
		(Err(_), _) => acc
		(Ok(key), Err(_)) => Ok((key, name))
		(Ok(key), Ok((best_key, _))) => if key > best_key { Ok((key, name)) } else { acc }
	})
	best.map_ok(|(_, name)| name)
}

# Four dot-separated parts of at most five digits each fit in a U64.
version_key : Str -> Try(U64, [NotVersion])
version_key = |name| {
	parts = Str.split_on(name, ".")
	if parts.len() != 4 {
		Err(NotVersion)
	} else {
		parts.fold(Ok(0), |acc, part| match (acc, U64.from_str(part)) {
			(Ok(key), Ok(n)) => if n < 100_000 { Ok(key * 100_000 + n) } else { Err(NotVersion) }
			_ => Err(NotVersion)
		})
	}
}

usage : Str
usage =
	\\Usage: roc scripts/build.roc -- <command>
	\\
	\\  inputs          copy sokol, compiler-rt or SDK libraries into platform/targets/<target>/
	\\  glue            regenerate engine/roc_platform_abi.odin
	\\  host            build the engine into platform/targets/<target>/
	\\  game <example>  link examples/<example> against the platform
	\\  shaders         regenerate engine/shader_basic.odin, if sokol-shdc is on PATH
	\\  keys            regenerate platform/Key.roc from the sokol Keycode enum
	\\  all             glue, host, inputs, game cards, game entity-game
	\\
	\\Run from the repository root. The target is the machine running the script.

main! : List(OsStr) => Try({}, [Exit(I32), ..])
main! = |args| {
	steps = match parse(args.drop_first(1).map(OsStr.display)) {
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

fail! : Str => Try(a, [Exit(I32), ..])
fail! = |message| {
	Stderr.line!("build: ${message}") ?? {}
	Err(Exit(1))
}

run_step! : Step, Target => Try({}, _)
run_step! = |step, target| match step {
	Inputs => inputs!(target)
	Glue => exec!(glue_run)
	Host => {
		Path.utf8(target.dir).create_all!()?
		exec!(host_run(target))
	}
	# roc build exits 2 when it wrote the binary with warnings and no errors.
	# The dbg in packages/meshes is such a warning, and roc has no flag to hide it.
	Game(example) => exec_allowing!(game_run(target, example), [2])
	Shaders =>
		if Cmd.check_available!(shaders_run.program) {
			exec!(shaders_run)
		} else {
			Stdout.line!("== shaders: sokol-shdc is not on PATH, keeping the committed engine/shader_basic.odin")
		}
	Keys => keys!()
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

sokol_app_path : Str
sokol_app_path = "sokol-odin/sokol/app/app.odin"

key_module_path : Str
key_module_path = "platform/Key.roc"

keys! : () => Try({}, _)
keys! = || {
	Stdout.line!("== keys: ${sokol_app_path} -> ${key_module_path}")?
	source = Path.utf8(sokol_app_path).read_utf8!() ? |_| Failed("${sokol_app_path} is missing. Run git submodule update --init.")
	keys = match parse_keycodes(source) {
		Ok(found) => found
		Err(NoKeycodeEnum) => return Err(Failed("${sokol_app_path} has no Keycode enum."))
		Err(BadKeycodeLine(line)) => return Err(Failed("${sokol_app_path} has a Keycode line that is not NAME = code: ${line}"))
	}
	Path.utf8(key_module_path).write_utf8!(key_module(keys))
}

KeyEntry : { tag : Str, code : U16 }

# Reads the body of `Keycode :: enum i32 { ... }`, one `NAME = code,` per line.
# INVALID is 0, which sokol never reports, so it gets no tag.
parse_keycodes : Str -> Try(List(KeyEntry), [NoKeycodeEnum, BadKeycodeLine(Str)])
parse_keycodes = |source| {
	body = match Str.split_first(source, "Keycode :: enum i32 {") {
		Ok({ after, .. }) => match Str.split_first(after, "}") {
			Ok({ before, .. }) => before
			Err(_) => return Err(NoKeycodeEnum)
		}
		Err(_) => return Err(NoKeycodeEnum)
	}
	var $entries = []
	for line in Str.split_on(body, "\n").map(Str.trim) {
		match Str.split_first(line, " = ") {
			_ if line == "" => {}
			Ok({ before: "INVALID", .. }) => {}
			Ok({ before, after }) => match U16.from_str(Str.drop_suffix(after, ",")) {
				Ok(code) => {
					$entries = $entries.append({ tag: key_tag(before), code })
				}
				Err(_) => return Err(BadKeycodeLine(line))
			}
			Err(_) => return Err(BadKeycodeLine(line))
		}
	}
	Ok($entries)
}

# LEFT_SHIFT becomes LeftShift. A tag cannot start with a digit, so _0 becomes Num0.
key_tag : Str -> Str
key_tag = |name|
	if Str.starts_with(name, "_") {
		Str.concat("Num", Str.drop_prefix(name, "_"))
	} else {
		Str.join_with(Str.split_on(name, "_").map(capitalized), "")
	}

capitalized : Str -> Str
capitalized = |word| {
	lower = Str.to_utf8(Str.with_ascii_lowercased(word))
	first = Str.to_utf8(word).take_first(1)
	Str.from_utf8(List.concat(first, lower.drop_first(1))) ?? word
}

key_module : List(KeyEntry) -> Str
key_module = |keys| {
	tags = Str.join_with(keys.map(|key| "    ${key.tag},\n"), "")
	codes = Str.join_with(keys.map(|key| "        ${key.tag} => ${key.code.to_str()}\n"), "")
	Str.join_with([key_module_head, key_module_intro, "Key := [\n", tags, "].{\n", key_module_code_head, codes, key_module_tail], "")
}

key_module_head : Str
key_module_head = "# Generated by roc scripts/build.roc -- keys from the Keycode enum in\n# ${sokol_app_path}. Do not edit.\n"

key_module_intro : Str
key_module_intro =
	\\import Vocabulary exposing [Input]
	\\
	\\# A named sokol key code. The game decides what a key means.
	\\

key_module_code_head : Str
key_module_code_head =
	\\    code : Key -> U16
	\\    code = |key| match key {
	\\

key_module_tail : Str
key_module_tail =
	\\    }
	\\
	\\    held : Input, Key -> Bool
	\\    held = |input, key| List.contains(input.held, code(key))
	\\
	\\    pressed : Input, Key -> Bool
	\\    pressed = |input, key| List.contains(input.pressed, code(key))
	\\
	\\    # 1.0 when only pos is held, -1.0 when only neg is held, else 0.0.
	\\    axis : Input, Key, Key -> F32
	\\    axis = |input, neg, pos| (if held(input, pos) 1.0 else 0.0) - (if held(input, neg) 1.0 else 0.0)
	\\}
	\\
	\\expect Key.code(Space) == 32
	\\expect Key.code(W) == 87
	\\expect Key.code(Num0) == 48
	\\expect Key.code(Kp0) == 320
	\\expect Key.code(Escape) == 256
	\\
	\\idle : Input
	\\idle = { held: [], pressed: [], mouse: { dx: 0.0, dy: 0.0 } }
	\\
	\\expect Key.held({ ..idle, held: [87] }, W) and !Key.held({ ..idle, pressed: [87] }, W)
	\\expect Key.pressed({ ..idle, pressed: [32] }, Space) and !Key.pressed({ ..idle, held: [32] }, Space)
	\\expect Key.axis({ ..idle, held: [87] }, S, W) == 1.0
	\\expect Key.axis({ ..idle, held: [83] }, S, W) == -1.0
	\\expect Key.axis({ ..idle, held: [83, 87] }, S, W) == 0.0
	\\expect Key.axis(idle, S, W) == 0.0
	\\

copy! : Copy => Try({}, _)
copy! = |file| Path.copy!(Path.utf8(file.from), Path.utf8(file.to))

inputs! : Target => Try({}, _)
inputs! = |target| {
	Stdout.line!("== inputs for ${target.roc_target}")?
	Path.utf8(target.dir).create_all!()?
	for file in sokol_copies(target) {
		copy!(file) ? |_| Failed("${file.from} is missing. Build it with sokol's build_clibs script for this OS.")
	}
	match target.extra_inputs {
		MacSdk => {
			# xcrun picks Xcode's clang, whose compiler-rt matches the SDK the sysroot comes from.
			out = Cmd.new("xcrun").args(["clang", "-print-resource-dir"]).exec_output!()?
			copy!(compiler_rt_copy(Str.trim(out.stdout_utf8), target))?
			exec!({ program: "./scripts/make-macos-sysroot.sh", args: ["platform/targets/macos-sysroot"], cwd: "." })
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

expect parse(["inputs"]) == Ok([Inputs])
expect parse(["glue"]) == Ok([Glue])
expect parse(["host"]) == Ok([Host])
expect parse(["game", "cards"]) == Ok([Game("cards")])
expect parse(["shaders"]) == Ok([Shaders])
expect parse(["all"]) == Ok([Glue, Host, Inputs, Game("cards"), Game("entity-game")])
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

expect glue_run == { program: "roc", args: ["glue", "glue/OdinGlue.roc", "./engine", "platform/main.roc"], cwd: "." }

expect {
	run = target_for(mac).map_ok(host_run)
	run == Ok({ program: "odin", args: ["build", "engine", "-build-mode:static", "-out:platform/targets/arm64mac/libhost.a", "-debug", "-vet", "-strict-style"], cwd: "." })
}

expect {
	# basic-cli names the Windows host host.lib, which is what lld-link looks for.
	out = target_for(windows).map_ok(|target| host_run(target).args.get(3))
	out == Ok(Ok("-out:platform/targets/x64win/host.lib"))
}

expect {
	run = target_for(mac).map_ok(|target| game_run(target, "cards"))
	run == Ok({ program: "roc", args: ["build", "--target=arm64mac", "--output=./cards.bin", "main.roc"], cwd: "examples/cards" })
}

expect {
	out = target_for(windows).map_ok(|target| game_run(target, "cards").args.get(2))
	out == Ok(Ok("--output=./cards.exe"))
}

expect {
	copies = target_for(mac).map_ok(sokol_copies)
	copies.map_ok(|all| all.first()) == Ok(Ok({ from: "sokol-odin/sokol/app/sokol_app_macos_arm64_metal_debug.a", to: "platform/targets/arm64mac/sokol_app_macos_arm64_metal_debug.a" }))
}

expect target_for(mac).map_ok(|target| sokol_copies(target).len()) == Ok(4)

expect {
	names = target_for(windows).map_ok(|target| sokol_copies(target).map(|file| file.to))
	names == Ok([
		"platform/targets/x64win/sokol_app_windows_x64_d3d11_debug.lib",
		"platform/targets/x64win/sokol_gfx_windows_x64_d3d11_debug.lib",
		"platform/targets/x64win/sokol_glue_windows_x64_d3d11_debug.lib",
		"platform/targets/x64win/sokol_log_windows_x64_d3d11_debug.lib",
	])
}

expect shaders_run.args == ["-i", "engine/shaders/basic.glsl", "-o", "engine/shader_basic.odin", "-l", "metal_macos:glsl430:hlsl5", "-f", "sokol_odin"]

expect target_for(mac).map_ok(|target| target.extra_inputs) == Ok(MacSdk)
expect target_for(linux).map_ok(|target| target.extra_inputs) == Ok(LinuxSystem)
expect target_for(windows).map_ok(|target| target.extra_inputs) == Ok(WindowsSdk)

expect {
	# The Linux image mounts the checkout, so the Mac binary must survive a Linux build.
	out = target_for(linux).map_ok(|target| game_run(target, "entity-game").args.get(2))
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

expect key_tag("SPACE") == "Space"
expect key_tag("LEFT_SHIFT") == "LeftShift"
expect key_tag("F1") == "F1"
expect key_tag("WORLD_1") == "World1"
expect key_tag("_0") == "Num0"
expect key_tag("KP_0") == "Kp0"
expect key_tag("KP_DECIMAL") == "KpDecimal"

sokol_keycode_sample : Str
sokol_keycode_sample =
	\\Mouse_Button :: enum i32 {
	\\    LEFT = 0,
	\\}
	\\Keycode :: enum i32 {
	\\    INVALID = 0,
	\\    SPACE = 32,
	\\    _0 = 48,
	\\    LEFT_SHIFT = 340,
	\\}
	\\Touch_Point :: struct {
	\\    changed : bool,
	\\}

expect parse_keycodes(sokol_keycode_sample) == Ok([{ tag: "Space", code: 32 }, { tag: "Num0", code: 48 }, { tag: "LeftShift", code: 340 }])
expect parse_keycodes("Mouse_Button :: enum i32 {\n    LEFT = 0,\n}") == Err(NoKeycodeEnum)
expect parse_keycodes("Keycode :: enum i32 {\n    SPACE = 32,\n    MENU = 1 << 9,\n}") == Err(BadKeycodeLine("MENU = 1 << 9,"))

expect {
	out = key_module([{ tag: "Space", code: 32 }, { tag: "W", code: 87 }])
	Str.contains(out, "Key := [\n    Space,\n    W,\n].{")
		and Str.contains(out, "        Space => 32\n        W => 87\n")
		and Str.starts_with(out, "# Generated by roc scripts/build.roc -- keys")
}
