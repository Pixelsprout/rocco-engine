app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst", roc: "0.1.0-RC2" }

import pf.OsStr
import pf.Stderr
import CiWait

Tool : [CiWait(CiWait.Options)]

usage =
	\\usage: roc scripts/tools.roc <tool> [<args>]
	\\
	\\Tools:
	\\  ci-wait   Wait for CI and print the output of each failed step.
	\\
	\\Run from the repository root.

parse : List(Str) -> Try(Tool, [Usage(Str)])
parse = |args| match args {
	["ci-wait", .. as rest] => match CiWait.parse(rest) {
		Ok(options) => Ok(CiWait(options))
		Err(Usage) => Err(Usage(CiWait.usage))
	}
	_ => Err(Usage(usage))
}

main! : List(OsStr) => Try({}, [Exit(I32)])
main! = |args| match parse(args.map(OsStr.display)) {
	Ok(CiWait(options)) => CiWait.run!(options)
	Err(Usage(text)) => {
		Stderr.line!(text) ?? {}
		Err(Exit(2))
	}
}

## A tool name with bad arguments gives that tool's usage.
expect parse(["ci-wait", "--verbose"]) == Err(Usage(CiWait.usage))

## An unknown tool gives the list of tools.
expect parse(["deploy"]) == Err(Usage(usage))
