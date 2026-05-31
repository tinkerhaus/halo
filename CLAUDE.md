# Halo

Halo is a native macOS menu-bar app: a **mouse-summoned radial command wheel** with
voice dictation at its center. Hold a configured mouse button anywhere → a ring of
"spokes" blooms at the cursor → flick toward a spoke and release to fire it
(keystroke / macro / text); release at the center to dictate by voice; pull into the
empty wedge to cancel. The wheel auto-switches its layout based on the frontmost app.

SwiftUI + Swift Package Manager, no Xcode project. Targets **macOS 14+** (uses the
`@Observable` macro). Runs as a background accessory (no Dock icon).

## Build, run, install

```bash
swift build                 # debug build / type-check
./package.sh                # release build → build/Halo.app (ad-hoc or stable-signed)
mv build/Halo.app /Applications/ && open /Applications/Halo.app
```

- `./create-dev-cert.sh` (run once) creates a stable self-signed "Halo Developer"
  code-signing identity. `package.sh` picks it up so **TCC permissions persist across
  rebuilds** (Accessibility / Input Monitoring bind to the code signature hash; an
  ad-hoc signature changes every build and silently drops grants).
- After granting a permission, **fully quit and relaunch** — TCC caches per process.

## Permissions

Halo needs three (System Settings → Privacy & Security):

- **Accessibility** — intercept the summon button and synthesize keystrokes.
- **Input Monitoring** — read mouse side buttons via HID (drivers like Logitech
  Options+ remap them before they become normal events).
- **Microphone** — voice dictation.

## Architecture

```
Sources/Halo/
  App/      HaloApp (@main, MenuBarExtra + Settings) · AppController (NSApplicationDelegate,
            owns the subsystems & wires them) · MenuBarMenu
  Model/    Arc · Action (Step/Modifiers) · Halo (Spoke) · HaloConfig (Profile/VoiceConfig)
            · HaloStore (persistence) · KeyChord (chord-string parsing)
  Input/    Summon (mouse-button trigger) · MouseHID · Keyboard (keystroke synthesis)
            · ActionRunner (runs a Step sequence) · ButtonRecorder
  Voice/    Voice (record → WhisperKit transcribe → inject)
  Wheel/    WheelModel · WheelView · WheelController (presents the wheel, tracks the cursor)
  Views/    SettingsView · Components
```

Dependencies: **Yams** (YAML config), **WhisperKit** (on-device transcription).

### Domain model (value types, all `Codable`)

- **`Action`** = an ordered `[Step]`; a `Step` is `.key(code, modifiers)`, `.text`,
  `.paste(recent:)`, or `.pause(ms)`. This is the one primitive a spoke performs.
- **`Spoke`** — `.performs(Action)` or `.opens(Halo)` (a nested ring, a "well" you
  dwell into).
- **`Halo`** (layout) = an `Arc` (span + orientation as integer degrees) + `radius` +
  `[Spoke]`. Recursive.
- **`Profile`** = name + app bundle IDs + a `Halo`.
- **`HaloConfig`** = `summonButton` + `voice` + `fallback` halo + `[Profile]` — the
  whole config, persisted by `HaloStore`.

### Interaction (in `WheelController`)

- The wheel is a borderless, non-activating `NSPanel` at `.statusBar` level that
  **ignores mouse events** — selection is computed purely from the cursor's angle, so
  the app underneath keeps focus and receives the keystroke.
- Arcs are never full circles; the leftover wedge is the cancel zone.
- Sub-rings (wells) **expand on dwell**; resting at the center backs out. Release is
  always terminal (fire / dictate / cancel).
- Voice mode (`config.voice.mode`): `handsFree` (release at center → session; press
  summon again to stop) or `pushToTalk` (hold at center; release to send). The hub
  itself becomes the recording UI (live waveform → "Transcribing…").

## Configuration

Everything lives in one **`~/Library/Application Support/Halo/config.yaml`** —
summon button, voice mode, the fallback wheel, and per-app profiles. It is:

