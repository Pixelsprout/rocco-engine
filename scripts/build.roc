app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0-rc1/GMezHWvmUP42Leqg8YkABvEk27cMUSVM6p7oz3XPj11N.tar.zst", roc: "nightly-2026-10-11-7d256b9" }

import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Path
import pf.Stderr
import pf.Stdout
import Keys

Mode : [Debug, Release]

# Tracked builds the host with the host tracking allocator and its leak report.
HostAlloc : [Tracked, Untracked]

# Spans builds the host with the per-Frame Span timers and the CSV sink.
HostSpans : [Spans, NoSpans]

# One bench game run at one N, Headless, for warmup plus measured Frames.
Bench : { game : Str, n : U64 }

Step : [Inputs(Mode), Glue, Host(Mode, HostAlloc, HostSpans), Game(Str), Shaders, Font, Keys, Target, BenchGame(Str), BenchRun(Bench)]

parse : List(Str) -> Try(List(Step), [Usage])
parse = |args| match args {
	["inputs"] => Ok([Inputs(Debug)])
	["inputs", "--release"] => Ok([Inputs(Release)])
	["glue"] => Ok([Glue])
	["host"] => Ok([Host(Debug, default_host_alloc(Debug), NoSpans)])
	["host", "--spans"] => Ok([Host(Debug, default_host_alloc(Debug), Spans)])
	["host", "--release"] => Ok([Host(Release, default_host_alloc(Release), NoSpans)])
	["host", "--release", "--spans"] => Ok([Host(Release, default_host_alloc(Release), Spans)])
	["host", "--release", "--track-alloc"] => Ok([Host(Release, Tracked, NoSpans)])
	["game", name] => Ok([Game(name)])
	["shaders"] => Ok([Shaders])
	["font"] => Ok([Font])
	["keys"] => Ok([Keys])
	["target"] => Ok([Target])
	["all"] => Ok(all_steps(Debug))
	["all", "--release"] => Ok(all_steps(Release))
	["bench", game, n] =>
		match U64.from_str(n) {
			Ok(count) if count > 0 => Ok([bench_host, Inputs(Release), BenchGame(game), BenchRun({ game, n: count })])
			_ => Err(Usage)
		}
	_ => Err(Usage)
}

all_steps : Mode -> List(Step)
all_steps = |mode| [Glue, Host(mode, default_host_alloc(mode), NoSpans), Inputs(mode), Game("cards"), Game("entity-game"), Game("pong")]

default_host_alloc : Mode -> HostAlloc
default_host_alloc = |mode| match mode {
	Debug => Tracked
	Release => Untracked
}

mode_name : Mode -> Str
mode_name = |mode| match mode {
	Debug => "debug"
	Release => "release"
}

# extra_inputs names what inputs copies besides the sokol and Clay archives.
# host_flags are the Odin flags that only this target's host build takes.
Target : {
	roc_target : Str,
	dir : Str,
	host_lib : Str,
	host_flags : List(Str),
	sokol_platform : Str,
	lib_ext : Str,
	exe : Str,
	extra_inputs : [MacSdk, WindowsImportLibs, LinuxStubs],
}

Machine : { arch : [X86, X64, ARM, AARCH64, OTHER(Str)], os : [LINUX, MACOS, WINDOWS, OTHER(Str)] }

target_for : Machine -> Try(Target, [UnsupportedMachine])
target_for = |machine| match (machine.os, machine.arch) {
	(MACOS, AARCH64) => Ok(make_target("arm64mac", "libhost.a", [], "macos_arm64_metal", ".a", ".bin", MacSdk))
	(LINUX, X64) => Ok(make_target("x64glibc", "libhost.a", [], "linux_x64_gl", ".a", "_linux.bin", LinuxStubs))
	# Roc links x64win with /nodefaultlib, so the host takes no CRT either. With
	# no CRT, nothing writes the TLS directory, so Odin's thread_local variables
	# must be plain globals.
	(WINDOWS, X64) => Ok(make_target("x64win", "host.lib", ["-no-crt", "-no-thread-local"], "windows_x64_d3d11", ".lib", ".exe", WindowsImportLibs))
	_ => Err(UnsupportedMachine)
}

