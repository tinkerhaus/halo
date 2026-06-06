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
            owns the subsystems & wires them) · MenuBarMenu · HaloLog (file logger)
  Model/    Arc · Action (Step/Modifiers) · Halo (Spoke) · HaloConfig (Profile/VoiceConfig/WhenMatch)
            · LLMConfig (LLMProvider/Function/ContextConfig) · HaloStore (persistence) · KeyChord
  Input/    Summon (mouse-button trigger) · MouseHID · Keyboard (keystroke synthesis)
            · ActionRunner (runs a Step sequence) · ButtonRecorder · AXContext (text before caret)
            · ProcessTree (descendant-process match for `when`)
  Voice/    Voice (record → WhisperKit transcribe → inject)
  LLM/      LLMClient (OpenAI-compatible chat) · Keychain (API-key storage)
  Wheel/    WheelModel · WheelView · WheelController (presents the wheel, tracks the cursor)
  Views/    SettingsView · Components
Tests/HaloTests/   swift-testing unit tests (model & config logic)
```

Dependencies: **Yams** (YAML config), **WhisperKit** (on-device transcription).

### Domain model (value types, all `Codable`)

- **`Action`** = an ordered `[Step]`; a `Step` is `.key(code, modifiers)`, `.text`,
  `.paste(recent:)`, `.pause(ms)`, `.verb` (a dictation control — dictate/send/cancel/undo),
  `.bash` (a shell command), or `.function` (call a named LLM function). The one primitive a
  spoke performs.
- **`Spoke`** — `.performs(Action)` or `.opens(Halo)` (a nested ring, a "well" you
  dwell into).
- **`Halo`** (layout) = an `Arc` (span + orientation as integer degrees) + `radius` +
  `[Spoke]`. Recursive.
- **`Profile`** = name + app bundle IDs + a `Halo`, plus optional `finish` ring, per-app
  `context`, and a `when` (`WhenMatch`: a runtime `process`/`titleMatches` condition — a
  matching `when`-profile beats a plain one, so the same app can show different wheels).
- **`HaloConfig`** = `summonButton` + `voice` + `default` halo + `[Profile]`, plus optional
  `llm`, `functions`, and `context` — the whole config, persisted by `HaloStore`.
- **LLM layer** (`LLMConfig.swift`): an **`LLMProvider`** (an OpenAI-compatible endpoint —
  the API key is a Keychain `keyRef`, never in the file), a **`Function`** (a reusable prompt
  + variables a spoke calls by name), and a **`ContextConfig`** (how to fill `{context}` —
  lines before the caret via AX, or a `bash` command's stdout). Run by `AppController.runFunction`
  via `LLMClient`; degrades to passing the raw dictation through when nothing is configured.

### Interaction (in `WheelController`)

- The wheel is a borderless, non-activating `NSPanel` at `.statusBar` level that
  **ignores mouse events** — selection is computed purely from the cursor's angle, so
  the app underneath keeps focus and receives the keystroke.
- Arcs are never full circles; the leftover wedge is the cancel zone.
- Sub-rings (wells) **expand on dwell** into their own ring (own arc / radius / spokes);
  **rest at the center to back out** one level (the hub shows ↩ "Hold to go back").
  Release is always terminal (fire / dictate / cancel). Releasing at the **center
  dictates** at any depth (a finish ring's center sends instead).
- Voice mode (`config.voice.mode`): `handsFree` (release at center → session; press
  summon again to stop) or `pushToTalk` (hold at center; release to send). The hub
  itself becomes the recording UI (live waveform → "Transcribing…").

## Configuration

Everything lives in one **`~/Library/Application Support/Halo/config.yaml`** —
summon button, voice mode, the `default` wheel, per-app profiles, and (optionally) the
**LLM** engines and **functions**. It is:

- **watched on disk** and re-read on the next summon, so it can be hand-edited (by a
  person or an agent) with no restart;
- **self-documenting** — `HaloStore` re-emits a `#`-comment header describing the
  schema on every save;
- **lenient** — omit any field and it falls back to a default.

