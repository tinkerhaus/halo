# Halo — to-do / parked

Things deferred to come back to.

## Polish
- [ ] **Waveform dynamics** — while dictating, the bars read as one uniform "blob"
      rather than per-syllable ups and downs. The envelope smoothing/gate calmed
      the jitter (good) but flattened the dynamic range. Want more visible
      variation: less flattening, wider dynamic range, and/or per-bar history that
      preserves transients. (`Voice.currentLevel()` + `WaveformView`.)
- [ ] **Ripple + sounds** — the liquid-glass ripple on the wheel and soft UI
      sounds (carried the design from Utter; not yet ported to Halo).

## Features
- [x] **Wheel editor UI** — built as the **Wheels** pane (`Views/WheelsEditor.swift`): a
      canvas-primary editor (rail · radial canvas · inspector) to assign / reorder / record /
      nest spokes, edit profiles & finish rings, all live on `store.config`. See
      `design/wheels-editor.md`. Pending a real run-through + the polish noted there.
- [ ] **Voice: cancel a session** — discard a recording without sending (e.g. Esc).
- [ ] **Voice: VAD auto-stop** — optional `voice.mode` that stops on silence.
- [ ] **Per-profile app list in UI** — currently seed-only / hand-edited in YAML.

## Distribution
- [ ] Model download has a menu-bar % readout; consider a first-run onboarding for
      the ~1.5 GB download + permission grants (Mic / Accessibility / Input Monitoring).
