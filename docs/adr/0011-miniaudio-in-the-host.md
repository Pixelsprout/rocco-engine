# 0011: miniaudio in the host

Status: accepted, 2026-10-22.

## Context

Milestone 20 gives the engine sound. The host needs a device, a mixer,
decoders for wav and ogg, a rate change for pitch, and a falloff with
distance. `docs/RESEARCH-SCALING.md` section 5a weighed three backends:
sokol `saudio`, miniaudio and FMOD Studio. Each native library costs an
archive per target and entries in the link catalogs: the macOS sysroot,
the Linux stubs and the Windows import libraries.

## Decision

- miniaudio 0.11.24 goes in the host as a submodule, built into one archive
  per target by our own scripts, in the same way as sokol. The Windows
  build uses `/Zl /GS-`, as sokol does.
- The engine binds the few `ma_engine` and `ma_sound` calls it needs in its
  own Odin file. It does not import `vendor:miniaudio`, which expects an
  archive inside the Odin install.
- miniaudio opens CoreAudio, ALSA, PulseAudio and WASAPI at run time. The
  catalogs gain `dlopen` and the thread symbols miniaudio calls, and no
  audio library.
- The host always creates an `ma_engine`. In Headless it has no device. If
  the device does not open, the host logs once and the run is silent.

## Considered options

- sokol `saudio`. Rejected: it gives one float stream and nothing above it,
  so the host would write the mixer, the decoders, the rate change, the
  falloff and a queue to the audio thread. It also links its audio
  libraries at build time: AudioToolbox on macOS, `libasound.so.2` on
  Linux and `ole32` on Windows. A Linux machine with no `libasound` would
  then fail to start the game, where miniaudio runs it silent.
- FMOD Studio. Rejected for the host: its EULA says the FMOD Engine is not
  distributed as part of a game engine. It can come later as an extension
  that a game author adds under their own licence.
- `MA_NO_RUNTIME_LINKING` on macOS. Deferred: it adds three frameworks to
  the sysroot catalog. The miniaudio manual says run-time linking may not
  pass Apple's notarization. No release step notarizes today.

## Consequences

- About 90k lines of third-party C ship in the host, against about 2.5k for
  `saudio`.
- When a release notarizes on macOS, set `MA_NO_RUNTIME_LINKING` there and
  add CoreFoundation, CoreAudio and AudioToolbox to the sysroot catalog.
- If the project wants to own its mixer in Odin, `saudio` becomes the
  better floor, and this decision reopens.
