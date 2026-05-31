# Halo

**A mouse-summoned radial command wheel with voice dictation, for macOS.**

Hold a configured mouse button anywhere and a ring of *spokes* blooms at your cursor — flick
toward a spoke and release to fire it (a keystroke, a macro, or some text); release at the
**center** to dictate by voice; pull into the empty wedge to cancel. The wheel automatically
switches its layout based on the app you're in. Halo runs as a background menu-bar accessory
(no Dock icon) and targets **macOS 14+**.

## How it works

- **Summon** — hold your configured mouse button (a side button by default; left/right clicks are never allowed). A ring blooms at the cursor.
- **Fire** — flick toward a spoke and release. A spoke can be a single keystroke (`cmd+s`), a multi-step macro, literal text, or a **well** — a nested sub-ring you dwell into.
- **Dictate** — release at the center. The hub becomes a live waveform; speak, then summon again to stop. A **finish ring** previews the transcript and lets you choose *Send*, *Send + Return*, or *Cancel*. Transcription runs **on-device** (WhisperKit) — no audio leaves your Mac.
- **Per-app** — Halo picks a wheel layout (a *profile*) from the frontmost app, so your terminal, browser, and editor each get their own spokes.

Everything — the summon button, the wheels, per-app profiles, and the whole voice flow — is
described in a single human-editable config file, so you (or an AI agent) can reshape Halo
without touching code.

## Build & install

Requires the Swift toolchain (Xcode command-line tools) on macOS 14+.

```bash
swift build                 # debug build / type-check
./package.sh                # release build → build/Halo.app
mv build/Halo.app /Applications/ && open /Applications/Halo.app
```

Run `./create-dev-cert.sh` once to create a stable self-signed signing identity — it keeps your
macOS permission grants across rebuilds (an ad-hoc signature changes every build and silently
drops them).

## Permissions

Grant these in **System Settings → Privacy & Security**, then fully quit and relaunch Halo
(macOS caches permissions per process):

- **Accessibility** — intercept the summon button and synthesize keystrokes.
- **Input Monitoring** — read mouse side buttons via HID (drivers like Logitech Options+ remap them).
- **Microphone** — voice dictation.

## Configuration

Everything lives in one watched, self-documenting file:

```
~/Library/Application Support/Halo/config.yaml
```

It's re-read on the next summon (no restart) and re-emits a commented schema header on every
save. A spoke is `{ label, glyph, <one of>: key | text | steps | well }`, where `key` is a
readable chord like `"cmd+shift+z"`, `"ctrl+c"`, or `"up"`, and `glyph` is an SF Symbol name.

Dictation is driven by the same step vocabulary through `do:` verbs — `dictate`, `send` (inject
the transcript), `cancel`, `undo` — so a finish ring's center can be, for example,
`[ {do: send}, {key: return} ]` to send and submit in one motion. A `bash:` step runs a shell
command with your dictation in `$HALO_TRANSCRIPT`, so a spoke can pipe what you said to a CLI
or AI agent (and chain steps via `as:`).

**Let an AI agent configure it for you.** The [`halo-config` skill](skills/) teaches Claude
Code (or any agent) the full schema — install it, then just ask: *"add a reopen-last-tab spoke
to my browser wheel,"* or *"make a Slack profile for reactions and replies."*

## Voice model

Dictation uses [WhisperKit](https://github.com/argmaxinc/WhisperKit). The model is **not
bundled** — on first launch it downloads from the Hugging Face repo
[`tinkerhaus/whisperkit-coreml`](https://huggingface.co/tinkerhaus/whisperkit-coreml) (variant
`openai_whisper-large-v3-v20240930_turbo`), so the app stays small. Download progress and status
show in the menu-bar menu.

## Architecture

SwiftUI + Swift Package Manager (no Xcode project). Modern `@Observable` stores, value-type
models, and a model layer kept free of AppKit/CoreGraphics.

```
Sources/Halo/
  App/    HaloApp · AppController · MenuBarMenu
  Model/  Arc · Action (Step/Verb) · Halo (Spoke) · HaloConfig · HaloStore · KeyChord
  Input/  Summon · MouseHID · Keyboard · ActionRunner · ButtonRecorder · SystemAudio
  Voice/  Voice (record → WhisperKit → inject)
  Wheel/  WheelModel · WheelView · WheelController
  Views/  SettingsView · Components
```

Dependencies: [Yams](https://github.com/jpsim/Yams) (YAML config) and
[WhisperKit](https://github.com/argmaxinc/WhisperKit) (on-device transcription).

## License

Halo is **source-available** under the [PolyForm Noncommercial License 1.0.0](LICENSE.md) — free
to use, modify, and share for **non-commercial** purposes (personal, learning, research).
Commercial use is not permitted.

---

Part of [**tinkerhaus**](https://github.com/tinkerhaus).
