# The helpers that every bench game shares. Config and Input copy
# pf.Vocabulary. Keep them identical, or init and step stop unifying.
Bench := [].{
	Config : { seed : U64, assets : List(Str), args : List(Str) }
	Input : { held : List(U16), pressed : List(U16), mouse : { dx : F32, dy : F32 } }

	# N is the first Arg. A missing or bad N must stop the run, so a typo cannot
	# give a benchmark at the wrong size.
	n_arg : List(Str) -> Try(U64, [BadCount])
	n_arg = |args| match args.first() {
		Ok(word) =>
			match U64.from_str(word) {
				Ok(n) if n > 0 => Ok(n)
				_ => Err(BadCount)
			}
		Err(_) => Err(BadCount)
	}

	# The draws capacity for a game that draws N Draws. A missing or bad N gives
	# the default, because init stops that run.
	draws_for_n : List(Str), U32 -> U32
	draws_for_n = |args, default| match n_arg(args) {
		Ok(n) =>
			match n.to_u32_try() {
				Ok(draws) => draws
				Err(_) => default
			}
		Err(BadCount) => default
	}

	# The Odin twins use the same generator and spread, so the golden files match.
	next_rng : U64 -> U64
	next_rng = |s| s.times_wrap(6364136223846793005).plus_wrap(1)

	# A value in [-limit, limit) from the top bits of the generator state.
	spread : U64, F32 -> F32
	spread = |s, limit| ((s.shr_zf_wrap(40) % 1000).to_f32() / 500.0 - 1.0) * limit

	no_args : Config
	no_args = { seed: 0, assets: [], args: [] }

	with_n : U64 -> Config
	with_n = |n| { ..no_args, args: [n.to_str()] }

	idle : Input
	idle = { held: [], pressed: [], mouse: { dx: 0.0, dy: 0.0 } }

	counts_up : List(U64) -> Bool
	counts_up = |ids| ids.map_with_index(|id, i| id == i).all(|ok| ok)
}

expect Bench.n_arg(["64"]) == Ok(64)
expect Bench.n_arg(["16384", "extra"]) == Ok(16384)
expect Bench.n_arg([]) == Err(BadCount)
expect Bench.n_arg(["0"]) == Err(BadCount)
expect Bench.n_arg(["-3"]) == Err(BadCount)
expect Bench.n_arg(["many"]) == Err(BadCount)

expect Bench.draws_for_n(["64"], 16384) == 64
expect Bench.draws_for_n(["20000"], 16384) == 20000
expect Bench.draws_for_n([], 16384) == 16384
expect Bench.draws_for_n(["many"], 16384) == 16384

expect Bench.with_n(64).args == ["64"]

expect Bench.counts_up([0, 1, 2]) and !Bench.counts_up([1, 2])

expect {
	values = [1, 2, 3, 4, 5].map(|s| Bench.spread(Bench.next_rng(s), 4.0))
	values.all(|v| v >= -4.0 and v < 4.0)
}
