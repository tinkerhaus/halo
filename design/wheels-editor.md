# Wheels editor — design spec

A visual, **canvas-primary** editor for Halo's radial wheels, replacing hand-editing of
`config.yaml`. The wheel canvas is the centerpiece (direct manipulation for everything
spatial); a contextual inspector handles everything you can't drag (a spoke's action,
glyph, the app list). **`config.yaml` stays the source of truth** — the editor only
mutates `store.config`, and every UI label is a literal config key (no translation
layer). Prototype: `design/wheels-editor.html`.

## North star
What you edit *is* what you'll summon. The canvas renders the real wheel (same arc math,
same look), so there's no separate "preview" — the editor is WYSIWYG. Direct manipulation
is allowed **only for things expressible in YAML**: spoke order, arc span/center, radius.
Spoke screen-position is *computed* from the arc (never stored), so "drag a spoke" can
only mean reorder — which keeps the editor honest to the config.

## Information architecture (three regions, inside the Wheels pane)
`HSplitView`: **Targets rail | Canvas | Inspector**.

- **Targets rail** — `Default`, each `Profile` (icon + app count), `+ Add profile`, and the
  summon button. Selecting a target loads its halo onto the canvas.
- **Wheel | Finish ring segment** above the canvas. Every target owns two halos:
  - Default → `{ Wheel: config.default, Finish: voice.finish }`
  - Profile → `{ Wheel: profile.halo (always custom), Finish: profile.finish ?? inherits voice.finish }`
    A profile's Finish tab shows "Use default finish ring" with an **Override** button.
- **Breadcrumb** (`Terminal › More`) tracks well depth; click to climb out.

## Terminology (UI label == config key)
`fallback` → **renamed to `default`** in the real YAML key (lenient decoder keeps reading
`fallback` as a deprecated alias; file self-heals on next save). Everything else keeps its
config key as its UI label: Arc (Span/Center), Radius, Spokes, Label, Glyph, Key/Text/
Steps/Verb, Well, Center, Finish ring, Apps. "Wheel" stays an informal umbrella for a
`halo`; nothing else is renamed.

## Canvas (direct manipulation)
A purpose-built `WheelCanvas` SwiftUI view — *not* `WheelView` directly (that's coupled to
runtime state: recording/transcribing/finishing/levels/reveal animation). It shares the
visual language via an extracted `SpokeChip` style so editor and runtime look identical,
and reuses `Arc.placements` for layout.

- **Click spoke** → select (inspector populates; chip highlights).
- **Drag spoke along the arc** → reorder (snaps to nearest slot — moves its index).
- **Drag the ◇ arc-endpoint handles** → set `arc.span` (symmetric about center, snapped to 2°).
- **Drag the rotate knob** → set `arc.center` (rotate the whole fan).
- **Radius** → inspector slider (least-used; keeps the canvas uncluttered).
- **Double-click a well** → drill in (canvas swaps to the sub-halo; breadcrumb home).
- **Click hub** → select the Center (release-at-hub) action.
- **+ ghost slot** at the next arc position → add a spoke.
- **Delete** → select + ⌫, an inspector Delete, or drag a spoke into the empty wedge
  (thematic: the wedge already means cancel/remove at runtime).

## Inspector (contextual)
- **Nothing selected** → halo properties: Arc (span/center), Radius, + the Apps list (for
  a profile: bundle IDs with resolved icon/name; Add via running-apps picker / `.app` file
  picker / free-text bundle ID).
- **Spoke selected** → Label, Glyph (curated SF Symbol grid + live-validated free text),
  Type `Action | Well`, then:
  - *Action* → the **Step editor**. Single keystroke shows a prominent "Record shortcut"
    field (local `NSEvent` keyDown monitor → `KeyChord.format`). "Add step" reveals the
    full sequence (key · text · paste · pause · verb), each add/remove/reorder-able. Simple
    stays simple; macros are possible.
  - *Well* → "Edit well contents →" (drills in).
  - Action⇄Well conversion lives here (confirm on discarding a non-empty well).
- **Hub selected** → Center action: "Default (by context)" vs a custom step sequence.

## Persistence — draft + explicit Save  (revised per user feedback)
**No auto-save.** Edits mutate `store.draft` (a working copy on the store); nothing reaches
`config.yaml` until you press **Save** (`store.commitDraft()` → `config = draft` → write).
- The header shows **Unsaved changes** (orange) vs **Saved**, with a prominent **Save** (⌘S)
  and a **Discard** (`store.discardDraft()`).
