import pf.Cmd
import pf.OsStr
import pf.Sleep
import pf.Stderr
import pf.Stdout

CiWait := [].{
	usage =
		\\usage: roc scripts/tools.roc ci-wait [<run id>] [--interval <seconds>] [--start-wait <seconds>]
		\\
		\\Waits for the CI runs of HEAD, or for one run. It prints one line each
		\\time a job changes state. When a job fails, it prints the failed step and
		\\the end of its output as soon as that job ends.
		\\
		\\  --interval     seconds between polls (default 30)
		\\  --start-wait   seconds to wait for a run of HEAD to appear (default 120)
		\\
		\\Exit status: 0 when every job passed, 1 when a job failed or was
		\\cancelled, 2 when gh failed. It needs gh, logged in. The job logs come
		\\from a host other than api.github.com, so a sandbox must allow it too.

	Options : { target : [Head, Run(U64)], interval : U64, start_wait : U64 }

	parse : List(Str) -> Try(Options, [Usage])
	parse = |args| parse_from(args, { target: Head, interval: 30, start_wait: 120 })

	run! : Options => Try({}, [Exit(I32)])
	run! = |options| match wait!(options) {
		Ok(Passing) => Ok({})
		Ok(Failing) => Err(Exit(1))
		Err(GhFailed(message)) => {
			Stderr.line!(message) ?? {}
			Err(Exit(2))
		}
		Err(other) => {
			Stderr.line!("ci-wait: ${Str.inspect(other)}") ?? {}
			Err(Exit(2))
		}
	}
}

# The JSON that gh prints. decode_run turns a GhRun into a RunState.
GhStep : { name : Str, status : Str }

GhJob : { name : Str, status : Str, conclusion : Str, databaseId : U64, url : Str, steps : List(GhStep) }

GhRun : { status : Str, conclusion : Str, url : Str, jobs : List(GhJob) }

RunSummary : { databaseId : U64, workflowName : Str }

# Failed has a failed step to show. Stopped, such as a cancelled job, has none.
Outcome : [Passed, Failed, Stopped]

# label is the state as the wait prints it, such as "in_progress (Build)".
Job : { name : Str, databaseId : U64, url : Str, label : Str, progress : [Running, Finished(Outcome)] }

RunState : { conclusion : Str, url : Str, progress : [Running, Finished([Passed, Failed])], jobs : List(Job) }

WatchedRun : { id : U64, workflow : Str }

# What the wait has printed so far. seen holds the last label printed for
# each job, and reported the jobs whose failure was printed.
Watch : { seen : Dict(Str, Str), reported : List(Str), verdict : [Passing, Failing] }

Event : [Line(Str), JobFailed(Job)]

start : Watch
start = { seen: Dict.empty(), reported: [], verdict: Passing }

# Takes one poll of a run and gives what to print, in order.
observe : Watch, { run : WatchedRun, state : RunState } -> { watch : Watch, events : List(Event) }
observe = |watch, { run, state }| {
	var $seen = watch.seen
	var $reported = watch.reported
	var $verdict = watch.verdict
	var $events = []
	for job in state.jobs {
		key = "${run.id.to_str()}/${job.name}"
		if $seen.get(key) != Ok(job.label) {
			$seen = $seen.insert(key, job.label)
			$events = $events.append(Line("${run.workflow} / ${job.name}: ${job.label}"))
		}
		match job.progress {
			Finished(Failed) => {
				$verdict = Failing
				if !$reported.contains(key) {
					$reported = $reported.append(key)
					$events = $events.append(JobFailed(job))
				}
			}
			Finished(Stopped) => {
				$verdict = Failing
			}
			Finished(Passed) | Running => {}
		}
	}
	match state.progress {
		Finished(outcome) => {
			$events = $events.append(Line("${run.workflow}: ${state.conclusion} ${state.url}"))
			if outcome == Failed {
				$verdict = Failing
			}
		}
		Running => {}
	}
	{ watch: { seen: $seen, reported: $reported, verdict: $verdict }, events: $events }
}

decode_run : GhRun -> RunState
decode_run = |gh_run| {
	progress = if (gh_run.status != "completed") Running else if (gh_run.conclusion == "success") Finished(Passed) else Finished(Failed)
	{ conclusion: gh_run.conclusion, url: gh_run.url, progress, jobs: gh_run.jobs.map(decode_job) }
}