- **watched on disk** and re-read on the next summon, so it can be hand-edited (by a
  person or an agent) with no restart;
- **self-documenting** — `HaloStore` re-emits a `#`-comment header describing the
  schema on every save;
- **lenient** — omit any field and it falls back to a default.

A spoke is `{ label, glyph, <one of>: key | text | steps | well }`. `glyph` is an SF
Symbol name. `key` is a readable chord string parsed by `KeyChord` — e.g. `"cmd+s"`,
`"ctrl+c"`, `"shift+tab"`, `"cmd+["`, `"up"`. Left/right mouse buttons are never
allowed as the summon button.

## Voice / model distribution

Dictation uses WhisperKit. The model is **not bundled** — it's downloaded on first
launch from the Hugging Face repo `tinkerhaus/whisperkit-coreml`
(variant `openai_whisper-large-v3-v20240930_turbo`), so the `.app` stays small. Load
status (download %, ready, recording, transcribing) shows in the menu-bar menu.

## Conventions

- Modern SwiftUI: `@Observable` stores injected via `.environment(...)`; value-type
  models; no `ObservableObject`.
- Keep the model UI-agnostic (no AppKit/CoreGraphics types leak into `Model/`).
- Assets (app icon, menu-bar glyph) live in `Resources/`; the menu-bar glyph is a
  template image so macOS tints it to the menu bar.
- See `TODO.md` for parked work.

## Working on Halo (process)

- **Build often.** SwiftUI errors cascade; `swift build` after each change is cheap.
- To actually verify behavior you must run the real app: `./package.sh` → move to
  `/Applications` → relaunch. The wheel/voice can't be exercised from a debug binary
  without the bundle's Info.plist (permission usage strings) and a stable signature.
- After any change to permissions-related code, re-grant + relaunch (TCC caches).
- Keep changes idiomatic and match the surrounding style. Prefer small value types and
  one or two `@Observable` stores over many tiny ones.

## Pitfalls & gotchas (learned the hard way)

- **SwiftUI type-checker timeouts.** A `body` with heavy inline math (e.g. building
  `CGPoint`s from trig + casts) fails with "unable to type-check in reasonable time."
  Pull the math into small `private func` helpers with explicit types.
- **`@Observable` init ordering.** Inside `init`, don't reference one stored property
  via `self.` before all are set. Compute with locals, then assign once.
- **Background writes to `@Observable` state must hop to the main queue**
  (`DispatchQueue.main.async`) — e.g. WhisperKit/recording callbacks updating `Voice`.
- **Floating `NSPanel` HUDs:** use `.nonactivatingPanel`, `level = .statusBar`,
  `ignoresMouseEvents = true`, `hasShadow = false`, and a transparent hosting layer
  (`wantsLayer`, clear `backgroundColor`, `masksToBounds = false`). Draw any shadow in
  SwiftUI so it follows rounded corners.
- **`NSScreen.main` is the key-window screen, not the cursor's.** For cursor-anchored
  UI, find the screen containing `NSEvent.mouseLocation`.
- **Menu-bar icons** should be template images (`isTemplate = true`) so macOS tints
  them; load from `Bundle.module` (the target has `resources: [.process("Resources")]`).
- **YAML numbers:** Yams renders `Double` in scientific notation (`2e+2`). Use `Int`
  for whole-number config fields (degrees, radius) to keep the file clean.
- **Config round-trips drop user comments.** Any save re-serializes; the doc header is
  regenerated, but hand-written comments elsewhere are lost. That's expected.
- **Keystroke synthesis:** release modifiers before posting a key (a stuck ⌘ from a
  prior ⌘V turns `⏎` into `⌘⏎`). See `Keyboard.releaseModifiers()`.
- **Summon button:** never allow left/right (button 0/1) — they're needed for normal
  clicking. The recorder and `Summon` both reject them; the config self-heals.
- **Logs from ad-hoc/self-signed apps are filtered out of Console/`log show`.** If you
  need traces during dev, write to a file under `~/Library/Logs/Halo/` and `tail` it.
