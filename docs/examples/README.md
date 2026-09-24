# Examples

The generic platform from `docs/DESIGN.md` and two games that run on it
unchanged. They check and test with no engine. Both use the camera package in
`packages/camera/`. Roadmap milestone 2 moves them to `platform/` and
`examples/`, where they link.

```sh
roc check entity-game.roc && roc test entity-game.roc
roc check cards.roc && roc test cards.roc
roc glue ../../glue/OdinGlue.roc out platform/main.roc
```

| File | What it shows |
|---|---|
| `platform/main.roc` | The vocabulary, the for-clause binding `Model`, the boxed wrappers. |
| `entity-game.roc` | A `step` pipeline of stages, a `Model` with a tag-union payload the host never sees, `view` at step rate with stable draw ids, six tests. |
| `cards.roc` | A game with no entities on the same platform. The proof the platform is agnostic. |

`view_for_host`'s return type is written inline rather than as `Scene`
because `roc check` on `nightly-2026-09-12-220fd47` segfaults on some alias
shapes in platform modules. The app files are unaffected.