A spoke is `{ label, glyph, <one of>: key | text | steps | well }`. `glyph` is an SF
Symbol name. `key` is a readable chord string parsed by `KeyChord` — e.g. `"cmd+s"`,
`"ctrl+c"`, `"shift+tab"`, `"cmd+["`, `"up"`. Left/right mouse buttons are never
allowed as the summon button.

A step can also call an **LLM function**: `functions:` define named prompts; `llm:` defines the
OpenAI-compatible engines they run on (key in the Keychain via `keyRef`). The function takes the
dictation as input and can interpolate `{context}` captured from the focused app, and a profile's
`when:` condition can swap the wheel for what's running (e.g. a Claude-Code wheel in a terminal).
**Config-only for now** (no settings UI). The full schema lives in `skills/halo-config/SKILL.md`
and is mirrored in the `#`-header `HaloStore` re-emits on save.

## Voice / model distribution

Dictation uses WhisperKit. The model is **not bundled** — it's downloaded on first
launch from the Hugging Face repo `tinkerhaus/whisperkit-coreml`
(variant `openai_whisper-large-v3-v20240930_turbo`), so the `.app` stays small. Load
status (download %, ready, recording, transcribing) shows in the menu-bar menu.

## Updates — notify-only

Halo is self-signed / un-notarized, so macOS **App Management** blocks any in-place
self-update: a self-signed build has **no Team ID**, so macOS won't grant the
self-update exemption and the install fails with *"…was prevented from modifying the
applications."* So Halo bundles **no updater framework** — it just **notifies**.

`UpdateChecker` (an `@Observable` owned by `AppController`) fetches a tiny JSON manifest
**`docs/version.json`** from GitHub Pages, compares its `build` to the running
`CFBundleVersion`, and — when a newer build is out — shows a native alert with a
**Download** button (opens the releases page), plus *Remind Me Later* / *Skip This
Version*. It checks quietly on launch (at most once a day) and on demand via **Check for
Updates…** (in the menu-bar menu and the app menu). Nothing is downloaded or installed
in-app — the user grabs the new dmg and drags it into Applications, like the first time.

Cutting a release: bump `VERSION`/`BUILD` in `package.sh` (both env-overridable, e.g.
`VERSION=0.1.1 BUILD=2 ./package.sh`), build + dmg, upload it as a GitHub release, then
bump `build` (= the new `CFBundleVersion`) and `shortVersion` in `docs/version.json` and
push to `main`; Pages republishes the manifest.

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
- **Self-signed apps can't self-update in place.** A self-signed build has no Team ID,
  so macOS App Management refuses the self-update exemption and blocks any tool from
  replacing the bundle (*"…prevented from modifying the applications"*). That's why
  updates are notify-only (see **Updates**); true in-place auto-update would require a
  Developer ID + notarization.
- **`Bundle.module` is a launch-time landmine in a hand-assembled `.app`.** SwiftPM's
  generated accessor first looks for the resource bundle at `Bundle.main.bundleURL`
  (the `.app` *root*) and then falls back to a *hardcoded absolute build-machine path*
  (`/Users/.../​.build/.../Halo_Halo.bundle`) — and `Swift.fatalError`s if neither
  exists. On the build machine the fallback path resolves, so it "works"; on any other
  Mac it **traps on launch**. (This shipped once — the menu-bar icon evaluated
  `Bundle.module` during `MenuBarExtra` setup and the app couldn't open at all.) Fix:
  `package.sh` copies `Halo_Halo.bundle` into `Contents/Resources` and the app loads it
  via `Bundle.halo` (resolves `Bundle.main.resourceURL`, never traps), **not**
  `Bundle.module`. The bundle must live under `Contents/` — anything at the `.app` root
  (real dir *or* symlink) breaks the code-signature resource seal ("unsealed contents
  present in the bundle root", verify fails). Dependency resource bundles
  (`swift-transformers_Hub`, `swift-crypto_Crypto`) have the same root-seeking accessor,
  so they can't be shipped without breaking the seal — they're left out because neither
  is read on Halo's Whisper path (Hub's is only a tokenizer-config fallback that Whisper
  models don't trigger; Crypto's is an unused privacy manifest).
