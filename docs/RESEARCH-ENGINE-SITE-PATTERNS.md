# Research: how engine sites present an engine with little to show

Date: 2026-11-20

## Question

How do game engine sites present an engine that has little to showcase yet? What should a public rocco landing page copy, and what should it avoid?

rocco context: the pitch is data-driven, good for AI agents, and reliable by construction. Roc is not the main draw. rocco has three early games (Village, Agent Town, Kula) that run in the browser through WebGPU.

## Method

- I read each live landing page on 2026-11-20 with a page fetcher. Quotes below come from those reads.
- I read archive.org snapshots of the Bevy home page (2020-08-11, one day after launch) and the Macroquad home pages (2021-05-05 and 2021-06-15). I pulled the raw HTML with the `id_` suffix and stripped the tags.
- archive.org went "Temporarily Offline" during the session. Some deeper snapshots (Macroquad example pages, the Bevy 2020 FAQ) did not load. Those gaps are marked "Not confirmed".
- "Above the fold" here means the first screen of text a fetcher returns. A page fetcher does not render CSS, so a background video or canvas can be missed. Treat "no hero media" as "no hero media in the HTML text".

## Summary table

| Site | Hero message | Above the fold | Maturity signal | Split |
|---|---|---|---|---|
| Godot | "Your free, open-source game engine." | Logo, Download 4.7.2, What's new | Version, 2007–2026, sponsor tiers, showcase | Site / external docs / Showcase / Community hub |
| Bevy (now) | "A refreshingly simple data-driven game engine built in Rust" | Headline, "Get Started" | Warning lives in Quick Start, not home | Home / Learn / Examples / News / Community / Assets |
| Bevy (2020 launch) | Same headline, "Free and Open Source Forever!" | Headline, feature blocks with stills | No warning on home; warning in launch post | Features / Learn (Book) / News / Community |
| Defold | "Lightweight and performant." | Logo, tagline, Download | "Production ready", shipped games, monthly releases, partners | Learn / Showcase / Community / Blog |
| raylib | "A simple and easy-to-use library to enjoy videogames programming" | Tagline, social icons, Donate | Counts (+120 examples, +60 bindings), grants, sponsors | examples / games / cheatsheet / wiki |
| LÖVE | "LÖVE is an \*awesome\* framework you can use to make 2D games in Lua." | Wiki / Forums / Bugs buttons, Download 11.5 | Version, licence, six shipped games incl. Balatro | Wiki / Forums / Bugs |
| Macroquad (now) | "Simple and easy to use game library for Rust programming language." | Text, "Browse examples" | None stated | Examples / Articles / Docs / GitHub |
| Macroquad (May 2021) | (home page was the examples grid) | Grid of ~30 example thumbnails, each with a GitHub source link | None stated | Examples / Tutorials / docs.rs / GitHub |
| Effect | "Reliable TypeScript for the AI era" | Install command, "In production at" logos | Logos, talks, testimonials, FAQ | Docs / Play / Blog / Podcast / Community |

## Godot (godotengine.org)