make_target : Str, Str, List(Str), Str, Str, Str, [MacSdk, WindowsImportLibs, LinuxStubs] -> Target
make_target = |roc_target, host_lib, host_flags, sokol_platform, lib_ext, exe, extra_inputs| {
	roc_target,
	dir: "platform/targets/${roc_target}",
	host_lib,
	host_flags,
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

host_run : Target, Mode, HostAlloc, HostSpans -> Run
host_run = |target, mode, alloc, spans| {
	opt = match mode {
		Debug => ["-debug"]
		Release => ["-o:speed"]
	}
	track = match alloc {
		Tracked => ["-define:ROCCO_TRACK_ALLOC=true"]
		Untracked => []
	}
	span_defines = match spans {
		Spans => ["-define:ROCCO_SPANS=true"]
		NoSpans => []
	}
	{
		program: "odin",
		args: ["build", "engine", "-build-mode:static", "-out:${target.dir}/${target.host_lib}"].concat(target.host_flags).concat(opt).concat(track).concat(span_defines).concat(["-vet", "-strict-style"]),
		cwd: ".",
	}
}

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

bench_host : Step
bench_host = Host(Release, Untracked, Spans)

bench_warmup_frames : U64
bench_warmup_frames = 120

bench_measured_frames : U64
bench_measured_frames = 2000

bench_out_dir : Str
bench_out_dir = "bench/out"

bench_stem : Bench -> Str
bench_stem = |bench| "${bench_out_dir}/${bench.game}-${bench.n.to_str()}"

# root is the absolute repository root. The engine writes the Spans CSV to
# ROCCO_SPANS_CSV and runs Headless for ROCCO_EXIT_AFTER_FRAMES Frames.
bench_run : Target, Bench, Str -> { run : Run, env : List((Str, Str)) }
bench_run = |target, bench, root| {
	frames = bench_warmup_frames + bench_measured_frames
	{
		run: {
			program: "${root}/bench/${bench.game}/${bench.game}${target.exe}",
			args: [bench.n.to_str()],
			cwd: "bench/${bench.game}",
		},
		env: [
			("ROCCO_HEADLESS", "1"),
			("ROCCO_EXIT_AFTER_FRAMES", frames.to_str()),
			("ROCCO_SPANS_CSV", "${root}/${bench_stem(bench)}.csv"),
		],
	}
}

# What bench/analyse.py needs beside the CSV. The host flags decide ODIN_DEBUG:
# odin sets it only for -debug.
bench_meta : Target, Bench, Str -> Str
bench_meta = |target, bench, git_hash| {
	host_flags = host_run(target, Release, Untracked, Spans).args
	game_flags = game_run(target, "bench/${bench.game}", bench.game).args
	odin_debug = if host_flags.contains("-debug") "true" else "false"
	json_list = |words| "[${Str.join_with(words.map(|w| "\"${w}\""), ", ")}]"
	lines = [
		"{",
		"  \"game\": \"${bench.game}\",",
		"  \"n\": ${bench.n.to_str()},",
		"  \"mode\": \"headless\",",
		"  \"warmup_frames\": ${bench_warmup_frames.to_str()},",
		"  \"measured_frames\": ${bench_measured_frames.to_str()},",
		"  \"seed\": 0,",
		"  \"git_hash\": \"${git_hash}\",",
		"  \"target\": \"${target.roc_target}\",",
		"  \"odin_debug\": ${odin_debug},",
		"  \"build_flags\": { \"host\": ${json_list(host_flags)}, \"game\": ${json_list(game_flags)} }",
		"}",
		"",
	]
	Str.join_with(lines, "\n")
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

# Clay ships one prebuilt archive per OS beside its Odin bindings.
clay_copies : Target -> List(Copy)
clay_copies = |target| match target.extra_inputs {
	MacSdk => [clay_copy("macos-arm64", target)]
	LinuxStubs => [clay_copy("linux", target)]
	WindowsImportLibs => [clay_copy("windows", target)]
}

