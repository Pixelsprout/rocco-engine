# Cutout shadow validation

Date: 2026-11-05.
Decision: [ADR 0031](adr/0031-cutout-shadow-coverage.md).

## Coverage and capacity

MASK shadows sample the same base texture and factored vertex alpha as the colour pass.
The fragment shader samples before discarding below the imported cutoff.
Single-sided MASK parts cull back faces.
Double-sided MASK parts cull neither face and use one submit.
BLEND parts cast no shadow.

Every cascade draws all Opaque ranges before MASK parts.
An Opaque range retains the position-only shader, empty fragment shader, and one submit per Draw.
Each placed MASK part adds one textured submit.
Only parts that fit the Main draw capacity cast shadows.
Rigid and skinned paths use the same placed transform and skin pose in both passes.
Named slots and raw colour metadata remain unchanged.
The default GPU vertex colour already includes the imported base factor and `COLOR_0` once.

The shadow vertex block grows from 64 to 80 bytes.
Its aligned cost stays 256 bytes per submit.
The fragment shader adds no uniform block.
Each cascade submits at most as many shadow draws as placed Main submits.
Each skinned Draw uploads its palette once per used shadow pipeline.
These pipelines form a subset of the Main pipelines already counted by `frame_room`.
Uniform capacity, skin capacity, spare slots, and the 1,195,443 draw limit remain unchanged.
The renderer adds four pipeline objects and two shader objects.
MASK programs use three rigid attributes or five skinned attributes.
Texture variants remain within the existing 16-texture limit per Mesh.

## Visual checks

The Bridge captured fixed steps 120 and 520 with the default camera and `--far-shadows`.
The far view uses four 2048 cascades, a 0.05-radian lens, and a camera radius of 110 metres.
The geometry lies within the final cascade.
Both runs produced 960 by 540 physical screenshots with 4-sample MSAA.
The debug Metal run reported no Sokol validation failures.
Every process exited after the Bridge sent `quit`.

| Capture | Observation |
| --- | --- |
| [Original, step 120](evidence/cutout-shadows/before-front.png) | Solid fence slabs, square leaf shadow, solid Pip shadow. |
| [Cutout, step 120](evidence/cutout-shadows/cutout-front.png) | Fence holes, leaf silhouette, and holes in the skinned shadow. |
| [Cutout, step 520](evidence/cutout-shadows/cutout-back.png) | Rotated leaf still casts from its back face. |
| [Far, step 120](evidence/cutout-shadows/far-front.png) | Leaf shadow and fence coverage remain visible. |
| [Far, step 520](evidence/cutout-shadows/far-back.png) | Camera motion retains leaf and skinned coverage. Fine fence detail aliases at this resolution. |

The far captures show the expected loss of subtexel detail under PCF.
They do not establish temporal stability for every foliage asset or camera route.

## Mip evaluation

Ordinary box mips remove the example fence and leaf coverage in small levels.
The importer now preserves coverage at the effective texture cutoff when the combined vertex alpha is constant.
Different effective cutoffs use separate texture variants.
The colour and shadow passes share each variant.
Base pixels and RGB mip values remain unchanged.

The following counts use the actual engine importer and the committed example assets at cutoff 0.5.

| Asset | Mip dimensions | Passing texels, ordinary mips | Passing texels, coverage mips |
| --- | --- | --- | --- |
| Fence | 64 × 64 | 1,072 / 4,096 | 1,072 / 4,096 |
| Fence | 4 × 4 | 0 / 16 | 8 / 16 |
| Fence | 2 × 2 | 0 / 4 | 4 / 4 |
| Leaf | 128 × 128 | 6,592 / 16,384 | 6,592 / 16,384 |
| Leaf | 16 × 16 | 100 / 256 | 104 / 256 |
| Leaf | 2 × 2 | 0 / 4 | 4 / 4 |
| Pip holes | 8 × 8 | 48 / 64 | 40 / 64 |

The algorithm chooses the closest available nonzero coverage from each mip's alpha bins.
Tied alpha bins and small mip levels limit precision.
The final levels can overestimate coverage, which darkens distant fine fences.
Zero averaged alpha remains zero.
Variable vertex alpha keeps ordinary mips because one texture threshold cannot preserve every interpolated cutoff.
A future Surface override must select or rebuild mips when its alpha rules change.

## Reference Mac measurement