decode_job : GhJob -> Job
decode_job = |gh_job| {
	(label, progress) =
		if gh_job.status == "completed" {
			(if (gh_job.conclusion == "") "completed" else gh_job.conclusion, Finished(job_outcome(gh_job.conclusion)))
		} else {
			match gh_job.steps.find_first(|step| step.status == "in_progress") {
				Ok(step) => ("${gh_job.status} (${step.name})", Running)
				Err(_) => (gh_job.status, Running)
			}
		}
	{ name: gh_job.name, databaseId: gh_job.databaseId, url: gh_job.url, label, progress }
}

# A cancelled job stopped because of another job or a newer push.
job_outcome : Str -> Outcome
job_outcome = |conclusion| match conclusion {
	"success" | "skipped" => Passed
	"failure" | "timed_out" | "startup_failure" => Failed
	_ => Stopped
}

runs_to_wait_for : List(RunSummary) -> Try(List(WatchedRun), [CiNotStarted])
runs_to_wait_for = |runs|
	if (runs.any(|run| run.workflowName == ci_workflow))
		Ok(runs.map(|run| { id: run.databaseId, workflow: run.workflowName }))
	else
		Err(CiNotStarted)

# The first failed step of a job log: its name and the last tail lines of
# its output.
failure_excerpt : Str, { tail : U64 } -> Try(Str, [NoErrorLine])
failure_excerpt = |log, { tail }| {
	var $step = "unknown"
	var $output = []
	for line in log.split_on("\n").map(clean_log_line) {
		if line.starts_with(step_start) {
			$step = line.drop_prefix(step_start)
			$output = []
		} else if line.starts_with(group_end) {
			$output = []
		} else if line.starts_with(error_start) {
			kept = $output.keep_if(|text| text.trim() != "")
			body = kept.take_last(tail).append(line.drop_prefix(error_start))
			return Ok(Str.join_with(List.join([["Failed step: ${$step}"], body.map(|text| "  ${text}")]), "\n"))
		} else {
			$output = $output.append(line)
		}
	}
	Err(NoErrorLine)
}

# The name in .github/workflows/ci.yml. Other workflows, such as "Grow the
# site", often start first and end sooner.
ci_workflow = "CI"

head_poll_seconds = 10

parse_from : List(Str), CiWait.Options -> Try(CiWait.Options, [Usage])
parse_from = |args, options| match args {
	[] => Ok(options)
	["--interval", value, .. as rest] => parse_from(rest, { ..options, interval: U64.from_str(value) ? |_| Usage })
	["--start-wait", value, .. as rest] => parse_from(rest, { ..options, start_wait: U64.from_str(value) ? |_| Usage })
	[word, .. as rest] if options.target == Head => parse_from(rest, { ..options, target: Run(U64.from_str(word) ? |_| Usage) })
	_ => Err(Usage)
}

wait! : CiWait.Options => Try([Passing, Failing], _)
wait! = |options| {
	var $pending = match options.target {
		Run(id) => {
			summary : { workflowName : Str }
			summary = Json.parse(read_gh_text!(["run", "view", id.to_str(), "--json", "workflowName"])?) ? |_| GhFailed("gh run view ${id.to_str()}: unexpected JSON")
			[{ id, workflow: summary.workflowName }]
		}
		Head => find_head_runs!(options.start_wait)?
	}
	var $watch = start
	while !$pending.is_empty() {
		var $running = []
		for run in $pending {
			id = run.id.to_str()
			gh_run : GhRun
			gh_run = Json.parse(read_gh_text!(["run", "view", id, "--json", "status,conclusion,url,jobs"])?) ? |_| GhFailed("gh run view ${id}: unexpected JSON")
			state = decode_run(gh_run)
			polled = observe($watch, { run, state })
			$watch = polled.watch
			for event in polled.events {
				match event {
					Line(text) => Stdout.line!(text)?
					JobFailed(job) => print_failure!(job)?
				}
			}
			if state.progress == Running {
				$running = $running.append(run)
			}
		}
		$pending = $running
		if !$pending.is_empty() {
			Sleep.millis!(options.interval * 1000)?
		}
	}
	Ok($watch.verdict)
}

