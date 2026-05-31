---
name: halo-config
description: Configure the Halo macOS app — a mouse-summoned radial command wheel with on-device voice dictation — by editing its config.yaml. Use when the user wants to set up, customize, or add commands, wheels, spokes, per-app profiles, macros, dictation, or shell-scripting actions to Halo, or edit ~/Library/Application Support/Halo/config.yaml.
---

# Configure Halo (`config.yaml`)

Halo is a macOS menu-bar app: the user holds a mouse button anywhere → a ring of "spokes"
blooms at the cursor → they flick toward a spoke and release to fire it (a keystroke, a macro,
text, or a shell command); releasing at the **center** dictates by voice. The wheel
auto-switches its layout based on the frontmost app.

`config.yaml` is the single source of truth. Edit it to set up or change the user's wheels.

## The file

```
~/Library/Application Support/Halo/config.yaml
```

YAML. Edits apply on the user's **next summon** — the file is watched live (no restart, no UI).

## Editing it

1. Read the user's current file first. The app re-emits a `#`-comment header documenting the
   exact schema for their installed version — trust it over this doc if they ever differ.
2. Make the minimal change (add/edit a spoke, profile, finish ring…). Omit any field to take
   its default; the decoder is lenient.
3. Save, then tell the user to summon the wheel to test.

> ⚠️ The app **rewrites the whole file** when it saves (e.g. from its visual editor) and
> regenerates the header — so **any comments you add are dropped.** Don't store notes inside it.

---

## Schema

### Top level
```yaml
summonButton: 4          # mouse button (NSEvent #): 2=middle, 3=back, 4=forward. 0/1 (left/right) NOT allowed.
sounds: true             # soft UI cues on summon / select / fire / send
voice:
  finish: <halo>         # the finish ring shown after a dictation (see Wells/Center; a profile can override it)
default: <halo>          # the wheel shown when no profile matches the frontmost app
profiles:                # per-app wheels — the frontmost app's bundle ID picks one (fewest apps wins)
  - name: "Browser"
    apps: [com.apple.Safari, com.google.Chrome]
    halo: <halo>
    finish: <halo>       # optional; overrides voice.finish for these apps
```
(`default` was once `fallback`; the old key is still read as a deprecated alias.)

### halo — a ring of spokes
```yaml
arc:
  spanDegrees: 200       # fan width, 0–330 (never a full circle; the gap is the cancel wedge)
  centerDegrees: -90     # direction: -90 = up, 0 = right, 90 = down
radius: 124              # hub→spoke distance
spokes: [ <spoke>, … ]   # MAX 7 (nest a `well` for more)
center: [ <step>, … ]    # optional; release-at-hub action (see Center)
```
Use **integers** for `spanDegrees` / `centerDegrees` / `radius`.

### spoke — `{ label, glyph, <exactly one of>: key | text | steps | well }`
- `label` — short text under the icon.
- `glyph` — an **SF Symbol** name (`arrow.up`, `stop.circle`, `magnifyingglass`, `sparkles`…); invalid → `?`.
- one action:
  - `key: "cmd+s"` — a single keystroke (see Key chords).
  - `text: "hello"` — type literal text.
  - `steps: [ … ]` — an ordered sequence (see Steps).
  - `well: { spokes: [ … ] }` — a nested sub-ring (see Wells).

