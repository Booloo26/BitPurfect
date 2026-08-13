# BitPurfect

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

BitPurfect reads those lines and matches the output device to them.

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
  BitPurfect puts it back.
- **Anti-pop** holds a silent stream open on wired external DACs so they don't power their output
  stage down between tracks and click on the way back. While Music is playing it writes exact
  zeros, so a bit-perfect path stays bit perfect; when idle it writes dither at about -120 dBFS
  for DACs that watch for digital silence rather than an idle USB stream. It's skipped for
  built-in, Bluetooth and AirPlay output, which don't have the problem.
- **Lossy streams report no rate at all**, because only the lossless decoder logs one. The panel
  says so rather than guessing.

## Requirements

- **Apple Silicon Mac.** The build is arm64-only — see [Sharing it](#sharing-it) for why a
  universal binary isn't currently possible with this toolchain.
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

`make run` signs with a **local self-signed certificate** (`BitPurfect Dev`), which is fine on the
machine that built the app and rejected by Gatekeeper anywhere else. Create it once in Keychain
Access, or with `openssl req -x509 -newkey rsa:2048 -nodes -subj "/CN=BitPurfect Dev"
-addext "extendedKeyUsage=codeSigning"` imported via `security import`.

A stable local identity is used rather than ad-hoc (`codesign -s -`) on purpose: an ad-hoc
signature changes on every build, and anything macOS keys to the app's identity — a Login Item
approval, for instance — would need re-approving each time.

## Sharing it

|  | `make dist` | `make dist-adhoc` |
| --- | --- | --- |
| Needs | Apple Developer Program ($99/yr) | nothing |
| Recipient | double-clicks, it opens | must approve it once in System Settings |
| Output | notarized, stapled `.dmg` | ad-hoc signed `.dmg` |

Both produce `.build/dist/BitPurfect-<version>.dmg` containing the app, an `/Applications`
symlink, `LICENSE`, and `THIRD-PARTY-NOTICES.md`. That last file is not optional — the bundled
dependencies are MIT and BSD-3, and both require their copyright notices to accompany a binary.

The App Store is not an option: the now-playing bridge reaches a private framework through
`/usr/bin/perl`, which App Review rejects, and sandboxing would break log reading anyway.

### The notarized path

Once enrolled, create a **Developer ID Application** certificate, then store a notary credential
once:

```
xcrun notarytool store-credentials "notary" \
  --apple-id "you@example.com" --team-id TEAMID --password APP_SPECIFIC_PASSWORD
```

Then:

```
make dist DIST_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

That signs with hardened runtime (notarization refuses without it), builds the disk image,
submits and waits, staples the ticket so verification needs no network, and finishes with
`spctl -a -t install` as a check.

**Expect to test one thing.** Hardened runtime is the only part of this that hasn't been
exercised here, and it is exactly the kind of change that can break the perl → MediaRemote
bridge, which depends on loading a dylib into an Apple-signed binary. If now-playing detection
stops working under a hardened build, add an entitlements file granting
`com.apple.security.cs.disable-library-validation` and pass it with `--entitlements`.

### The free path

`make dist-adhoc` gives a valid but anonymous signature. Recipients will be blocked on first
launch and have to allow it explicitly:

1. Double-click the app; macOS refuses to open it.
2. **System Settings → Privacy & Security**, scroll to the message about BitPurfect, click
   **Open Anyway**.
3. Confirm.

Recent macOS removed the old right-click → Open shortcut, so this System Settings trip is the
only route. Anyone technical can instead strip the quarantine flag themselves:

```
xattr -d com.apple.quarantine /Applications/BitPurfect.app
```

### Why it's arm64-only

`swift build --arch arm64 --arch x86_64` fails when linking the x86_64 slice:

```
"__swift_FORCE_LOAD_$_swiftCompatibility56", referenced from: ...
ld: symbol(s) not found for architecture x86_64
```

The Swift back-deployment compatibility archives shipped with the Command Line Tools contain
**arm64 and arm64e slices only**, and the dependencies' older deployment targets pull those
archives in. Full Xcode ships the x86_64 slices; the Command Line Tools do not. So a universal
build needs Xcode installed.

In practice this matters less than it sounds: Intel Macs stop at macOS 15, this app's log-line
detection is only verified on macOS 27, and the toolchain now warns that x86_64 is deprecated for
recent deployment targets.

## Layout

| Path | What's in it |
| --- | --- |
| `Sources/BitPurfect/Detection/` | `log stream` subprocess and the decoder-line parser; Now Playing bridge |
| `Sources/BitPurfect/Engine/` | Rate decisions, display state |
| `Sources/BitPurfect/Audio/` | Core Audio device access, rate selection, anti-pop stream |
| `Sources/BitPurfect/UI/` | Menu bar panel and its four themes |
| `Packaging/` | `Info.plist`, icon generator, generated `.icns` |

The UI implements design 1a ("Minimal · one number, one verdict") from the Bit Perfect design
document; the icon is design 1d ("Sample bars"). The anti-pop, style and quit rows are additions
the mockups have no reason to show.
