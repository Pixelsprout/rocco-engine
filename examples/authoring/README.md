# Shader authoring proof

This small game proves the author workflow before village integration.
It uses a two-slot tree, a ground surface, an occluder, and one selected Group.
The Group contains the tree and a small marker.
The game owns the wind and outline shaders.
No shader style requires an Odin change.

The generated `Tree.leaves` helper selects the imported `Leaves` slot.
The generated `Foliage` helper supplies Scene, Material, and Draw parameters.
The Surface hook preserves imported textures, alpha rules, and material properties.
The unassigned `Bark` slot keeps its imported material.
All rendering passes use the same wind deformation and cutout texture.
The wind hook converts world displacement with `Vertex.world_to_local_direction`.
It clamps local displacement length to 0.25, within its declared 0.35 bound.
The clamp can reduce world amplitude at small scales.
Exact world amplitude needs a declared local bound that covers the inverse scale.

`Outline` uses scene colour, scene depth, selected coverage, and selected depth.
Its `visible_only` parameter selects the occlusion policy.
Both policies use the same selected Group and the same Selection inputs.
`Selection` displays coverage in red, selected depth in green, and scene depth in blue.

## Controls

| Key | Action |
| --- | --- |
| V | Switch the outline occlusion policy. |
| S | Select or deselect the Group. |
| C | Change the leaf colour parameter. |
| N | Switch tree shadow casting. |
| U | Unload or reload the Shader Pack. |

Use `--no-wind` for a still frame.
Use `--selection` to inspect Selection inputs.
Use `--through-wall` for the through-wall outline.
Use `--empty` to omit the Post effect.
Use `--solid` to replace the imported alpha mask with opaque coverage.
Use `--no-occluder`, `--no-shadow`, or `--no-selection` for comparisons.

## Candidate SDK proof

The CI artifact is a draft-PR candidate.
It is not a stable release.
The candidate contains platform and package archives, checksums, provenance, and this fixture.
The clean CI jobs download that artifact without an engine checkout.
They install pinned Roc and the shader compiler named by the SDK contract.
They assert that Odin is absent.
They clear `LIB` before the Windows link.

Install the Roc nightly named in `candidate.json`.
Download the `candidate-sdk` artifact from its CI run.
Extract the artifact into an empty `sdk` folder.
Verify each file against `SHA256SUMS` before extracting the fixture.
Extract `authoring-fixture.tar.gz` into another empty folder.
Run the following command from that folder:

```sh
CANDIDATE_ARTIFACT_URL=https://github.com/OWNER/REPO/actions/runs/RUN/artifacts/ARTIFACT \
  python3 authoring/proof.py --sdk /absolute/path/to/sdk --out /absolute/path/to/evidence
```

The proof verifies archive checksums again.
It runs `roc unbundle` in an explicit empty folder.
Roc requires a bare hash filename for `unbundle`.
The proof copies each verified release-named archive to its bare hash name.
Roc extracts that archive under the bare hash directory in the current working directory.
The evidence preserves the original published filename and digest.
The proof points the game header at the extracted platform and mesh package.
It compiles shaders with the SDK tool and contract.
It builds the game with Roc.
It runs the game through the standalone Bridge driver in this folder.
The driver uses only Python's standard library.

`evidence.json` records the artifact URL, run, commit, archive hashes, toolchain, commands, and checks.
The evidence folder also contains native logs and screenshots.
Manual SDK runs record `local SDK replay`.
Only clean CI runs with matching artifact, run, commit, and digest provenance can pass the published-artifact gate.
The checks cover repeated wind steps, imported materials, cutout shadows, Pack ownership, and both outline policies.
They also cover live Surface and Post edits, compiler failures, package rejection, source recovery, and interface restart.
The interface check retains the old frame before it rebuilds and restarts the game.

On Linux, install Xvfb and Mesa before the native run.
Run the proof under `xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1`.
CI uses software GL and the Windows runner's D3D11 device.
These runs prove backend compatibility.
They do not establish reference-machine performance.

## Local preparation

From an engine checkout, build the game and run the local proof:

```sh
roc scripts/build.roc host --release
roc scripts/build.roc inputs --release
roc scripts/build.roc game authoring
python3 examples/authoring/proof.py --platform platform --out /tmp/authoring-evidence
```

The local mode records `local preparation` in its evidence.
It does not satisfy the published-artifact gate.

For live editing, start the game and run this command from the game folder:

```sh
python3 /absolute/path/to/platform/shader-tools/build.py --watch --install
```

Edit `wind.glsl`, `leaves.glsl`, or `outline.glsl`.
Compatible source changes reload at a frame boundary.
Invalid source preserves the previous shader outputs and rendered frame.
Correct the source to recover without a restart.
If the declaration changes an interface, rebuild the game and restart it.
The running game retains its valid generation until that restart.

## Asset source

`source/make_tree.py` creates the small original fixture with Python's standard library.
The GLB embeds its alpha texture and vertex weights.
It needs no external asset download or conversion tool.
Run `python3 source/make_tree.py` from this folder to regenerate it.
