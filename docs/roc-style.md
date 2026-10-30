# Roc Style Guide

An opinionated guide to writing Roc: for apps, packages, platforms, and examples.

The [langref](https://roc-lang.org/docs/main/langref/) is the base. This guide goes further, and where it does, it is deliberate. Three things settle a question, in this order:

1. **The type checker.** Write the rule as a type whenever you can.
2. **`roc fmt`.** Its layout is final. Never hand-format against it.
3. **This guide.** For the rules neither of the first two can see.

## Contents

1. [Principles](#principles)
2. [Naming](#naming)
3. [Types and data](#types-and-data)
4. [Function shape](#function-shape)
5. [Well-known methods](#well-known-methods)
6. [Errors](#errors)
7. [Text and bytes](#text-and-bytes)
8. [Effects and purity](#effects-and-purity)
9. [Modules](#modules)
10. [Platforms and the host boundary](#platforms-and-the-host-boundary)
11. [Layout](#layout)
12. [Tests](#tests)

## Principles

- **Prefer a construct that can't be wrong to one that can be wrong and still compile.** A tag over a Bool, an opaque type over a validated `Str`, a record over positional arguments. Most rules below are instances of this.
- **Reduce what a reader must remember.** Count how many other definitions someone must read to know what a line does. Every jump to a helper, every hidden assumption, and every parameter that never varies adds to that count.
- **One home for each rule.** A fact the program depends on (a limit, a check, a format) lives in one place, and everything else asks that place. A second copy that must remember to agree is a bug waiting to happen.
- **A little speed traded for robustness is fine,** especially away from hot loops.

## Naming

The langref's [naming](https://roc-lang.org/docs/main/langref/naming/) page covers the rules the compiler enforces. These are the ones it doesn't.

- **A function returning `Bool` is a question: `is_*` or `has_*`.** A bare adjective (`all_digits`, `valid`) doesn't say which way `True` points.
- **An effect is named for its act: a verb.** `send_message!`, `load_user!`, `write_file!`. Never a noun or a state (`message!`, `sent!`, `member!`), which read as a value or a question.
- **A command is not named as a question.** An effect that does something and reports how it went is named for what it does: `serve_file!` answering `[Served, NotFound]`, not `file_exists!`.
- **Name a tag for what it is: a command, an event, or a state.** A command is an imperative verb, an event is past tense, a state is a noun or adjective. The reader can then tell an instruction from a fact at a glance.

  ```roc
  # A command, passed in:
  Edit : [Pin, Unpin]

  # An event, stored and replayed:
  Change : [Added, Removed]

  # A state:
  Presence : [Online, Offline]
  ```

  A domain's own words stay as they are: HTTP's `NotFound` beside `Redirect` is the protocol's name, not a slip.
- **Vague container words are a smell.** `Entry`, `Item`, `Node`, `Data`, `Info`, `Value`, `Thing` usually stand in for a word the domain already has. Use it: `Header`, `Row`, `Heading`, `Payload`.
- **Prefer a plain word to an abbreviation.** `topic`, not `tid`; `request`, not `req`; `count`, not `n` (outside a tiny lambda).
- **Name an unused argument when the name documents it.** `|_args|` says more than `|_|`. The compiler warns if an `_`-prefixed name is used, so it stays honest.
- **Don't shadow.** The compiler warns; pick a more specific name instead.

## Types and data

### A closed set is a tag union

- **Use a tag union, not a `Bool`, a magic number, or a magic string, for any closed set.** Match on it exhaustively. A tag says which case it is; a `Bool` has to be remembered.
- **Naming the tags forces you to name the question.** When a Bool becomes a tag, rename the field: `online : Bool` becomes `presence : [Online, Offline]`.
- **No optionals.** Don't write `[Some(a), None]`. Name what is there and why it might not be:

  ```roc
  # Not this:
  peek : Parser -> [Some(Str), None]

  # This:
  peek : Parser -> [Grapheme(Str), Eof]
  ```

  `Some` says nothing about what the `Str` is; `Grapheme` does. `None` says only that something is missing; `Eof` says why. The builtins do the same: `List.first` answers `Err(ListWasEmpty)`, not `None`.

  This is about tags. Record [optional fields](https://roc-lang.org/docs/main/langref/records/#optional-fields) (`label ?: Str`) are the right tool when it matters at runtime whether a field was provided, such as JSON. When you just want a value if nobody says, use a defaulted field (`retries : U64 ?? 3`); see [props](#configuration-is-a-props-record).
- **An ordering answers `[Before, Same, After]`**, which is what `List.sort_with` takes. Never a signed number compared against zero.
- **Use `match` when a chain tests one value** against tags, constants, or ranges. Leave an `if` chain alone when its branches test different things in turn.
- **Match the shape you need instead of indexing and defaulting.** A list pattern (`[first, second, ..]`) leaves no impossible case to crash on.

### Records over tuples

- **Use a record when the fields have meaning.** Headers are `{ name : Str, value : Str }`, not `(Str, Str)`. A record names every field where it is built and read, and can't have two same-typed values swapped.
- **A tuple is only for a really temporary pair:** built and destructured within a few lines, never part of a signature someone else reads.
- **No list read by position.** A list of lists whose parts are known only by index becomes a list of records.
- **Let record types document parse targets and response bodies.** A decoded `{ id : U64, name : Str }` is the clearest spec of the payload.

### Nominal and opaque types

`:=` declares a **transparent** nominal type: a distinct name whose backing type everyone can see. `::` declares an **opaque** nominal type: outside its module, nobody can build or unwrap one.

- **Use `:=` where values of the same shape mean different things,** so passing a name where an id belongs is a type error.
- **Use `::` for anything validated.** If only the module's own constructor can build a value, the validator is the only way in, and every value in the program follows the rule.

  ```roc
  Uid :: Str.{
  	from_str : Str -> Try(Uid, [NotAUid])
  	from_str = |text| if (is_all_digits(text)) Ok(Uid.(text)) else Err(NotAUid)

  	to_str : Uid -> Str
  	to_str = |Uid.(text)| text

  	is_eq : _
  	to_hash : _
  }
  ```
- **Decode into the type at the door, once.** The function that reads a request, file, or host answer produces `Uid`, `Email`, `Path`. Nothing deeper takes the raw `Str` and validates it again.
- **A state machine that crosses functions is an opaque type whose module owns the transitions.** Each transition is a function from one state to the next, so a caller can't build a state by hand or skip a step. A two-state tag used inside one function needs none of this.
- **Derive methods with `_`; write one by hand only when the structural answer is wrong.** `is_eq : _`, `to_hash : _`, `parser_for : _`, `encoder_for : _`, `map : _`, `map! : _`. A hand-written structural `is_eq` is more code to read and to get wrong. If you do write `is_eq` by hand and the type is used as a key, write `to_hash` to agree with it: equal values must hash the same.
- **Structured output goes through one builder, never a string spliced by hand.** JSON, HTML, SQL: an opaque type whose only constructors escape what they take, so no caller can forget.

### Name what travels together

- **A function with three or more arguments takes a record.** `roc fmt` won't stack a type annotation, so a long signature stays one long line; a record stacks, names every argument at the call site, and can't be called with two swapped. Either one record, or a subject first and a record of the rest:

  ```roc
  count_while : List(U8), { keep : U8 -> Bool, start : U64 } -> U64

  digits = Bytes.count_while(line, { keep: is_digit, start: 0 })
  ```
- **Neighbouring arguments of the same type get a record,** even when there are only two. Two `Str`s in a row can be swapped and still type-check.
- **Destructure a record argument** when the fields are few and their names are clear: `|{ name, value }| "${name}: ${value}"`.

### Configuration is a props record

- **Configure with a nominal record of defaulted fields,** like props. Required fields have no default; everything else has one, so a caller names only what differs and every call site reads as its own spec. A new option is a new defaulted field, and no existing caller changes.

  ```roc
  Button := {
  	label : Str,
  	width : Length ?? Auto,
  	padding : U32 ?? 8,
  	state : [Enabled, Disabled] ?? Enabled,
  }

  save = button({ label: "Save" })

  cancel = button({ label: "Cancel", width: Fill, state: Disabled })
  ```
- **Props replace builders and option lists for configuration.** Prefer them to a chain of `with_*` setters, to a `List([Width(..), Padding(..)])` of option tags, and to separate `button`, `button_wide`, and `button_disabled` functions.
- **Pass props as the record argument:** the subject first (children, a target) and props beside it, `col({ width: Fill, gap: 12 }, children)`. This is the [3+ arguments](#name-what-travels-together) rule, already satisfied.
- **A default that means "let the platform decide" is a tag** (`Auto`, `Default`, `Inherit`), never a magic `0` or `""`.
- **Defaulted (`??`) by default; optional (`?:`) only when presence matters.** A defaulted field answers "what should this be if nobody says?" An optional field answers "did anybody say?", and that is rarely the question configuration asks. A defaulted field whose type is `[Some(a), None]` is an optional in disguise. Name the absent case for what it means: `on_open : [Idle, Run(state => Action(state))] ?? Idle`.

## Function shape

- **A function boundary must earn its existence.** It names a genuine domain concept, isolates platform fiddliness, eliminates substantial repetition, or makes a pure decision reachable by tests. Nothing else.
- **Inline a helper that is used once and is under 3–4 lines,** or that mostly depends on behaviour defined elsewhere.
- **Don't fracture a coherent linear flow.** Ten readable lines beat five two-line helpers: every helper is another name to remember, another call to jump to, and a name that rarely describes everything its body does. If documenting a helper would take more text than its body, inline it.
- **Don't write a helper that only renames error tags.** Let the unions merge (see [errors](#errors)).
- **Call methods on the receiver:** `items.map(...)`, `items.keep_if(...)`, `name.is_empty()`, `uid.to_str()`. Use the qualified name only where the function is passed as a value (`ids.map(Uid.to_str)`) or for constructors that build a value from parts.
- **Chain transforms instead of numbering intermediate values.** (For configuration, use [props](#configuration-is-a-props-record), not a chain of setters.)

  ```roc
  active_names = |users|
  	users
  		.keep_if(|user| user.active)
  		.map(|user| user.name)
  		.sort_with(by_length)
  ```
- **No braces around a body that is one expression,** one `match`, one `if`, or one record update.
- **Keep short pure helpers compact,** but expand nested `if`/`match` when the one-line version hurts scanning.

### Record builders

- **Combine independent values of one applicative type with a record builder.** `{ a: fa, b: fb }.T` desugars to `T.map2`, so a type that defines `map2 : T(a), T(b), (a, b -> c) -> T(c)` combines any number of fields. Each result is named by its field: no `map3`/`map4` family and no positional tuples.
- **Reach for one when every part can be worked out without the others:** CLI and config parsers, decoders, form validation, signals, collecting several `Try`s at once. The builder can see all the parts, so it can do what `?` can't: report every failure, or build help text from all the options.

  ```roc
  Check(a) := [Valid(a), Invalid(List(Str))].{
  	map2 : Check(a), Check(b), (a, b -> c) -> Check(c)
  	map2 = |left, right, combine| match (left, right) {
  		(Valid(a), Valid(b)) => Valid(combine(a, b))
  		(Invalid(a), Invalid(b)) => Invalid(a.concat(b))
  		(Invalid(a), _) => Invalid(a)
  		(_, Invalid(b)) => Invalid(b)
  	}
  }

  ## Reports every invalid field, not just the first.
  signup = |form| {
  	name: Check.required("name", form.name),
  	email: Check.required("email", form.email),
  	age: Check.at_least(18, form.age),
  }.Check
  ```
- **When a step needs an earlier step's result, it is a sequence, not a builder.** Use `?` in a block.
- **A builder needs at least two fields.** With one, call the function directly.

### Type annotations

- **Annotate every top-level function,** including `main!` and small helpers. The annotation is the reader-facing API.
- **Omit annotations on simple top-level constants** whose type is obvious from the literal.
- **Use `_` in an annotation where spelling the type out would expose plumbing,** most often an error row that just merges what `?` passes up (see [errors](#errors)). Spell it out where it is part of the API.

## Well-known methods

Well-known methods are opt-in hooks for syntax and builtins, not interfaces: each call still resolves to one concrete function. Define one only when it makes the type easier to use without making behaviour surprising. The langref's [table](https://roc-lang.org/docs/main/langref/static-dispatch/#well-known-methods) is the reference; these are the opinions.

- **`to_inspect : T -> Str`** for debug, logging, and test output through `Str.inspect` and `dbg`. Define it when the default inspection isn't the useful one.
- **`to_str : T -> Str` only when the type has one clear user-facing string.** When it has several, name each one: `to_markdown`, `to_plain_text`, `to_html`. Never use `to_str` as serialization; that is `encoder_for`.
- **`is_eq` and `to_hash`: derive them** (`is_eq : _`, `to_hash : _`). Hand-write only when equality isn't structural, and then keep the two consistent.
- **Ordering (`is_lt`, `is_lte`, `is_gt`, `is_gte`) only when the type has one obvious ordering.**
- **Arithmetic (`plus`, `minus`, `times`, `div_by`, `div_trunc_by`, `rem_by`) and unary (`negate`, `not`) only when the operator is the clearest spelling** of the operation and its meaning is unsurprising.
- **Ranges (`range_exclusive_to`, `range_inclusive_to`, `range_iter`, …) only when `..<` and `..=` read naturally** for the type.
- **Literal hooks only when a plain literal should construct the type,** and the conversion is never lossy, contextual, or one of several interpretations. Otherwise write an explicit constructor. A literal hook runs at compile time, so an `Err` is a compile error, which makes it ideal for validated types:

  ```roc
  Port :: U16.{
  	from_numeral : Numeral -> Try(Port, [InvalidNumeral(Str)])
  	from_numeral = |numeral| {
  		n = U16.from_numeral(numeral)?
  		if (n == 0) Err(InvalidNumeral("port 0 is reserved")) else Ok(Port.(n))
  	}
  }

  port : Port
  port = 8080
  ```

  - `from_numeral : Numeral -> Try(T, [InvalidNumeral(Str)])` for number literals.
  - `from_quote : Str -> Try(T, [BadQuotedBytes(Str)])` for string literals.
  - `from_interpolation : List(Str) -> Try((List(item) -> T), [InvalidInterpolation(Str)])` for interpolated literals. The segments are checked at compile time; the returned function decides how runtime values get in (for example, escaping them).
- **`iter : T -> Iter(item)` for collection-like types,** so `for` loops and lazy pipelines work. Collections define `iter`; only iterators define `next`.
- **`parser_for` and `encoder_for` for structured formats.** Derive them when the structural shape is the format.

## Errors

The langref's [errors](https://roc-lang.org/docs/main/langref/errors/) page is the base.

- **A function that can fail returns a `Try`, never a `Bool`.** A `Bool` lets the caller drop the failure, and `?` can't pass it on.
- **Error tags say what went wrong,** with payloads when useful: `[ListWasEmpty]`, `NotFound(path)`. Never a `Str` error; tags stay inspectable and composable.
- **Keep distinct failures apart:** `[Missing, Failed]`, not one `Failed`. As a `Try` they still work with `?` and `??`.
- **Let error unions merge.** Two `?`s with different errors give a function whose error type is the union. Let the compiler infer it, and use `_` in the annotation where the row is plumbing. Don't declare wrapper error types or write functions that just rename tags.
- **Use infix `?` to add context** where the low-level error alone would lose it: `Http.send!(request) ? SendFailed`.
- **Use `??` only at a real boundary** where a fallback value is correct. Never in a parsing path, where it hides invalid input, and never to paper over a case that can't happen.
- **`crash` on the impossible, with a message naming the function and why.** A default for an impossible case hides the bug that causes it. A case that *can* happen (user input, a missing file) keeps an error tag.

  ```roc
  Err(_) => crash "Template.fill: more slots than values"
  ```
- **Never discard a `Try`.** Not with `_ = effect!()`, not with `match effect!() { _ => {} }`. Use `?`, infix `?`, an explicit `match`, or `??` at a boundary. (`_ =` is fine for a value that isn't a failure.)
- **No `Ok(value) = result` unwrapping.** Use `?`, or `match` when the error deserves handling.
- **Write a fallible core and a thin boundary wrapper** when a workflow needs a fallback:

  ```roc
  route : Request -> Response
  route = |request| route_result(request) ?? internal_error_response()
  ```
- **For cleanup-sensitive workflows, capture the result, clean up, then rethrow:**

  ```roc
  main! : List(Str) => Try({}, _)
  main! = |args| {
  	Tty.enable_raw_mode!()?
  	result = game_loop!(args)
  	restored = Tty.disable_raw_mode!()

  	result?
  	restored?
  	Ok({})
  }
  ```

### CLI boundaries

- **Let structured errors bubble to `main!`.** The platform renders unexpected failures with `Str.inspect`, so there's no need to turn every failure into `Exit(1)` or a string.
- **Render human-facing error text in one place,** only where custom text is part of the program, not in scattered print-and-exit branches.

```roc
main! : List(Str) => Try({}, _)
main! = |_args| {
	response = Http.send!(request) ? SendFailed
	decoded = Http.decode_json_response(response) ? DecodeResponseFailed

	Stdout.line!("received: ${Str.inspect(decoded)}")?
	Ok({})
}
```

## Text and bytes

- **Text is a `Str`; bytes exist only at the door.** Decode UTF-8 once, where text enters. Past that point, work in `Str` with its helpers (`split_on`, `join_with`, interpolation). `List(U8)` is for parsers and for bytes that aren't text.
- **Refuse invalid UTF-8:** `Str.from_utf8(bytes) ? |_| BadBodyUtf8`. Use `?? fallback` only for display at a boundary, and `Str.from_utf8_lossy` only when lossy display is explicitly the point.
- **Build text by interpolation:** `"${base}/${topic}"`, not `Str.concat` chains. Convert at the slot: `"${count.to_str()} items"`. Join a list with `Str.join_with(pieces, ", ")`.
- **Use `Str.inspect` for debug output** of records, tags, byte lists, and Bools. Don't write one-off `bytes_to_str` or `headers_to_str` helpers.
- **Count bytes with `Str.count_utf8_bytes`; test emptiness with `is_empty`.** `Str.len` deliberately doesn't return a number. A length limit counts bytes, never graphemes.
- **Long templates, markup, and CSS are multiline `\\` strings,** one `\\` per line. They need no escaping and keep interpolation. Leave a short literal on one line.
- **Character literals (`'a'`) are for byte-level parsing.** A number left in the code should be an honest number, not a byte in disguise.
- **Read the builtins before writing a helper.** A helper the builtins already have is a second copy to keep right.

## Effects and purity

- **Pure decisions live outside effects,** so `expect`s can reach them. An effect gathers input, calls a pure function for the decision, and acts on the answer. This is the one split the [function shape](#function-shape) rules always allow.
- **Effects are named for their act.** See [naming](#naming).

## Modules

- **The type block is the public surface.** Only what's inside `X :: [].{ ... }` is exposed, so private helpers go outside it. The block then reads as the module's API at a glance.

  ```roc
  Util :: [].{
  	public_fn : Str -> Str
  	public_fn = |s| helper(s)
  }

  helper : Str -> Str
  helper = |s| s.trim()
  ```
- **A resource is reached through one module.** One module calls the host's file functions (or network, or database); everything else asks it.
- **A flow is read in one module, not five.** A module whose every caller is one other module belongs with that caller, unless the reason it stands alone is written down. Shared helpers go where their callers meet, not where they were first written.

## Platforms and the host boundary

- **A hosted function answers a tag or a `Try`, never a `Bool`:** `[Member, Outsider]`, or `Try({}, [Failed])` for one that can only succeed or fail.
- **Every record and tag union that crosses the seam is checked against `roc glue`,** field by field and tag by tag, at compile time. A size assertion misses two same-sized fields swapped, and a swap isn't an error: the host silently reads the wrong field.
- **The host gives facts; Roc gives verdicts.** When Roc can decide from what the host can tell it, the host reports the fact (who is asking) and Roc decides (whether they may). The host keeps only what needs its secrets or its state.
- **A primitive takes bytes exactly; the rules around them are Roc's.** The host appends what it is handed. Whether a newline or separator is needed first is a pure Roc function its `expect`s reach.
- **Decode the host's answer into types at the door.** A host answer of zero or one value becomes a named tag immediately (`[Sent(List(U8)), Unsent]`). Pure code never takes the host's raw list.
- **A bad request at the seam crashes rather than returning an empty answer.** An empty answer looks like a real one.
- **Words the operator reads come from Roc.** The host never builds a message from facts Roc already has.
- **Plan destructive work as data first.** Roc builds the whole plan as a list of tagged steps before anything changes, then hands each step to an effect in order, stopping at the first failure. A dry run and the real run are then the same plan.

## Layout

- **`roc fmt` is final.** Ask for a vertical stack with a trailing comma; it keeps it.
- **Stack anything with three or more parts,** one per line with a trailing comma: lists, records, tuples, call arguments, tag payloads. Stack a line over about 100 columns too.
- **A call whose one argument is a stacked list keeps the bracket on the call's line:** `with_headers([` … `])`.
- **`roc fmt` parenthesises an `if` condition when the branch isn't a block:** `if (n < 0) -n else n`. Write it that way.

## Tests

- **Write top-level `expect`s beside the code** they test. `roc test main.roc` runs every imported module's `expect`s; CI runs `roc test` on every app and example.
- **Put a `##` doc comment directly before every top-level `expect`.** `roc test` prints it with the failure, so it is the test's name.
- **Test every pure mapping, and the exact output of every builder.**
- **Use `?` for setup inside an `expect`;** an `Err` fails the test immediately.
- **Compare decoded values, not `Try`s,** on the happy path.
- **Keep simple tests as direct comparisons.** Avoid long `and` chains.
- **For several related facts, compare a labelled report.** Build a multiline `actual` with `Str.inspect` for Bools, tags, and records, and compare it to a multiline `expected`. A failure then shows exactly which line differs.
- **Include negative tests for every parser.**
- **Build tests with `--opt=dev`.** The default optimising backend compiles far slower, and a test run rarely needs it.

```roc
## Inline debug helpers expose inspect and equality behaviour.
expect {
	inline : Markdown.Inline
	inline = Strong([Text("Roc")])

	actual =
		\\inspect: ${Str.inspect(inline)}
		\\debug: ${inline.to_debug_str()}
		\\eq same: ${Str.inspect(inline == Strong([Text("Roc")]))}
		\\eq different: ${Str.inspect(inline == Emphasis([Text("Roc")]))}

	expected =
		\\inspect: Strong([Text("Roc")])
		\\debug: Strong([Text("Roc")])
		\\eq same: True
		\\eq different: False

	actual == expected
}
```