clay_copy : Str, Target -> Copy
clay_copy = |os_dir, target| { from: "${clay_odin_dir}/${os_dir}/clay${target.lib_ext}", to: "${target.dir}/clay${target.lib_ext}" }

compiler_rt_copy : Str, Target -> Copy
compiler_rt_copy = |resource_dir, target| {
	from: "${resource_dir}/lib/darwin/libclang_rt.osx.a",
	to: "${target.dir}/libclang_rt.osx.a",
}

usage : Str
usage =
	\\Usage: roc scripts/build.roc -- <command>
	\\
	\\  inputs          copy sokol, Clay and compiler-rt libraries into platform/targets/<target>/
	\\  glue            regenerate engine/roc_platform_abi.odin
	\\  host            build the engine into platform/targets/<target>/
	\\  game <name>     link examples/<name> against the platform
	\\  shaders         regenerate engine/shader_basic.odin, if sokol-shdc is on PATH
	\\  font            regenerate engine/font_baked.odin from scripts/fonts/, if odin is on PATH
	\\  keys            regenerate platform/Key.roc from the sokol Keycode enum
	\\  target          print the Roc target, the binary suffix and the host library for this machine
	\\  all             glue, host, inputs, game cards, game entity-game, game pong
	\\  bench <game> <n>
	\\                  build a release host with Spans, the release inputs and
	\\                  bench/<game>, then run it Headless with N as its first Arg.
	\\                  Writes bench/out/<game>-<n>.csv and <game>-<n>.run.json.
	\\                  Run all again before you run the examples.
	\\
	\\inputs, host and all take --release to use the release sokol archives and build
	\\the host with -o:speed and without -debug. Without it they use debug.
	\\
	\\A debug host has the host tracking allocator and its leak report. A release
	\\host has it only with host --release --track-alloc.
	\\
	\\host --spans and host --release --spans add the per-Frame Span timers. Such a
	\\host writes one CSV row per Frame to the path in ROCCO_SPANS_CSV.
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
	Host(mode, alloc, spans) => host!(target, host_run(target, mode, alloc, spans))
	Game(name) => link_game!(target, "examples/${name}", name)
	BenchGame(name) => link_game!(target, "bench/${name}", name)
	BenchRun(bench) => bench!(target, bench)
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

host! : Target, Run => Try({}, _)
host! = |target, run| {
	Path.utf8(target.dir).create_all!()?
	# odin adds members to an existing archive, so an object from an older
	# build with other defines can survive.
	match Path.utf8("${target.dir}/${target.host_lib}").delete!() {
		Ok({}) => {}
		Err(PathErr(NotFound, _)) => {}
		Err(err) => return Err(err)
	}
	exec!(run)
}

# roc build exits 2 when it wrote the binary with warnings and no errors.
# The dbg in packages/mesh is such a warning, and roc has no flag to hide it.
link_game! : Target, Str, Str => Try({}, _)
link_game! = |target, dir, name| {
	if !(Path.utf8("${dir}/main.roc").is_file!() ?? Bool.False) {
		return Err(Failed("${dir}/main.roc does not exist."))
	}
	exec_allowing!(game_run(target, dir, name), [2])
}

bench! : Target, Bench => Try({}, _)
bench! = |target, bench| {
	root = Env.cwd!() ? |_| Failed("The working directory is unavailable.")
	git = Cmd.new("git").args(["rev-parse", "HEAD"]).exec_output!() ? |_| Failed("git rev-parse HEAD failed.")
	status = Cmd.new("git").args(["status", "--porcelain"]).exec_output!() ? |_| Failed("git status failed.")
	dirty = if Str.trim(status.stdout_utf8) == "" "" else "-dirty"
	Path.utf8(bench_out_dir).create_all!()?
	planned = bench_run(target, bench, root.display())
	exec_env_allowing!(planned.run, planned.env, [])?
	meta_path = "${bench_stem(bench)}.run.json"
	Path.utf8(meta_path).write_utf8!(bench_meta(target, bench, "${Str.trim(git.stdout_utf8)}${dirty}"))?
	Stdout.line!("== bench: wrote ${bench_stem(bench)}.csv and ${meta_path}")
}