### Key chords
Readable string; **last token is the key**, earlier tokens are modifiers.
- modifiers: `cmd`, `ctrl`, `opt`, `shift`
- keys: `a`–`z`, `0`–`9`, `return`/`enter`, `esc`, `tab`, `space`, `delete`, `up`/`down`/`left`/`right`,
  `home`/`end`, `pageup`/`pagedown`, and `[ ] / \ ; ' , . - = ` `
- examples: `cmd+s`, `cmd+shift+z`, `ctrl+c`, `shift+tab`, `cmd+[`, `up`, `return`

### Steps — ordered list, each item one of
```yaml
- key:   "cmd+s"        # a keystroke
- text:  "literal"      # type text
- paste: 0              # paste clipboard history (0 = latest, 1 = previous, …)
- pause: 200            # wait N ms
- do:    send           # dictation verb: dictate | send | cancel | undo
- bash:  "echo hi"      # run a shell command (see Bash)
```
**`do` verbs** (mid-dictation): `dictate` start a session · `send` inject the transcript ·
`cancel` discard · `undo` delete the last injected dictation. Compose:
`steps: [ {do: send}, {key: return} ]` types your words then presses Return.

### Bash (shell + scripting)
Runs via the **login shell** (`zsh -lc`, so PATH/tools resolve). The dictation is in
**`$HALO_TRANSCRIPT`** (an env var — quotes/newlines are safe).
```yaml
- { bash: "agy -p \"$HALO_TRANSCRIPT\"" }                  # fire-and-forget
- { bash: "fix-grammar \"$HALO_TRANSCRIPT\"", inject: true } # type the command's stdout back
```
- `inject: true` — type the command's **stdout** back where you were.
- `as: name` — save stdout so a later step reads it as `$name` (the step waits for it). Chain:
```yaml
steps:
  - { bash: "clean \"$HALO_TRANSCRIPT\"", as: clean }   # $clean = cleaned text
  - { bash: "summarize \"$clean\"", inject: true }       # uses step 1's output
```
On a normal wheel (no dictation), `$HALO_TRANSCRIPT` is just empty.

### Wells (sub-rings)
A `well` spoke opens a nested ring. **Provide only `spokes`** — at runtime the sub-ring is laid
out on the *parent's* arc/radius, and a **Back** spoke is auto-added where the well sits (dwell
the well to open, dwell Back to return — same place in and out). So a well holds **at most 6**
spokes, and its own `arc`/`radius` are ignored.
```yaml
- label: Nav
  glyph: arrow.up.and.down.and.arrow.left.and.right
  well:
    spokes:
      - { label: Left,  glyph: arrow.left,  key: left }
      - { label: Right, glyph: arrow.right, key: right }
```

### Center (release-at-hub)
Releasing at the hub fires `center`. **Omit it → it starts a dictation** (the default for the
action wheel and every well). A **finish ring must set `center`** (else its center would
re-dictate) — usually `[ {do: send} ]`:
```yaml
center: [ {do: send}, {key: return} ]   # finish ring: send the dictation, then submit
```

---

## Examples

### Browser profile
```yaml
- name: Browser
  apps: [com.apple.Safari, com.google.Chrome, company.thebrowser.Browser, com.brave.Browser]
  halo:
    arc: { spanDegrees: 210, centerDegrees: -90 }
    radius: 124
    spokes:
      - { label: Back,    glyph: chevron.left,    key: cmd+[ }
      - { label: Forward, glyph: chevron.right,   key: cmd+] }
      - { label: Reload,  glyph: arrow.clockwise, key: cmd+r }
      - { label: New Tab, glyph: plus.square,     key: cmd+t }
      - { label: Close,   glyph: xmark.square,    key: cmd+w }
      - { label: Find,    glyph: magnifyingglass, key: cmd+f }
      - label: Tabs
        glyph: ellipsis.circle
        well:
          spokes:
            - { label: Address,  glyph: link,            key: cmd+l }
            - { label: Reopen,   glyph: arrow.uturn.left, key: cmd+shift+t }
            - { label: Next Tab, glyph: chevron.right.2, key: ctrl+tab }
```

### Terminal profile (with a finish ring that runs what you dictate)
```yaml
- name: Terminal
  apps: [com.apple.Terminal, com.googlecode.iterm2, com.mitchellh.ghostty]
  halo:
    arc: { spanDegrees: 210, centerDegrees: -90 }
    radius: 124
    spokes:
      - { label: Enter, glyph: return,      key: return }
      - { label: Up,    glyph: arrow.up,    key: up }
      - { label: Down,  glyph: arrow.down,  key: down }
      - { label: Tab,   glyph: arrow.right.to.line, key: tab }
      - { label: Esc,   glyph: escape,      key: esc }
      - { label: Stop,  glyph: stop.circle, key: ctrl+c }
  finish:
    arc: { spanDegrees: 200, centerDegrees: -90 }
    radius: 108
    spokes:
      - { label: Send only, glyph: arrow.up, steps: [ {do: send} ] }
      - { label: Cancel,    glyph: xmark,    steps: [ {do: cancel} ] }
    center: [ {do: send}, {key: return} ]   # release at center = type it + run it
```

### Default dictation finish ring
```yaml
voice:
  finish:
    arc: { spanDegrees: 200, centerDegrees: -90 }
    radius: 108
    spokes:
      - { label: Submit, glyph: return, steps: [ {do: send}, {key: return} ] }
      - { label: Cancel, glyph: xmark,  steps: [ {do: cancel} ] }
    center: [ {do: send} ]   # release at center = send as-is
```

### Send your dictation to an AI agent (add to a finish ring)
```yaml
- label: To Agent
  glyph: sparkles
  steps:
    - { bash: "agy -p \"$HALO_TRANSCRIPT\"" }   # replace `agy` with your CLI agent
```

### Run a command from a normal wheel
```yaml
- { label: Notes, glyph: note.text, steps: [ { bash: "open -a Notes" } ] }
```

---

## Rules & gotchas

- **Integers only** for `spanDegrees` / `centerDegrees` / `radius` (decimals serialize badly).
- `glyph` must be a real **SF Symbol** name; invalid names render a `?`.
- **Max 7 spokes per ring** (6 inside a well — Back takes a slot). Past that, nest a `well`.
- **Left/right mouse buttons (0/1) can't be the summon button.**
- The app **rewrites the file** on save and drops your comments — keep notes out of it.
- A `well` reuses its parent's arc/radius and auto-adds **Back**; the center **always dictates**.
- Edits apply on the **next summon** (watched live). No relaunch.

## Common bundle IDs
Terminal `com.apple.Terminal` · iTerm2 `com.googlecode.iterm2` · Ghostty `com.mitchellh.ghostty` ·
Safari `com.apple.Safari` · Chrome `com.google.Chrome` · Arc `company.thebrowser.Browser` ·
VS Code `com.microsoft.VSCode` · Xcode `com.apple.dt.Xcode` · Zed `dev.zed.Zed` ·
Slack `com.tinyspeck.slackmacgap` · Notes `com.apple.Notes`.
Find any app's ID: `osascript -e 'id of app "Slack"'`
