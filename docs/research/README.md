# Research

Each note answers one question with outside evidence, on the date it gives.
A note decides nothing. A grilling and an ADR in `docs/adr/` decide.
The Status line at the top of each note says what happened next.

| Note | Question | Status |
| --- | --- | --- |
| [scaling.md](scaling.md) | What must change so that rocco runs more and bigger games? | Historical. The ADRs record each decision. |
| [lights.md](lights.md) | Is the 8-light cap too low, and how do other engines handle it? | Superseded by ADR 0033. |
| [cutout-shadows.md](cutout-shadows.md) | How do engines cast shadows from alpha-tested materials? | Implemented. See ADR 0027. |
| [godot-scene.md](godot-scene.md) | What does the Godot village reference contain? | Reference for `examples/village`. |
| [immersive-scene.md](immersive-scene.md) | What does rocco lack for the village scene? | Historical. `docs/IMMERSIVE-SCENE.md` holds the scope. |
| [texture-sharing.md](texture-sharing.md) | Should rocco share textures or build atlases first? | Sharing implemented. No atlas. |

Add a new note here as `<topic>.md`, with a Date line and a Status line under the title.