exec! : Run => Try({}, _)
exec! = |run| exec_allowing!(run, [])

exec_allowing! : Run, List(I32) => Try({}, _)
exec_allowing! = |run, ok_codes| exec_env_allowing!(run, [], ok_codes)

exec_env_allowing! : Run, List((Str, Str)), List(I32) => Try({}, _)
exec_env_allowing! = |run, env, ok_codes| {
	env_words = env.map(|(name, value)| "${name}=${value} ")
	Stdout.line!("== ${Str.join_with(env_words, "")}${run.program} ${Str.join_with(run.args, " ")}")?
	cmd = Cmd.new_str(run.program).args(run.args.map(OsStr.from_str)).envs_str(env).cwd(Path.utf8(run.cwd))
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
		# scripts/make_windows_import_libs.py writes these inputs, and they are committed.
		WindowsImportLibs => Ok({})
		# scripts/make_linux_stubs.py writes these inputs, and they are committed.
		LinuxStubs => Ok({})
	}
}

expect parse(["inputs"]) == Ok([Inputs(Debug)])
expect parse(["inputs", "--release"]) == Ok([Inputs(Release)])
expect parse(["glue"]) == Ok([Glue])
expect parse(["host"]) == Ok([Host(Debug, Tracked, NoSpans)])
expect parse(["host", "--spans"]) == Ok([Host(Debug, Tracked, Spans)])
expect parse(["host", "--release"]) == Ok([Host(Release, Untracked, NoSpans)])
expect parse(["host", "--release", "--spans"]) == Ok([Host(Release, Untracked, Spans)])
expect parse(["host", "--release", "--track-alloc"]) == Ok([Host(Release, Tracked, NoSpans)])
expect parse(["game", "cards"]) == Ok([Game("cards")])
expect parse(["shaders"]) == Ok([Shaders])
expect parse(["all"]) == Ok([Glue, Host(Debug, Tracked, NoSpans), Inputs(Debug), Game("cards"), Game("entity-game"), Game("pong")])
expect parse(["all", "--release"]) == Ok([Glue, Host(Release, Untracked, NoSpans), Inputs(Release), Game("cards"), Game("entity-game"), Game("pong")])
expect parse(["glue", "--release"]) == Err(Usage)
expect parse(["inputs", "--debug"]) == Err(Usage)
expect parse(["inputs", "--release", "--track-alloc"]) == Err(Usage)
expect parse(["host", "--track-alloc"]) == Err(Usage)
expect parse(["host", "--spans", "--release"]) == Err(Usage)
expect parse([]) == Err(Usage)
expect parse(["game"]) == Err(Usage)
expect parse(["host", "extra"]) == Err(Usage)
expect parse(["deploy"]) == Err(Usage)
expect parse(["bench", "model-size", "64"]) == Ok([Host(Release, Untracked, Spans), Inputs(Release), BenchGame("model-size"), BenchRun({ game: "model-size", n: 64 })])
expect parse(["bench", "model-size", "0"]) == Err(Usage)
expect parse(["bench", "model-size", "many"]) == Err(Usage)
expect parse(["bench", "model-size"]) == Err(Usage)

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
	run = target_for(mac).map_ok(|target| host_run(target, Debug, Tracked, NoSpans))
	run == Ok({ program: "odin", args: ["build", "engine", "-build-mode:static", "-out:platform/targets/arm64mac/libhost.a", "-debug", "-define:ROCCO_TRACK_ALLOC=true", "-vet", "-strict-style"], cwd: "." })
}

expect {
	run = target_for(mac).map_ok(|target| host_run(target, Release, Untracked, NoSpans))
	run == Ok({ program: "odin", args: ["build", "engine", "-build-mode:static", "-out:platform/targets/arm64mac/libhost.a", "-o:speed", "-vet", "-strict-style"], cwd: "." })
}

expect {
	run = target_for(mac).map_ok(|target| host_run(target, Release, Tracked, NoSpans))
	run == Ok({ program: "odin", args: ["build", "engine", "-build-mode:static", "-out:platform/targets/arm64mac/libhost.a", "-o:speed", "-define:ROCCO_TRACK_ALLOC=true", "-vet", "-strict-style"], cwd: "." })
}

