# A Roc file marks a region with "# region: <name>" and "# endregion" lines.
# A page marks the place for it with "<!-- region: <path>#<name> -->" and
# "<!-- endregion -->" lines around a fenced block. The path is from the
# repository root.
Regions := [].{
	RegionErr : { page : Str, region : Str, problem : [MissingFile, MissingRegion, UnclosedInSource, UnclosedInPage, NoRegionName] }

	# stale names each region whose block in the page differed from its source.
	Filled : { text : Str, stale : List(Str) }

	page_start : Str
	page_start = "<!-- region:"

	page_end : Str
	page_end = "<!-- endregion -->"

	source_end : Str
	source_end = "# endregion"

	# The files a page takes regions from, each once, so the caller can read them.
	refs : Str -> List(Str)
	refs = |page_text| {
		var $paths = []
		for line in Str.split_on(page_text, "\n") {
			match marker_ref(line) {
				Ok(ref) => {
					path = split_ref(ref).path
					if !$paths.contains(path) {
						$paths = $paths.append(path)
					}
				}
				Err(_) => {}
			}
		}
		$paths
	}

	# sources pairs each path that exists with its text. A path not in sources is a missing file.
	fill : Str, Str, List((Str, Str)) -> Try(Filled, RegionErr)
	fill = |page, text, sources| {
		var $out = []
		var $stale = []
		var $open = Closed
		for line in Str.split_on(text, "\n") {
			match $open {
				Open({ ref, body }) =>
					if Str.trim(line) == page_end {
						block = region_block(page, ref, sources)?
						if block != body {
							$stale = $stale.append(ref)
						}
						$out = $out.concat(block).append(line)
						$open = Closed
					} else if marker_ref(line).is_ok() {
						return Err({ page, region: ref, problem: UnclosedInPage })
					} else {
						$open = Open({ ref, body: body.append(line) })
					}
				Closed => {
					$out = $out.append(line)
					match marker_ref(line) {
						Ok(ref) => {
							$open = Open({ ref, body: [] })
						}
						Err(_) => {}
					}
				}
			}
		}
		match $open {
			Open({ ref, .. }) => Err({ page, region: ref, problem: UnclosedInPage })
			Closed => Ok({ text: Str.join_with($out, "\n"), stale: $stale })
		}
	}

	message : RegionErr -> Str
	message = |err| {
		{ path, name } = split_ref(err.region)
		detail = match err.problem {
			MissingFile => "${path} does not exist."
			MissingRegion => "${path} has no \"# region: ${name}\" line."
			UnclosedInSource => "${path} has no \"${source_end}\" line after \"# region: ${name}\"."
			UnclosedInPage => "the page has no \"${page_end}\" line after the marker."
			NoRegionName => "the marker names no region. Write <!-- region: <path>#<name> -->."
		}
		"${err.page}: region ${err.region}: ${detail}"
	}

	marker_ref : Str -> Try(Str, [NotMarker])
	marker_ref = |line| {
		trimmed = Str.trim(line)
		if Str.starts_with(trimmed, page_start) and Str.ends_with(trimmed, "-->") and trimmed != page_end {
			Ok(Str.trim(Str.drop_suffix(Str.drop_prefix(trimmed, page_start), "-->")))
		} else {
			Err(NotMarker)
		}
	}

	split_ref : Str -> { path : Str, name : Str }
	split_ref = |ref| match Str.split_first(ref, "#") {
		Ok({ before, after }) => { path: before, name: after }
		Err(_) => { path: ref, name: "" }
	}

	# The lines that go between the page markers: the region in a fenced block.
	region_block : Str, Str, List((Str, Str)) -> Try(List(Str), RegionErr)
	region_block = |page, ref, sources| {
		{ path, name } = split_ref(ref)
		fail = |problem| Err({ page, region: ref, problem })
		if name == "" {
			return fail(NoRegionName)
		}
		source = match sources.find_first(|(p, _)| p == path) {
			Ok((_, found)) => found
			Err(_) => return fail(MissingFile)
		}
		lines = Str.split_on(source, "\n")
		start = "# region: ${name}"
		after = match lines.find_first_index(|line| Str.trim(line) == start) {
			Ok(i) => lines.drop_first(i + 1)
			Err(_) => return fail(MissingRegion)
		}
		body = match after.find_first_index(|line| Str.trim(line) == source_end) {
			Ok(j) => trim_blank_lines(after.take_first(j))
			Err(_) => return fail(UnclosedInSource)
		}
		Ok(["```roc"].concat(body).append("```"))
	}

	trim_blank_lines : List(Str) -> List(Str)
	trim_blank_lines = |lines| {
		is_blank = |line| Str.trim(line) == ""
		lead = lines.find_first_index(|line| !is_blank(line)) ?? lines.len()
		rest = lines.drop_first(lead)
		match rest.find_last_index(|line| !is_blank(line)) {
			Ok(last) => rest.take_first(last + 1)
			Err(_) => []
		}
	}
}

game_source : Str
game_source =
	\\app [main] {}
	\\
	\\# region: launch
	\\launch = |_config| Launch.default
	\\# endregion
	\\
	\\other = 1
	\\