find_head_runs! : U64 => Try(List(WatchedRun), _)
find_head_runs! = |start_wait| {
	sha = Cmd.new("git").args(["rev-parse", "HEAD"]).capture!()?.trim()
	var $waited = 0
	while $waited <= start_wait {
		runs : List(RunSummary)
		runs = Json.parse(read_gh_text!(["run", "list", "--commit", sha, "--json", "databaseId,workflowName"])?) ? |_| GhFailed("gh run list: unexpected JSON")
		match runs_to_wait_for(runs) {
			Ok(pending) => return Ok(pending)
			Err(CiNotStarted) => {}
		}
		Sleep.millis!(head_poll_seconds * 1000)?
		$waited = $waited + head_poll_seconds
	}
	short_sha = Str.from_utf8_lossy(sha.to_utf8().take_first(7))
	Err(GhFailed("no ${ci_workflow} run started for ${short_sha} within ${start_wait.to_str()}s. Was it pushed?"))
}

print_failure! : Job => Try({}, _)
print_failure! = |job| {
	Stdout.line!("--- ${job.name} failed: ${job.url}")?
	match run_gh!(["api", "--allow-escape-sequences", "repos/{owner}/{repo}/actions/jobs/${job.databaseId.to_str()}/logs"]) {
		Ok(output) => match failure_excerpt(output.stdout_utf8_lossy(), { tail: 40 }) {
			Ok(excerpt) => Stdout.line!(excerpt)
			Err(NoErrorLine) => Stdout.line!("The log has no ##[error] line.")
		}
		Err(GhFailed(message)) => Stdout.line!("Could not read the job log. ${message}")
	}
}

run_gh! : List(Str) => Try(Cmd.Output, [GhFailed(Str)])
run_gh! = |args| {
	command = "gh ${Str.join_with(args, " ")}"
	output = Cmd.new("gh").args(args.map(OsStr.from_str)).run!() ? |err| GhFailed("${command}: ${Str.inspect(err)}")
	match output.status {
		Exited(0) => Ok(output)
		_ => Err(GhFailed("${command}: ${output.stderr_utf8_lossy().trim()}"))
	}
}

read_gh_text! : List(Str) => Try(Str, [GhFailed(Str)])
read_gh_text! = |args| match run_gh!(args)?.stdout_utf8() {
	Ok(text) => Ok(text)
	Err(BadUtf8(_)) => Err(GhFailed("gh ${Str.join_with(args, " ")}: the output is not UTF-8"))
}

step_start = "##[group]Run "

group_end = "##[endgroup]"

error_start = "##[error]"

csi = "\u(1b)["

clean_log_line : Str -> Str
clean_log_line = |line| strip_ansi(drop_timestamp(line.drop_suffix("\r")))

# Drops a leading "2026-11-06T21:14:59.5800020Z " that GitHub puts on each line.
drop_timestamp : Str -> Str
drop_timestamp = |line| {
	bytes = line.to_utf8()
	stamp_length = match bytes {
		[y1, y2, y3, y4, '-', m1, m2, '-', d1, d2, 'T', .. as rest] if [y1, y2, y3, y4, m1, m2, d1, d2].all(is_digit) => {
			clock = rest.find_first_index(|byte| !(is_digit(byte) or byte == ':' or byte == '.')) ?? rest.len()
			match rest.drop_first(clock) {
				['Z', ' ', ..] if clock > 0 => 11 + clock + 2
				['Z', ..] if clock > 0 => 11 + clock + 1
				_ => 0
			}
		}
		_ => 0
	}
	Str.from_utf8_lossy(bytes.drop_first(stamp_length))
}

# Drops each ANSI sequence of the form ESC [ digits-and-semicolons letter.
strip_ansi : Str -> Str
strip_ansi = |text| {
	pieces = text.split_on(csi)
	after_escapes = pieces.drop_first(1).map(
		|piece| {
			bytes = piece.to_utf8()
			params = bytes.find_first_index(|byte| !(is_digit(byte) or byte == ';')) ?? bytes.len()
			match bytes.get(params) {
				Ok(final) if is_letter(final) => Str.from_utf8_lossy(bytes.drop_first(params + 1))
				_ => "${csi}${piece}"
			}
		},
	)
	Str.join_with(List.join([pieces.take_first(1), after_escapes]), "")
}

is_digit : U8 -> Bool
is_digit = |byte| byte >= '0' and byte <= '9'

