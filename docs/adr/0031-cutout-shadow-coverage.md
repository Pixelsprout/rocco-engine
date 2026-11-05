# 0031: Cutout shadow coverage

Status: accepted, 2026-11-05.
Supersedes the temporary MASK shadow rule in [ADR 0027](0027-alpha-modes-and-blend-frame-order.md).

## Context

Whole-triangle MASK shadows fill texture holes and omit leaf faces that point away from the Sun.
The immersive village requires foliage shadows that match visible cutouts.

## Decision

The shadow pass draws Opaque ranges first with the existing position-only, empty-fragment shader.
It then draws each placed MASK part with its base texture, vertex alpha, and imported cutoff.
The default vertex colour already includes the imported base factor and raw `COLOR_0` exactly once.
The shadow shader uses that same colour without multiplying either input again.
Named material slots remain attached to their parts.

Single-sided MASK parts cull back faces.
Double-sided MASK parts cull neither face and need one submit.
BLEND parts cast no shadow.
Rigid and skinned MASK programs use the existing skin palette and transforms.
Future Surface variants must share deformation and alpha rules across colour, shadow, and selection.

The cutoff travels in the vertex block and a flat varying.
Each shadow submit consumes one aligned uniform slot.
Each cascade submits at most one shadow draw per placed Main submit.
Each skinned Draw applies its palette once per used shadow pipeline.
The Main pipeline count already bounds these uploads.
The capacity calculation and draw limit therefore remain valid.

MASK mip levels preserve base-level alpha coverage at the imported effective cutoff when constant vertex alpha permits it.
Texture variants include their cutoff, so shared Opaque or differently clipped materials keep their own mip data.
Variable vertex alpha keeps ordinary mips because one texture threshold cannot preserve every interpolated cutoff.
Visual checks must include camera motion and distant cascades.
Measurements must report real CPU and GPU work on the reference Mac.
Metal, GL, and D3D runtime checks remain separate acceptance gates.

## Consequences

MASK parts add submits, texture reads, and fragment discard work to each covered cascade.
Opaque parts retain their cheap path.
Coverage preservation can keep distant thin cutouts visible, with quantization limits in small mip levels.
Runtime measurements and backend checks establish costs and compatibility.
