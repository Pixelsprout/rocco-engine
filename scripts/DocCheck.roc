# roc docs gives each item an <article class="entry ..."> and puts a ##
# comment in a <div class="entry-doc"> inside it. A ## comment on the module's
# own type becomes a <div class="module-doc"> before the first article.
DocCheck := [].{
	# The module and each item on a roc docs module page with no ## comment, by
	# their anchor names, such as "Vocabulary" and "Vocabulary.Launch".
	missing : Str -> List(Str)
	missing = |html| {
		chunks = Str.split_on(html, article_start)
		head = chunks.first() ?? ""
		var $items = match between(head, "<h1 class=\"module-name\">", "</h1>") {
			Ok(name) if !Str.contains(head, "<div class=\"module-doc\">") => [name]
			_ => []
		}
		for chunk in chunks.drop_first(1) {
			article = match Str.split_first(chunk, "</article>") {
				Ok({ before, .. }) => before
				Err(_) => chunk
			}
			if !Str.contains(article, "<div class=\"entry-doc\">") {
				$items = $items.append(between(article, "id=\"", "\"") ?? "an unnamed item")
			}
		}
		$items
	}

	# A package with no item found means roc docs changed its HTML, and missing
	# would pass everything.
	has_items : Str -> Bool
	has_items = |html| Str.contains(html, article_start)

	article_start : Str
	article_start = "<article class=\"entry"

	between : Str, Str, Str -> Try(Str, [NotFound])
	between = |text, start, end| {
		{ after, .. } = Str.split_first(text, start) ? |_| NotFound
		{ before, .. } = Str.split_first(after, end) ? |_| NotFound
		Ok(before)
	}
}

documented : Str
documented =
	\\<h1 class="module-name">Launch</h1>
	\\<pre class="entry-type-def"><code class="entry-type-def-code">:= []</code></pre>
	\\<div class="module-doc">
	\\    <p>The Launch a game starts from.</p>
	\\</div>
	\\<article class="entry entry-value" id="Launch.default">
	\\    <div class="entry-signature">default</div>
	\\    <div class="entry-doc"><p>Today's constants.</p></div>
	\\</article>
	\\

bare : Str
bare =
	\\<h1 class="module-name">Vocabulary</h1>
	\\<pre class="entry-type-def"><code class="entry-type-def-code">:= []</code></pre>
	\\<article class="entry entry-type" id="Vocabulary.Vec3">
	\\    <div class="entry-signature">Vec3</div>
	\\    <div class="entry-doc"><p>A point.</p></div>
	\\</article>
	\\<article class="entry entry-type" id="Vocabulary.Launch">
	\\    <div class="entry-signature">Launch</div>
	\\</article>
	\\<article class="entry entry-type" id="Vocabulary.Window">
	\\    <div class="entry-signature">Window</div>
	\\</article>
	\\

expect DocCheck.missing(documented) == []
expect DocCheck.missing(bare) == ["Vocabulary", "Vocabulary.Launch", "Vocabulary.Window"]

# The package index page names no module and has no items.
expect DocCheck.missing("<div class=\"index-decoration\"></div>") == []

expect DocCheck.has_items(documented) and DocCheck.has_items(bare)
expect !DocCheck.has_items("<div class=\"index-decoration\"></div>")