is_letter : U8 -> Bool
is_letter = |byte| (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z')

sample_log =
	\\2026-11-06T21:14:59.5800020Z ##[group]Run sh scripts/macos/build-miniaudio.sh
	\\2026-11-06T21:14:59.5844440Z ##[endgroup]
	\\2026-11-06T21:15:05.6000000Z == miniaudio archive
	\\2026-11-06T21:15:05.6108760Z ##[group]Run roc scripts/build.roc all --release
	\\2026-11-06T21:15:05.6109130Z ${ansi_cyan}roc scripts/build.roc all --release${ansi_reset}
	\\2026-11-06T21:15:05.6151780Z shell: /bin/bash -e {0}
	\\2026-11-06T21:15:05.6154610Z ##[endgroup]
	\\2026-11-06T21:15:28.4193460Z == roc build --target=arm64mac --output=./cards.bin main.roc
	\\2026-11-06T21:15:29.1726160Z ld64.lld: error: undefined symbol: _snprintf
	\\2026-11-06T21:15:29.1730330Z >>> did you mean: _vsnprintf
	\\2026-11-06T21:15:29.1752370Z
	\\2026-11-06T21:15:29.1781060Z build: roc exited with 1
	\\2026-11-06T21:15:29.1991920Z ##[error]Process completed with exit code 1.
	\\2026-11-06T21:15:29.2272910Z ##[group]Run actions/upload-artifact@v4
	\\2026-11-06T21:15:29.2275910Z ##[endgroup]

ansi_cyan = "\u(1b)[36;1m"

ansi_reset = "\u(1b)[0m"

## The excerpt names the failed step and keeps its output.
expect {
	expected =
		\\Failed step: roc scripts/build.roc all --release
		\\  == roc build --target=arm64mac --output=./cards.bin main.roc
		\\  ld64.lld: error: undefined symbol: _snprintf
		\\  >>> did you mean: _vsnprintf
		\\  build: roc exited with 1
		\\  Process completed with exit code 1.
	failure_excerpt(sample_log, { tail: 40 }) == Ok(expected)
}

## The excerpt keeps only the tail of a long step.
expect {
	expected =
		\\Failed step: roc scripts/build.roc all --release
		\\  build: roc exited with 1
		\\  Process completed with exit code 1.
	failure_excerpt(sample_log, { tail: 1 }) == Ok(expected)
}

## A log with no error line has no excerpt.
expect failure_excerpt(sample_log.replace_each("##[error]", ""), { tail: 40 }) == Err(NoErrorLine)

## A running job is labelled with its active step.
expect {
	gh_job = {
		name: "macos",
		status: "in_progress",
		conclusion: "",
		databaseId: 1,
		url: "",
		steps: [{ name: "Build", status: "completed" }, { name: "Run the games", status: "in_progress" }],
	}
	decode_job(gh_job).label == "in_progress (Run the games)"
}

## A finished job is labelled with its conclusion.
expect decode_job({ name: "macos", status: "completed", conclusion: "failure", databaseId: 1, url: "u", steps: [] }) == { name: "macos", databaseId: 1, url: "u", label: "failure", progress: Finished(Failed) }

## Only failure, timed_out and startup_failure have a failed step to show.
expect {
	actual =
		\\success: ${Str.inspect(job_outcome("success"))}
		\\skipped: ${Str.inspect(job_outcome("skipped"))}
		\\failure: ${Str.inspect(job_outcome("failure"))}
		\\timed_out: ${Str.inspect(job_outcome("timed_out"))}
		\\startup_failure: ${Str.inspect(job_outcome("startup_failure"))}
		\\cancelled: ${Str.inspect(job_outcome("cancelled"))}
		\\neutral: ${Str.inspect(job_outcome("neutral"))}
	expected =
		\\success: Passed
		\\skipped: Passed
		\\failure: Failed
		\\timed_out: Failed
		\\startup_failure: Failed
		\\cancelled: Stopped
		\\neutral: Stopped
	actual == expected
}

## A run passes only when its conclusion is success.
expect {
	finished = |conclusion| decode_run({ status: "completed", conclusion, url: "", jobs: [] }).progress
	actual =
		\\success: ${Str.inspect(finished("success"))}
		\\skipped: ${Str.inspect(finished("skipped"))}
		\\running: ${Str.inspect(decode_run({ status: "in_progress", conclusion: "", url: "", jobs: [] }).progress)}
	expected =
		\\success: Finished(Passed)
		\\skipped: Finished(Failed)
		\\running: Running
	actual == expected
}

## Waits for the CI run when another workflow starts first.
expect runs_to_wait_for([{ databaseId: 1, workflowName: "Grow the site" }]) == Err(CiNotStarted)

## Waits for every run once the CI run has started.
expect {
	runs = [{ databaseId: 1, workflowName: "Grow the site" }, { databaseId: 2, workflowName: "CI" }]
	runs_to_wait_for(runs) == Ok([{ id: 1, workflow: "Grow the site" }, { id: 2, workflow: "CI" }])
}

## Waits while no run has started.
expect runs_to_wait_for([]) == Err(CiNotStarted)

sample_job : { name : Str, label : Str, progress : [Running, Finished(Outcome)] } -> Job
sample_job = |{ name, label, progress }| { name, label, progress, databaseId: 7, url: "https://jobs/7" }

running_run : List(Job) -> RunState
running_run = |jobs| { conclusion: "", url: "https://runs/2", progress: Running, jobs }

ci_run = { id: 2, workflow: "CI" }

## A poll prints a line for each job whose label changed since the last poll.
expect {
	macos = sample_job({ name: "macos", label: "in_progress", progress: Running })
	first = observe(start, { run: ci_run, state: running_run([macos, sample_job({ name: "linux", label: "queued", progress: Running })]) })
	second = observe(first.watch, { run: ci_run, state: running_run([macos, sample_job({ name: "linux", label: "in_progress", progress: Running })]) })
	actual =
		\\first: ${Str.inspect(first.events)}
		\\second: ${Str.inspect(second.events)}
	expected =
		\\first: [Line("CI / macos: in_progress"), Line("CI / linux: queued")]
		\\second: [Line("CI / linux: in_progress")]
	actual == expected
}

## A failed job is reported once and fails the wait.
expect {
	failed = sample_job({ name: "macos", label: "failure", progress: Finished(Failed) })
	first = observe(start, { run: ci_run, state: running_run([failed]) })
	second = observe(first.watch, { run: ci_run, state: running_run([failed]) })
	actual =
		\\first: ${Str.inspect(first.events)}
		\\second: ${Str.inspect(second.events)}
		\\verdict: ${Str.inspect(second.watch.verdict)}
	expected =
		\\first: ${Str.inspect([Line("CI / macos: failure"), JobFailed(failed)])}
		\\second: []
		\\verdict: Failing
	actual == expected
}

## A stopped job fails the wait, but has no failed step to report.
expect {
	polled = observe(start, { run: ci_run, state: running_run([sample_job({ name: "macos", label: "cancelled", progress: Finished(Stopped) })]) })
	actual =
		\\events: ${Str.inspect(polled.events)}
		\\verdict: ${Str.inspect(polled.watch.verdict)}
	expected =
		\\events: [Line("CI / macos: cancelled")]
		\\verdict: Failing
	actual == expected
}

## A passed job does not fail the wait.
expect observe(start, { run: ci_run, state: running_run([sample_job({ name: "tour", label: "skipped", progress: Finished(Passed) })]) }).watch.verdict == Passing

## A finished run prints its conclusion, and its outcome decides the verdict.
expect {
	state = { conclusion: "failure", url: "https://runs/2", progress: Finished(Failed), jobs: [] }
	polled = observe(start, { run: ci_run, state })
	actual =
		\\events: ${Str.inspect(polled.events)}
		\\verdict: ${Str.inspect(polled.watch.verdict)}
	expected =
		\\events: [Line("CI: failure https://runs/2")]
		\\verdict: Failing
	actual == expected
}

## With no arguments it waits for HEAD with the default timings.
expect CiWait.parse([]) == Ok({ target: Head, interval: 30, start_wait: 120 })

## A run id and both options parse in any order.
expect CiWait.parse(["--interval", "5", "42", "--start-wait", "60"]) == Ok({ target: Run(42), interval: 5, start_wait: 60 })

## A second run id, a bad number and an unknown option are usage errors.
expect {
	actual =
		\\two ids: ${Str.inspect(CiWait.parse(["1", "2"]))}
		\\bad interval: ${Str.inspect(CiWait.parse(["--interval", "soon"]))}
		\\missing value: ${Str.inspect(CiWait.parse(["--interval"]))}
		\\unknown option: ${Str.inspect(CiWait.parse(["--verbose"]))}
	expected =
		\\two ids: Err(Usage)
		\\bad interval: Err(Usage)
		\\missing value: Err(Usage)
		\\unknown option: Err(Usage)
	actual == expected
}
