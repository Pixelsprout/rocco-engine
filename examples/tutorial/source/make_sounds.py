# Writes the tutorial's Sounds as 16-bit mono wav files into each chapter app
# that loads them. Python standard library only. Run it from anywhere:
#   python3 examples/tutorial/source/make_sounds.py
#
# A Loop Speaker jumps from the last sample back to the first with no
# crossfade. So each looping Sound holds a whole number of periods of every
# tone in it, and its notes fade to zero before the end.

import math
import os
import struct
import wave

TUTORIAL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

# Each chapter app keeps its own copy, so it runs with no ROCCO_ASSETS.
CHAPTERS = ["08-sound", "09-gamepad", "10-animation"]

RATE = 48000
TAU = 2.0 * math.pi

# The music is 8 notes of half a second each, so it loops every 4 seconds.
NOTE_SECONDS = 0.5
MELODY = [261.63, 329.63, 392.0, 440.0, 392.0, 329.63, 293.66, 392.0]
MUSIC_SECONDS = NOTE_SECONDS * len(MELODY)

# The door of chapter 8 opens in 4/3 of a second, and Pip may need 2 seconds
# to walk to it from the last pickup. The creak must still play then, so that
# Pip cuts it short.
CREAK_SECONDS = 4.0


def write(path, samples):
    clipped = [round(max(-1.0, min(1.0, s)) * 32767) for s in samples]
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(struct.pack(f"<{len(clipped)}h", *clipped))


# A raised cosine from 1 down to 0 over the last `seconds` of a sound `length`
# seconds long, so the sound ends at exactly zero.
def tail(t, length, seconds):
    left = length - t
    if left >= seconds:
        return 1.0
    return 0.5 - 0.5 * math.cos(math.pi * max(left, 0.0) / seconds)


# Two quick rising notes, like a coin.
def blip():
    length = 0.25
    first = 0.07
    samples = []
    phase = 0.0
    for i in range(int(length * RATE)):
        t = i / RATE
        freq = 988.0 if t < first else 1319.0
        phase += TAU * freq / RATE
        attack = min(t / 0.002, 1.0)
        decay = 1.0 if t < first else math.exp(-(t - first) / 0.06)
        tone = math.sin(phase) + 0.2 * math.sin(3.0 * phase)
        samples.append(0.45 * attack * decay * tail(t, length, 0.005) * tone)
    return samples


# One second of whole-hertz tones, so it loops with no click.
def hum():
    samples = []
    for i in range(RATE):
        t = i / RATE
        wobble = 1.0 + 0.15 * math.sin(TAU * 3.0 * t)
        tone = 0.25 * math.sin(TAU * 100.0 * t) + 0.12 * math.sin(TAU * 150.0 * t) + 0.08 * math.sin(TAU * 200.0 * t)
        samples.append(wobble * tone)
    return samples


# A rough saw tone that bends slowly up and down, broken into grains like
# wood that sticks and slips. It plays once, so it needs no whole periods.
def creak():
    samples = []
    phase = 0.0
    for i in range(int(CREAK_SECONDS * RATE)):
        t = i / RATE
        freq = 110.0 + 40.0 * t / CREAK_SECONDS + 18.0 * math.sin(TAU * 0.7 * t)
        phase += TAU * freq / RATE
        grain = 0.55 + 0.45 * math.sin(TAU * 23.0 * t + 3.0 * math.sin(TAU * 1.9 * t))
        tone = sum(math.sin(k * phase) / k for k in range(1, 7))
        attack = min(t / 0.03, 1.0)
        samples.append(0.3 * attack * grain * tail(t, CREAK_SECONDS, 0.6) * tone)
    return samples


# A plucked note that fades to zero by the end of its half second.
def pluck(freq, t):
    attack = min(t / 0.005, 1.0)
    decay = math.exp(-t / 0.15)
    tone = math.sin(TAU * freq * t) + 0.3 * math.sin(TAU * 2.0 * freq * t)
    return 0.25 * attack * decay * tail(t, NOTE_SECONDS, 0.02) * tone


# The pad's tones are whole multiples of a quarter hertz, so each one ends a
# 4 second loop at the phase where it starts.
def music():
    samples = []
    note_samples = int(NOTE_SECONDS * RATE)
    for i in range(int(MUSIC_SECONDS * RATE)):
        t = i / RATE
        note = MELODY[i // note_samples]
        swell = 0.75 + 0.25 * math.sin(TAU * 0.5 * t)
        pad = 0.06 * swell * (math.sin(TAU * 130.75 * t) + math.sin(TAU * 196.0 * t))
        samples.append(pluck(note, (i % note_samples) / RATE) + pad)
    return samples


sounds = {"blip.wav": blip(), "creak.wav": creak(), "hum.wav": hum(), "music.wav": music()}
for chapter in CHAPTERS:
    folder = os.path.join(TUTORIAL, chapter, "assets", "sound")
    os.makedirs(folder, exist_ok=True)
    for name, samples in sounds.items():
        write(os.path.join(folder, name), samples)
