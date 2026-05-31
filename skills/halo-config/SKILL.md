---
name: halo-config
description: Configure the Halo macOS app — a mouse-summoned radial command wheel with on-device voice dictation — by editing its config.yaml. Use when the user wants to set up, customize, or add commands, wheels, spokes, per-app profiles, macros, or dictation/scripting actions to Halo, edit ~/Library/Application Support/Halo/config.yaml, or mentions Halo's summon button, wheel, spokes, wells, or finish ring.
---

# Configuring Halo

Halo is a macOS menu-bar app: hold a mouse button anywhere → a ring of "spokes" blooms
at the cursor → flick toward a spoke and release to fire it (a keystroke, a macro, text,
or a shell command); release at the **center** to dictate by voice. The wheel
auto-switches its layout based on the frontmost app.

**`config.yaml` is the single source of truth.** Edit it and the change applies on the
**next summon** — the file is watched live, no restart, no UI needed.

## The file

```
~/Library/Application Support/Halo/config.yaml
```

It's YAML. **Read the top of the file first**: the app re-emits a `#`-comment header
documenting the exact schema for the installed version — that header is authoritative.

## Workflow

1. **Read** the config (the header documents the live schema; the body is the user's setup).
2. **Edit** — add or change a spoke, profile, finish ring, etc. Keep it minimal; omit any
   field to take its default (the decoder is lenient).
3. **Done** — next time the user summons the wheel, it's live. Tell them to summon to test.

> ⚠️ The app **rewrites the whole file** whenever it saves (e.g. from its visual editor)
> and regenerates the header — so **comments you add elsewhere are dropped**. Don't store
> notes in the file.

## Minimal example — add spokes to the default wheel

```yaml
default:
  arc: { spanDegrees: 200, centerDegrees: -90 }   # centerDegrees -90 = straight up
  radius: 124
  spokes:
    - { label: Save, glyph: square.and.arrow.down, key: cmd+s }
    - { label: Find, glyph: magnifyingglass,        key: cmd+f }
    - { label: Undo, glyph: arrow.uturn.backward,   key: cmd+z }
```

## Schema at a glance

- `summonButton` — mouse button (NSEvent #): `2`=middle, `3`=back, `4`=forward. **Left/right
  (0/1) are not allowed.**
- `sounds` — `true`/`false` (soft UI cues on summon / select / fire / send).
- `default` — the wheel shown when no profile matches the frontmost app.
- `profiles` — `[{ name, apps: [bundleID], halo, finish? }]`. The frontmost app picks one;
  **most specific (fewest apps) wins**.
- `voice.finish` — the finish ring shown after a dictation (a halo); a profile may override
  it with its own `finish`.
- **halo** = `{ arc: { spanDegrees, centerDegrees }, radius, spokes: [...], center? }`. Never
  a full circle — the empty wedge is release-to-cancel. **Max 7 spokes** (nest a `well` for more).
- **spoke** = `{ label, glyph, <exactly one of>: key | text | steps | well }`. `glyph` is an
  **SF Symbol** name (e.g. `arrow.up`, `stop.circle`).

Full details — every step type, `bash` scripting + output chaining, well/sub-ring behavior,
the center action, key-chord syntax, and per-app matching — are in **[REFERENCE.md](REFERENCE.md)**.
Paste-ready wheels (terminal, browser, editor, dictation finish ring, "send to an AI agent")
are in **[EXAMPLES.md](EXAMPLES.md)**.

## Rules you must not get wrong

- Use **integers** for `spanDegrees`, `centerDegrees`, `radius` (decimals serialize badly).
- `glyph` must be a real **SF Symbol** name; invalid names render a `?`.
- A **`well`** only needs `spokes` — its sub-ring reuses the *parent's* arc/radius, and a
  **Back** spoke is added automatically where the well sits. So a well holds at most **6**
  spokes, and its center (like every action ring) **always dictates**.
- `key` is a readable chord string: `cmd+s`, `ctrl+c`, `shift+tab`, `cmd+[`, `up`, `return`.