The machine used the scoped reference Mac: Apple M5, 10-core GPU, 16 GB RAM.
AC power was connected, and Low Power Mode was off.
Other development work shared the machine.
The host used release Odin optimization with Spans.
The Roc game used development compilation.
Both captures used windowed Lockstep, 960 by 540 physical pixels, 4-sample MSAA, and one 2048 shadow cascade.
The default camera and animation advanced by the same fixed steps.
Each capture recorded 720 GPU frames and 720 CPU rows.
The measured sample excludes 120 warmup frames and includes frames 121 through 720.

GPU work is the union of Active Metal intervals for the game process within each GPU frame.
CPU work sums the ten recorded work spans and excludes the instrumentation-cost estimate.
Percentiles use the nearest-rank method.

| Work | Renderer | Median | p95 | p99 | Maximum |
| --- | --- | --- | --- | --- | --- |
| GPU active | Whole triangles | 0.949 ms | 2.023 ms | 2.054 ms | 2.070 ms |
| GPU active | Cutout shadows | 0.974 ms | 2.055 ms | 2.073 ms | 2.118 ms |
| CPU spans | Whole triangles | 0.086 ms | 0.456 ms | 0.487 ms | 0.522 ms |
| CPU spans | Cutout shadows | 0.292 ms | 0.512 ms | 0.545 ms | 0.568 ms |
| CPU render submit | Whole triangles | 0.038 ms | 0.170 ms | 0.195 ms | 0.209 ms |
| CPU render submit | Cutout shadows | 0.118 ms | 0.208 ms | 0.229 ms | 0.253 ms |

The measured p95 changes are +0.032 ms GPU work and +0.056 ms CPU work.
One run per renderer cannot isolate small changes from shared-machine noise.
These measurements do not establish village performance, four-cascade cost, or real-clock frame pacing.

The original source was commit `3624fbff8282d1a0e5fd8be1aeb16bac17a72138`.
The original executable SHA-256 was `4fc03ac5053da2e2b8eef75d1b9799149b2afcc1766bb7576ff1d656cc29e300`.
The cutout executable SHA-256 was `68697bf6685d10270a313feb558678bf8934c0db25cc6f5a968793360458a80b`.

Local raw artifacts:

- `/tmp/mask-before-assets.trace` and `/tmp/mask-cutout.trace`.
- `/tmp/mask-before-assets-gpu.xml` and `/tmp/mask-cutout-gpu.xml`.
- `/tmp/mask-before-gpu.json` and `/tmp/mask-cutout-gpu.json`.
- `/tmp/mask-before-assets-cpu.csv` and `/tmp/mask-cutout-cpu.csv`.
- `/tmp/mask-cpu-summary.json` and `/tmp/mask-mips.log`.
- `/tmp/mask-metal-summary.py`, adapted from the existing village interval parser to select the executable name.

Reproduce a capture from `examples/mask` after building release inputs and the release host with Spans:

```sh
xcrun xctrace record --template 'Metal System Trace' --time-limit 30s \
  --output /tmp/mask-cutout.trace --env ROCCO_LOCKSTEP=1 \
  --env ROCCO_EXIT_AFTER_FRAMES=720 \
  --env ROCCO_SPANS_CSV=/tmp/mask-cutout-cpu.csv --launch -- ./mask.bin
xcrun xctrace export --input /tmp/mask-cutout.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-gpu-intervals"]' \
  --output /tmp/mask-cutout-gpu.xml
python3 /tmp/mask-metal-summary.py /tmp/mask-cutout-gpu.xml \
  --process mask.bin --discard 120 --out /tmp/mask-cutout-gpu.json
```

## Checks and remaining gates

The pinned `sokol-shdc` compiles Metal, GLSL 4.3, and HLSL 5 source.
Shader generation uses `/Users/braedenfoster/tools/sokol-tools-bin/bin/osx_arm64/sokol-shdc`.
Debug Metal runs validate both one-cascade and four-cascade rendering.
Both ordinary and Spans Odin suites pass all 786 tests.
Odin tests cover submit order, cutoff and texture bindings, named slots, skin poses, truncation, and mip coverage.
The MASK example passes `roc check` and all 135 Roc tests.
Shader regeneration reproduces the committed source after normalizing the generated command output path.

Linux GL and Windows D3D11 runtime checks remain PR CI gates.
Shader translation or host cross-compilation does not satisfy those runtime gates.
The existing CI jobs run the MASK example on their respective backends.