expect {
	run = target_for(mac).map_ok(|target| host_run(target, Release, Untracked, Spans))
	run == Ok({ program: "odin", args: ["build", "engine", "-build-mode:static", "-out:platform/targets/arm64mac/libhost.a", "-o:speed", "-define:ROCCO_SPANS=true", "-vet", "-strict-style"], cwd: "." })
}

expect {
	# basic-cli names the Windows host host.lib, which is what lld-link looks for.
	out = target_for(windows).map_ok(|target| host_run(target, Debug, Tracked, NoSpans).args.get(3))
	out == Ok(Ok("-out:platform/targets/x64win/host.lib"))
}

expect {
	run = target_for(windows).map_ok(|target| host_run(target, Release, Untracked, NoSpans))
	run.map_ok(|r| r.args) == Ok(["build", "engine", "-build-mode:static", "-out:platform/targets/x64win/host.lib", "-no-crt", "-no-thread-local", "-o:speed", "-vet", "-strict-style"])
}

expect target_for(linux).map_ok(|target| target.host_flags) == Ok([])

expect {
	run = target_for(mac).map_ok(|target| game_run(target, "examples/cards", "cards"))
	run == Ok({ program: "roc", args: ["build", "--target=arm64mac", "--output=./cards.bin", "main.roc"], cwd: "examples/cards" })
}

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
expect target_for(windows).map_ok(clay_copies) == Ok([{ from: "clay/bindings/odin/clay-odin/windows/clay.lib", to: "platform/targets/x64win/clay.lib" }])

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
expect target_for(linux).map_ok(|target| target.extra_inputs) == Ok(LinuxStubs)
expect target_for(windows).map_ok(|target| target.extra_inputs) == Ok(WindowsImportLibs)

expect {
	# The Linux image mounts the checkout, so the Mac binary must survive a Linux build.
	out = target_for(linux).map_ok(|target| game_run(target, "examples/entity-game", "entity-game").args.get(2))
	out == Ok(Ok("--output=./entity-game_linux.bin"))
}

expect {
	copy = target_for(mac).map_ok(|target| compiler_rt_copy("/Xcode/usr/lib/clang/21", target))
	copy == Ok({ from: "/Xcode/usr/lib/clang/21/lib/darwin/libclang_rt.osx.a", to: "platform/targets/arm64mac/libclang_rt.osx.a" })
}

expect parse(["keys"]) == Ok([Keys])

expect parse(["target"]) == Ok([Target])
expect target_for(mac).map_ok(target_lines) == Ok("target=arm64mac\nsuffix=.bin\nhost_lib=platform/targets/arm64mac/libhost.a")
expect target_for(linux).map_ok(target_lines) == Ok("target=x64glibc\nsuffix=_linux.bin\nhost_lib=platform/targets/x64glibc/libhost.a")
expect target_for(windows).map_ok(target_lines) == Ok("target=x64win\nsuffix=.exe\nhost_lib=platform/targets/x64win/host.lib")

expect {
	planned = target_for(mac).map_ok(|target| bench_run(target, { game: "model-size", n: 64 }, "/repo"))
	planned
		== Ok({
			run: { program: "/repo/bench/model-size/model-size.bin", args: ["64"], cwd: "bench/model-size" },
			env: [("ROCCO_HEADLESS", "1"), ("ROCCO_EXIT_AFTER_FRAMES", "2120"), ("ROCCO_SPANS_CSV", "/repo/bench/out/model-size-64.csv")],
		})
}

expect {
	meta = target_for(mac).map_ok(|target| bench_meta(target, { game: "model-size", n: 64 }, "abc123"))
	match meta {
		Ok(text) =>
			Str.contains(text, "\"n\": 64,")
				and Str.contains(text, "\"git_hash\": \"abc123\",")
					and Str.contains(text, "\"odin_debug\": false,")
						and Str.contains(text, "\"-define:ROCCO_SPANS=true\"")
		Err(_) => Bool.False
	}
}
