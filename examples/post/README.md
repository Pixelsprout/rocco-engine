# Post fixture

Build with `roc scripts/build.roc -- game post`.
Run `python3 scripts/post_check.py` from the repository root.

The default scene applies two LDR effects with independent values.
Press R to reverse their order.
Press E to enable or disable the effects.
Use `--hdr` to add an HDR effect before bloom.
Use `--depth` to display production scene depth.
Use `--wind` to deform the foliage.
Use `--solid` to remove Mask holes.
Use `--x2`, `--x4`, or `--x8` to select launch MSAA.

The tree uses the synthetic fixture from `examples/surface/source/`.
The native checks compare Mask depth, Blend omission, deterministic wind, UI exclusion, effect order, and failure isolation.
