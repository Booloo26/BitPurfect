# RateMatch

A macOS menu bar app that keeps your audio output device on the same sample rate as whatever
Apple Music is playing, so lossless tracks reach your DAC without Core Audio resampling them.

macOS never does this on its own: the output device stays on whatever rate Audio MIDI Setup was
last left on, and everything else is silently converted to match.

## How it works

Apple Music doesn't publish the sample rate of what it's playing through any API. It does log it,
though — Core Audio's ALAC decoder writes a line naming the rate and bit depth whenever it builds
a decoder:

```
ACAppleLosslessDecoder.cpp:681 (0x...) Input format: 2 ch, 96000 Hz, alac (0x00000003) from 24-bit source
```

RateMatch reads those lines and matches the output device to them.

Two details drive the whole design:

- **Detection runs `/usr/bin/log stream` as a subprocess**, not `OSLogStore` in-process.
  `OSLogStore` cannot be used either way round: a handle held across reads is a snapshot frozen
  at open time and never sees anything logged afterwards, while opening a fresh one per read
  leaks a `com.apple.loggingsupport.stream` thread every time — enough to reach 70 threads and
  stall completely. A subprocess is live by definition and gets fully reclaimed on exit.

- **Music logs a decoder line only when it *creates* a decoder**, then reuses it for every
  following track in the same format. Runs of many tracks log nothing at all, and resuming a
  paused track logs nothing. So a detected format is kept until a *different* one is reported,
  and a one-shot `log show` fills in the format when the app starts mid-track.

## Behaviour worth knowing

- **Rate choice respects clock family.** On a device that stops at 96 kHz, a 176.4 kHz source
  goes to 88.2 kHz (an exact 2:1 decimation), not to the numerically closer 96 kHz (a 1.8375:1
  resample). Output is always the source rate, an integer ratio of it, or — only if the device
  offers nothing in that family — the nearest rate it does support.
- **The rate is held, not just set.** If Audio MIDI Setup or another app moves the device's rate,
  RateMatch puts it back.
- **Anti-pop** holds a silent stream open on wired external DACs so they don't power their output
  stage down between tracks and click on the way back. While Music is playing it writes exact
  zeros, so a bit-perfect path stays bit perfect; when idle it writes dither at about -120 dBFS
  for DACs that watch for digital silence rather than an idle USB stream. It's skipped for
  built-in, Bluetooth and AirPlay output, which don't have the problem.
- **Lossy streams report no rate at all**, because only the lossless decoder logs one. The panel
  says so rather than guessing.

## Requirements

- Apple Silicon Mac. The build is arm64-only.
- Apple Music with Lossless enabled.
- An admin account is not required (this reads logs via `log`, not `OSLogStore`).

**Verified on macOS 27.0 only.** `LSMinimumSystemVersion` is 14.0 and nothing in the code needs
more than that — the Liquid glass theme is gated to macOS 26+ and falls back cleanly — but the log
line detection has not been tested on anything older, and Apple could change that line's wording
in any release. If detection stops working after a macOS update, that line is the thing to check.

## Building

```
make run      # build, bundle, sign, launch
make stop     # quit the app and its two helper processes
make icon     # regenerate AppIcon.icns from Packaging/GenerateIcon.swift
make clean
```

The app is signed with a **local self-signed certificate** (`RateMatch Dev`) and is **not
notarized**, which is fine for running it on the machine that built it. Gatekeeper will reject it
if you copy it to another Mac; that needs a Developer ID and a notarization pass.

Signing uses a stable local identity rather than ad-hoc (`codesign -s -`) on purpose: an ad-hoc
signature changes on every build, and anything macOS keys to the app's identity — such as a Login
Item approval — would need re-approving each time.

## Layout

| Path | What's in it |
| --- | --- |
| `Sources/RateMatch/Detection/` | `log stream` subprocess and the decoder-line parser; Now Playing bridge |
| `Sources/RateMatch/Engine/` | Rate decisions, display state |
| `Sources/RateMatch/Audio/` | Core Audio device access, rate selection, anti-pop stream |
| `Sources/RateMatch/UI/` | Menu bar panel and its four themes |
| `Packaging/` | `Info.plist`, icon generator, generated `.icns` |

The UI implements design 1a ("Minimal · one number, one verdict") from the Bit Perfect design
document; the icon is design 1d ("Sample bars"). The anti-pop, style and quit rows are additions
the mockups have no reason to show.
