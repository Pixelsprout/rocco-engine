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

Use `--selection` to display coverage, selected depth, and scene depth in red, green, and blue.
Use `--outline` to run the game-authored HDR outline before bloom.
Add `--through-wall` to change its occlusion policy with the same shader inputs.
Press V to change the policy.
Press S to select or deselect the Group.
Press U to unload the Pack.

The selected Group contains overlapping Draws, a nested Group, cutout foliage, alpha-zero glass, and skinned Pip.
Every selected Draw disables shadow casting.
The wall and floor occlude selected geometry without changing Selection coverage or selected depth.
The native check verifies the union and nearest depth against the separate left and right Draws.
It checks both policies, bloom, live deselection, deterministic deformation, and Pack lifetime.

`assets/meshes/pip.glb` copies the tutorial's synthetic Pip from `tutorial/10-animation`.
`source/make_glass.py` generates the synthetic alpha-zero, double-sided pane without external tools.