- **Hero.** "Your free, open‑source game engine." Sub-line: "Develop your 2D & 3D games, cross-platform projects, or even XR ideas!" Source: [godotengine.org](https://godotengine.org/).
- **Above the fold.** The text shows no video or screenshot in the hero. The calls to action are "Download Latest 4.7.2" and "What's new". Feature images come further down.
- **Maturity.** A stable version number, 4.8 beta snapshots, "© 2007-2026", and four tiers of corporate sponsors. No user counts or testimonials.
- **Split.** Docs and Contribute are separate sites. Showcase, Blog and Community are pages on the main site. Community is a hub that links to the forum and events.
- **Showcase.** The [showcase page](https://godotengine.org/showcase/) leads with yearly showreel videos (2023–2026), then platform filters, then games (Slay the Spire 2, Brotato, Dome Keeper and others), then "Apps & Tools", then "Coming soon".
- **Lesson.** Godot can lead with a download button because the brand is already known. A new engine cannot.

## Bevy (bevy.org, formerly bevyengine.org)

Bevy matters most here. It launched on 2020-08-10 with no games to show.

### Launch site (archive.org, 2020-08-11)

- **Hero.** "A refreshingly simple data-driven game engine built in Rust". Sub-line: "Free and Open Source Forever!" Source: [archive.org snapshot 20200811181008](https://web.archive.org/web/20200811181008/https://bevyengine.org/).
- **Above the fold.** Logo and headline only. Navigation: Features, Learn, News, Community, and a "Get Started" button.
- **Body.** The page is a list of feature blocks. Each block has a heading, three short claim lines, and one illustration. Most illustrations are diagrams or icons (`ecs.svg`, `render_graph.svg`, `scene.svg`, `hot_reloading.svg`). Only two are renders (`sprite.png`, `boat.png`). The blocks are: Data Driven, 2D Renderer, 3D Renderer, Render Graph, Cross Platform, Bevy UI, Scenes, Sound, Hot Reloading, Productive Compile Times, Free and Open Source.
- **Concrete, checkable claims.** "With Bevy you can expect 0.8-3.0 seconds with the 'fast compiles' configuration". "Compare that to other popular Rust game engines, which can take over 30 seconds to compile a single newline insertion!" "You can currently hot-reload scenes, textures, and meshes".
- **Honest earliness.** "Cross Platform" says "Support for all major desktop platforms" and "With more on the way: Android, iOS, Web". The home page has no stability warning.
- **Where the warning lived.** The launch post carried it. Source: [Introducing Bevy, 2020-08-10](https://bevy.org/news/introducing-bevy/). Quotes:
  - "Bevy is still in the very early stages."
  - "I consider it to be in the 'prototyping' phase: features are missing, APIs will change, and documentation is sparse."
  - "I don't yet recommend using Bevy in serious projects unless you are willing to deal with gaps and instability."
- The 2020 Getting Started page also said: "Currently the project is moving really fast." Its quick start was "cargo run --example breakout". Source: [archive.org snapshot 20200828174913](https://web.archive.org/web/20200828174913/https://bevyengine.org/learn/book/getting-started/).
- The launch post sold the design goals (Capable, Simple, Data Focused, Modular, Fast, Productive) with code snippets, PNG screenshots, a hot-reload video, and SVG benchmark charts.

### Current site

- **Hero.** The headline is unchanged six years on: "A refreshingly simple data-driven game engine built in Rust". Source: [bevy.org](https://bevy.org/).
- **Body.** The same feature-block structure. Each block still has one illustration. The compile-time claim is still there.
- **Warning.** It sits on the first Quick Start page, not the home page: "Bevy is still in development. Important features are missing, and documentation can be sparse." "A new version of Bevy containing breaking changes to the API is released approximately once every 3 months." "Use only if you are willing to work in this environment." Source: [Quick Start introduction](https://bevy.org/learn/quick-start/introduction/).
- **Examples.** The [examples page](https://bevy.org/examples/) says "Click an example below to run it in your browser (using WASM + WebGL) and view the source code." It groups examples into 26 categories. A separate page runs WebGPU examples.
- **Split.** Getting Started, Learn, News, Community, Foundation, Assets, Examples. There is no "Showcase" item.

## Defold (defold.com)

- **Hero.** "Lightweight and performant." Sub-line: "Defold is a free, powerful, all-in-one game engine for building truly cross-platform 2D and 3D games." Source: [defold.com](https://defold.com/).
- **Above the fold.** Logo, tagline, "DOWNLOAD DEFOLD NOW". No video, live demo or code. Three featured games follow directly below the hero.
- **Maturity.** Four badges: "Free forever", "Cross-platform", "Production ready", "Source available". "Proven track record of game releases on desktop, consoles, web and mobile." "Actively developed, with a new release every month." A platform logo strip includes consoles. A foundation and partner tiers are named.
- **Split.** Learn (tutorials, manuals, examples, API), Showcase, Community, Blog.
- **Lesson.** Defold argues maturity through release cadence and shipped platforms. Those are claims rocco cannot make yet.

## raylib (raylib.com)

- **Hero.** "raylib is a simple and easy-to-use library to enjoy videogames programming." Source: [raylib.com](https://www.raylib.com/).
- **Above the fold.** Tagline, social icons, "Donate". No hero media in the text. An architecture diagram sits near the bottom.
- **Maturity.** Counts: "+120 code examples", "+60 bindings". Recognitions: Google Open Source Peer Bonus (2019), Epic MegaGrant (2020), NLnet NGI Zero (2025). Sponsor tiers. The page text never states a version number.
- **Feature list.** Plain technical facts: "NO external dependencies", "Written in plain C code (C99)", "Hardware accelerated with OpenGL (1.1, 2.1, 3.3, 4.3 or ES 2.0)".
- **Split.** Top bar: examples, games, cheatsheet, wiki. Community is a section lower on the page.
- **Examples.** The [examples page](https://www.raylib.com/examples.html) filters by module and rates each example "by complexity with stars". Not confirmed from the fetch: whether each example runs live in the browser.
- **Lesson.** raylib's maturity signal is the size of its example set and its cheatsheet. It works because the examples are the product.

## LÖVE (love2d.org)

- **Hero.** "LÖVE is an \*awesome\* framework you can use to make 2D games in Lua." Source: [love2d.org](https://love2d.org/).
- **Above the fold.** Three buttons (Wiki, Forums, Bugs), then the download block for 11.5. No screenshot.
- **Code.** Three tiny snippets: draw text, draw an image, play a sound. Each is two to four lines.
- **Maturity.** Version 11.5, zlib licence, and a "Games" strip: Balatro, Arco, Move or Die, Gravity Circuit, oh my giraffe, Moonring.
- **Split.** The site is close to a link page. The wiki holds docs. The forum and Discord hold the community. Bugs link to GitHub issues.
- **Lesson.** Three tiny code snippets show the programming model faster than prose does.

## Macroquad (macroquad.rs)

Macroquad also went public with little to show.

### Early site (archive.org, 2021)

- **May 2021.** The home page was the examples grid itself. It held about 30 cards (3d, arkanoid, asteroids, camera, first_person, particles, platformer, post_processing, shadertoy, snake, ui, and more). Each card had a thumbnail that linked to a page such as `3d.html`, and a GitHub icon that linked to the `.rs` source. A particles editor on itch.io closed the list. Source: [archive.org snapshot 20210505190509](https://web.archive.org/web/20210505190509/https://macroquad.rs/). Not confirmed: that the 2021 example pages ran wasm. The later live examples page says "Click an example to run it in your browser."
- **June 2021.** The home page became a text page. Headline: "Simple and easy to use game library for Rust programming language." One button: "Browse examples". Five feature blocks: HTML5 ("First class browsers support, WebGL1 and IOS Safari supported."), Android ("Single command docker-powered android builds."), IOS, PC ("no external system dependencies"), Batteries included. Navigation: Examples, Tutorials, docs.rs, GitHub. Source: [archive.org snapshot 20210615062501](https://web.archive.org/web/20210615062501/https://macroquad.rs/).
- No version number, no stability statement, no games.

### Current site

- The structure is the June 2021 page plus a five-step getting-started block with a full `main.rs`. Navigation adds Articles and "This Week in Quad". Still no showcase and no stability statement. Source: [macroquad.rs](https://macroquad.rs/).
- [Examples page](https://macroquad.rs/examples/): thumbnail cards, "Click an example to run it in your browser", and a GitHub icon for the source.
- **Lesson.** Macroquad used small, many, runnable examples as its showcase. It made "runs in the browser" a headline claim, then let the examples prove it.

## Effect (effect.website)

Effect is not a game engine. It is here for its "reliable" pitch.

- **Hero.** "Reliable TypeScript for the AI era". Sub-line: "Build production-ready systems your team can ship, customers can depend on, and AI agents can work with." Source: [effect.website](https://effect.website/).
- **Above the fold.** An install command with package-manager tabs, and "In production at" logos (Cloudflare, opencode, T3). No video or diagram.
- **The reliability argument.** The page does not say "reliable by construction". It argues that the type makes failure visible:
  - Mental model heading: "Track successes, errors, dependencies in one type".
  - Body: "The type signature tells you everything. The compiler catches what you miss. No more runtime surprises."
  - It shows the signature `Effect<Success, Error, Requirements>` with each parameter labelled, then a short code example.
- **Pain point, then solution.** Six cards open with a pain line, then list the fix. Examples: "Try-catch blocks everywhere but you still do not know how things can fail." "That Promise.all call? One failure and everything crashes." "No observability. Production is on fire and you do not know why."
- **The AI argument.** Section "LLMs ❤️ Effect": "Effect's declarative patterns and strong type system make it easier for LLMs to generate correct, production-ready code." Four points: "Predictable structure", "Typed feedback loop: detailed error traces show what failed, enabling precise self-repair.", "Built-in reliability", "Rich toolbox". It links to an LLM quick-start guide.
- **Proof.** Three conference talk videos from production users, then eight testimonials, then an FAQ that meets objections head-on ("Why is the syntax different from typical TypeScript?", "What about performance overhead?", "Is it possible to adopt Effect in an existing codebase?").
- **Split.** Docs, Play (a playground), Blog, Podcast, Module of the Week, Community, Discord, GitHub.

## Patterns

### What every site does

- The hero is one sentence that names the category and one or two adjectives. Bevy, raylib, Macroquad and LÖVE all use "simple". Bevy has kept its line for six years.
- No engine site puts a "this is early" warning on the home page. Bevy puts it in the launch post and on the first Quick Start page. Macroquad states nothing.
- The engines with little to show (Bevy 2020, Macroquad 2021) used diagrams, short claim lists, and runnable examples. They did not fake a showcase.
- Docs live on a separate page or site. The landing page links to "Get Started" or "Examples" first.

## Recommendations for rocco

### Patterns to copy

1. **Put a running game above the fold.** No surveyed engine does this, and rocco can. Load Village, Agent Town or Kula in a WebGPU canvas in the hero. This beats Macroquad's thumbnails and Bevy's diagrams, which were what they had. Show a still and a "Play" button when WebGPU is not available.
2. **Keep one plain hero sentence and keep it stable.** Follow Bevy: category plus the claim. Lead with "data-driven" and "reliable", not with Roc or Odin. Bevy names Rust in the headline. rocco should name the language lower down, because Roc is not the draw.
3. **Argue reliability the Effect way.** Open each feature with a game-dev pain line, then the fix. Example pain lines: a save file that no longer loads, a crash deep in a frame, a script that mutates state from anywhere. Show one type or one small code block that makes the guarantee visible.
4. **Give AI agents their own section.** Copy Effect's "LLMs ❤️ Effect" shape: a one-line claim, three or four numbered reasons, and a link to an agent quick-start. Make each reason checkable, for example "the host rejects a bad Scene before it renders".
5. **Use concrete, checkable numbers.** Bevy's "0.8-3.0 seconds" compile claim worked because a reader can test it. Quote numbers from `docs/BENCHMARKS.md` only where a reader can reproduce them.
6. **Make examples the showcase.** Follow Macroquad and Bevy: a grid of small runnable examples, each with a link to its source. Split the three games from the examples. Three games alone look thin. Three games plus twenty examples look like a working engine.
7. **Show tiny code.** Follow LÖVE: three snippets of two to six lines each. Pick the data-driven shape: a Scene as data, an update as a pure function, a typed event.
8. **Put the honest warning one click in.** Follow Bevy: put "rocco is early, the API will change" on the first Get Started page and in a launch post. Keep the home page factual. Do not claim "production ready".
9. **List platforms honestly.** Follow Bevy 2020: "Runs today: desktop, browser (WebGPU)", then "On the way: ...".

### Patterns to avoid

1. **Do not lead with a download button.** Godot and Defold can, because people already know them. A new engine needs to show first.
2. **Do not borrow mature-engine proof.** Do not use sponsor tiers, "Production ready" badges, console logos, or "proven track record" lines. Defold earns these. rocco cannot yet.
3. **Do not use vanity counts that are small.** raylib's "+120 code examples" works at 120. "3 games" invites the wrong comparison. Show the games, do not count them.
4. **Do not use an empty showcase or a "coming soon" grid.** Neither Bevy nor Macroquad had a Showcase page at launch. Add one when outside games exist.
5. **Do not let the language be the headline.** Bevy and Macroquad name Rust because Rust was the draw. For rocco, Roc in the hero narrows the audience to people who already know Roc.
6. **Do not make the reliability claim without proof on the page.** Effect backs "reliable" with a type, a code sample, talks and an FAQ. A bare "reliable by construction" reads as marketing to a game dev.
7. **Do not hide the source.** Every engine example grid links to the code. A playable game with no "view source" link wastes the data-driven pitch.

## Open questions

- Not confirmed: whether the 2021 Macroquad example pages ran wasm in the browser. archive.org was offline when I tried them.
- Not confirmed: whether raylib's example pages run live in the browser.
- Not checked: early archives of Godot (2014) and Defold (2016 public release). Both launched with existing games behind them, so they matter less to this question.