game_sources : List((Str, Str))
game_sources = [("examples/game/main.roc", game_source)]

current_page : Str
current_page =
	\\# Install
	\\
	\\<!-- region: examples/game/main.roc#launch -->
	\\```roc
	\\launch = |_config| Launch.default
	\\```
	\\<!-- endregion -->
	\\
	\\The end.
	\\

stale_page : Str
stale_page =
	\\# Install
	\\
	\\<!-- region: examples/game/main.roc#launch -->
	\\```roc
	\\launch = |_config| Launch.old
	\\```
	\\<!-- endregion -->
	\\
	\\The end.
	\\

expect Regions.refs(current_page) == ["examples/game/main.roc"]
expect Regions.refs("<!-- region: a.roc#x -->\n<!-- endregion -->\n<!-- region: a.roc#y -->\n<!-- endregion -->\n<!-- region: b.roc#z -->\n<!-- endregion -->") == ["a.roc", "b.roc"]
expect Regions.refs("No regions here.\n") == []

expect Regions.fill("guide/install.md", current_page, game_sources) == Ok({ text: current_page, stale: [] })
expect Regions.fill("guide/install.md", stale_page, game_sources) == Ok({ text: current_page, stale: ["examples/game/main.roc#launch"] })

# An empty block gets its fence on the first fill.
expect {
	empty = "<!-- region: examples/game/main.roc#launch -->\n<!-- endregion -->\n"
	filled = Regions.fill("guide/a.md", empty, game_sources)
	filled == Ok({ text: "<!-- region: examples/game/main.roc#launch -->\n```roc\nlaunch = |_config| Launch.default\n```\n<!-- endregion -->\n", stale: ["examples/game/main.roc#launch"] })
}

# Blank lines at the edges of a region stay out of the block, and the indent stays.
expect {
	source = "# region: body\n\n\tx = 1\n\n\ty = 2\n\n# endregion\n"
	page = "<!-- region: a.roc#body -->\n<!-- endregion -->"
	Regions.fill("p.md", page, [("a.roc", source)]).map_ok(|f| f.text) == Ok("<!-- region: a.roc#body -->\n```roc\n\tx = 1\n\n\ty = 2\n```\n<!-- endregion -->")
}

expect Regions.fill("p.md", "  <!-- region: examples/game/main.roc#launch -->\n```roc\n```\n  <!-- endregion -->", game_sources).map_ok(|f| f.stale) == Ok(["examples/game/main.roc#launch"])

expect {
	err = { page: "guide/install.md", region: "examples/game/main.roc#start", problem: MissingRegion }
	page = "<!-- region: examples/game/main.roc#start -->\n<!-- endregion -->\n"
	text = Regions.message(err)
	Regions.fill("guide/install.md", page, game_sources) == Err(err)
		and Str.contains(text, "guide/install.md")
			and Str.contains(text, "examples/game/main.roc#start")
}

expect {
	err = { page: "guide/install.md", region: "examples/gone/main.roc#launch", problem: MissingFile }
	page = "<!-- region: examples/gone/main.roc#launch -->\n<!-- endregion -->\n"
	text = Regions.message(err)
	Regions.fill("guide/install.md", page, game_sources) == Err(err)
		and Str.contains(text, "guide/install.md")
			and Str.contains(text, "examples/gone/main.roc#launch")
				and Str.contains(text, "does not exist")
}

expect {
	err = { page: "guide/install.md", region: "examples/game/main.roc#launch", problem: UnclosedInPage }
	page = "<!-- region: examples/game/main.roc#launch -->\n```roc\n```\n"
	text = Regions.message(err)
	Regions.fill("guide/install.md", page, game_sources) == Err(err)
		and Str.contains(text, "guide/install.md")
			and Str.contains(text, "examples/game/main.roc#launch")
				and Str.contains(text, "<!-- endregion -->")
}

expect {
	err = { page: "guide/install.md", region: "a.roc#open", problem: UnclosedInSource }
	page = "<!-- region: a.roc#open -->\n<!-- endregion -->\n"
	text = Regions.message(err)
	Regions.fill("guide/install.md", page, [("a.roc", "# region: open\nx = 1\n")]) == Err(err)
		and Str.contains(text, "guide/install.md")
			and Str.contains(text, "a.roc#open")
				and Str.contains(text, "# endregion")
}

expect {
	err = { page: "guide/install.md", region: "a.roc", problem: NoRegionName }
	page = "<!-- region: a.roc -->\n<!-- endregion -->\n"
	text = Regions.message(err)
	Regions.fill("guide/install.md", page, [("a.roc", "")]) == Err(err)
		and Str.contains(text, "guide/install.md")
			and Str.contains(text, "a.roc")
}

# A second region opened before the first is closed leaves the first unclosed.
expect Regions.fill("p.md", "<!-- region: examples/game/main.roc#launch -->\n<!-- region: examples/game/main.roc#launch -->\n<!-- endregion -->\n", game_sources).map_err(|e| e.problem) == Err(UnclosedInPage)
