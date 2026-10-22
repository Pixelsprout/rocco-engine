/*
The one translation unit of the miniaudio archive: miniaudio, and stb_vorbis
for .ogg. scripts/macos/build-miniaudio.sh, scripts/linux/build-miniaudio.sh
and scripts/windows/build_miniaudio.cmd compile it.

The host decodes each Sound itself, so it needs no resource manager.
MA_NO_NULL removes the null backend, so a machine with no audio device fails
ma_engine_init instead of opening a silent device.

MA_NO_SSE2 makes x64 normalize the Listener axes with an exact sqrt, as arm64
does. With SSE2, miniaudio uses rsqrtss, which is off by up to 4e-4, so an At
sound at its range still plays and the falloff is not linear.
*/
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_NULL
#define MA_NO_FLAC
#define MA_NO_MP3
#define MA_NO_ENCODING
#define MA_NO_SSE2

#define STB_VORBIS_HEADER_ONLY
#include "../../miniaudio/extras/stb_vorbis.c"

#define MINIAUDIO_IMPLEMENTATION
#include "../../miniaudio/miniaudio.h"

#undef STB_VORBIS_HEADER_ONLY
#include "../../miniaudio/extras/stb_vorbis.c"

/* engine/miniaudio.odin declares these layouts. They are equal on the three targets. */
_Static_assert(sizeof(ma_engine_config) == 256, "update Ma_Engine_Config in engine/miniaudio.odin");
_Static_assert(sizeof(ma_decoder_config) == 144, "update Ma_Decoder_Config in engine/miniaudio.odin");
_Static_assert(sizeof(ma_engine) == 1352, "update MA_ENGINE_SIZE in engine/miniaudio.odin");
_Static_assert(_Alignof(ma_engine) == 8, "update the alignment of Ma_Engine in engine/miniaudio.odin");
_Static_assert(sizeof(ma_sound) == 1016, "update MA_SOUND_SIZE in engine/miniaudio.odin");
_Static_assert(_Alignof(ma_sound) == 8, "update the alignment of Ma_Sound in engine/miniaudio.odin");
_Static_assert(sizeof(ma_audio_buffer_ref) == 112, "update MA_AUDIO_BUFFER_REF_SIZE in engine/miniaudio.odin");
_Static_assert(_Alignof(ma_audio_buffer_ref) == 8, "update the alignment of Ma_Audio_Buffer_Ref in engine/miniaudio.odin");