- The draft lives on `HaloStore` (not the view) so unsaved edits survive closing the window
  or switching sidebar panes. `reload()` keeps a *clean* draft in sync with external edits;
  a dirty draft is preserved.
- (Earlier edit-in-place + per-edit Undo/debounced-save was replaced by this; `HaloStore.apply`
  was removed. The ~0.3s debounce on `save()` stays — harmless, and still helps non-editor
  config writes.)

## v1 scope
**In:** three-region layout; rail (Default + profiles + add/remove, summon button); Wheel|
Finish segment; canvas with select / drag-reorder / arc-handle / rotate / drill / hub /
add / delete; inspector (label, glyph picker, action+step editor with key recorder, text/
paste/pause/verb steps, Action⇄Well); halo props (arc/radius/center); profile name + apps
picker; finish-ring editing; edit-in-place + debounced save + undo.

**Later:** "▶ Test" (summon this halo on screen via `WheelController`); drag-to-wedge
delete; full SF Symbol browser; reorder-by-drag inside step list.

## Constraints
- **Max 7 spokes per halo** (`Halo.maxSpokes`). Past ~7 the flick targets get too cramped
  to hit; the **well** is the overflow valve. The editor enforces it (the `+` slot hides at
  7); a hand-edited config with more still loads, it just can't grow in the UI.

## Build order (vertical slices) — ALL BUILT, pending a real run-through
- **Slice A — DONE** canvas + navigation + edit-in-place. `WheelCanvas` renders the target's
  halo (rail + Wheel/Finish segment + breadcrumb + double-click-to-drill); inspector edits
  spoke **label/glyph** and halo **arc span/center + radius** live. Edits flow through
  `store.apply` (undoable, ⌘Z) + **debounced** `HaloStore.save()`.
- **Slice 3 — DONE** action / step editor. `KeystrokeRecorder` (local `NSEvent` keyDown →
  `KeyChord.format`) records a key step; full step list (key/text/paste/pause/verb) with
  add / remove / move.
- **Slice 4 — DONE** spatial canvas editing. Drag a spoke along the arc to reorder; drag the
  ◇ endpoint handles for `arc.span`; drag the rotate knob for `arc.center`; `+` ghost adds a
  spoke (capped at `Halo.maxSpokes`); delete via the inspector. Continuous drags collapse to
  one undo step.
- **Slice 5 — DONE** wells. Inspector `Action | Well` segmented type switch with a
  confirm-on-discard; drill via double-click / "Edit well contents"; a well's own arc/radius
  edit through the same inspector sliders when drilled in.
- **Slice 6 — DONE** profiles & finish rings. Add / rename / delete profile in the rail +
  inspector; apps editor (running-app menu · `.app` file picker · free-text bundle ID, with
  resolved icon/name); finish-ring inherit→**Override**→revert flow; `Default → Finish` edits
  the global `voice.finish`.

## New files / touched
- `Sources/Halo/Views/WheelsEditor.swift` — the editor (`WheelsEditor` + `WheelCanvas` +
  `WheelLayout` + `HaloPalette`).
- `Sources/Halo/Input/KeystrokeRecorder.swift` — keystroke capture for `key` steps.
- `Model/HaloConfig.swift` (`fallback`→`default` + alias), `Model/Halo.swift` (`maxSpokes`),
  `Model/Action.swift` (`Verb: CaseIterable`), `Model/HaloStore.swift` (`apply(_:undoManager:)`
  + debounced `save()`), `Views/MainWindow.swift` (wire `.wheels`).

## Known rough edges (verify / polish)
- **Gestures unproven at runtime** — tap-select vs double-tap-drill vs drag-reorder coexist
  on a chip; needs a real run to confirm they disambiguate cleanly.
- **Undo granularity** — text fields register one undo per keystroke (sliders/drags are
  grouped). Group text edits later.
- **Inherited-finish editing** — editing a profile's inherited finish ring via the canvas
  creates an override implicitly (the inspector's explicit "Override" is the signposted path).
- **External edits reset profile selection** — a hand-edit that the watcher reloads
  regenerates profile UUIDs, so the rail selection falls back to Default.
