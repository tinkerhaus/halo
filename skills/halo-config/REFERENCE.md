# Halo config.yaml — full reference

The whole file is one `HaloConfig`. Decoding is lenient: omit any field for its default.

## Top level

```yaml
summonButton: 4          # NSEvent button number. 2=middle, 3=back, 4=forward. 0/1 (left/right) NOT allowed.
sounds: true             # soft UI cues on summon / select / fire / send / cancel
voice:
  finish: <halo>         # the default finish ring shown after a dictation (see "Finish ring")
default: <halo>          # the wheel shown when no profile matches the frontmost app
profiles:                # per-app wheels; most specific (fewest apps) wins
  - name: "Terminal"
    apps: [com.apple.Terminal, com.googlecode.iterm2]
    halo: <halo>
    finish: <halo>       # optional; overrides voice.finish for these apps
```

(`default` was once called `fallback`; the old key is still read as a deprecated alias.)

## halo

A ring of spokes. Recursive (a spoke may open another halo).

```yaml
arc:
  spanDegrees: 200       # how wide the fan is. 0–330 (never a full circle; the gap = cancel wedge)
  centerDegrees: -90     # which way it points. -90 = straight up, 0 = right, 90 = down
radius: 124              # points from hub to each spoke
spokes: [ <spoke>, ... ] # MAX 7 (use a `well` to nest more)
center: [ <step>, ... ]  # optional: steps fired when you release at the hub (see "Center")
```

Use **integers** for `spanDegrees`, `centerDegrees`, `radius`.

## spoke

`{ label, glyph, <exactly one of>: key | text | steps | well }`

- `label` — short text under the icon.
- `glyph` — an **SF Symbol** name, e.g. `arrow.up`, `stop.circle`, `magnifyingglass`,
  `square.and.arrow.down`, `sparkles`. Invalid names render a `?`.
- exactly one action:
  - `key: "cmd+s"` — a single keystroke/chord (see "Key chords").
  - `text: "hello"` — type literal text.
  - `steps: [ ... ]` — an ordered sequence (see "Steps").
  - `well: { spokes: [ ... ] }` — a nested sub-ring (see "Wells").

```yaml
- { label: Stop, glyph: stop.circle, key: ctrl+c }
- { label: Greet, glyph: text.bubble, text: "Hello there" }
```

## Key chords

`key` is a readable string; the **last token is the key**, earlier tokens are modifiers.

- modifiers: `cmd` (command), `ctrl` (control), `opt` (option/alt), `shift`
- keys: `a`–`z`, `0`–`9`, `return`/`enter`, `esc`, `tab`, `space`, `delete`, `fwddelete`,
  `up`/`down`/`left`/`right`, `home`/`end`, `pageup`/`pagedown`, and `[ ] / \ ; ' , . - = ` `

Examples: `cmd+s`, `cmd+shift+z`, `ctrl+c`, `shift+tab`, `cmd+[`, `up`, `return`.

## Steps

An ordered list; each item is exactly one of:

```yaml
- key:   "cmd+s"        # a keystroke
- text:  "literal text" # type text
- paste: 0              # paste from clipboard history (0 = latest, 1 = previous, …)
- pause: 200            # wait N milliseconds before the next step
- do:    send           # a dictation verb: dictate | send | cancel | undo
- bash:  "echo hi"      # run a shell command (see "Bash")
```

**Dictation verbs (`do`)** only mean something mid-dictation:
- `dictate` — start a voice session (the hub becomes the live recording UI)
- `send` — inject the transcript you just dictated
- `cancel` — discard the recording without injecting
- `undo` — delete the last dictation you injected (works even where ⌘Z doesn't)

Compose them: `steps: [ {do: send}, {key: return} ]` types your words then presses Return.

## Bash (shell + scripting)

A `bash` step runs through your **login shell** (`zsh -lc`, so your PATH/tools resolve).
The dictation is passed as the env var **`$HALO_TRANSCRIPT`** (never string-interpolated, so
quotes/newlines are safe).

```yaml
- bash: "agy -p \"$HALO_TRANSCRIPT\""          # fire-and-forget: send the dictation to a CLI agent
- bash: "fix-grammar \"$HALO_TRANSCRIPT\"", inject: true   # type the command's stdout back
```

- `inject: true` — type the command's **stdout** back where you were dictating.
- `as: name` — save the command's stdout so a **later** step can read it as `$name`. Steps run
  in order; a step with `as:` waits for its command before the next step runs. Chain them:

```yaml
steps:
  - { bash: "clean \"$HALO_TRANSCRIPT\"", as: clean }   # step 1 → $clean
  - { bash: "summarize \"$clean\"", inject: true }       # step 2 uses step 1's output
```

A `bash` step also works on a normal wheel (no dictation) — `$HALO_TRANSCRIPT` is just empty.

## Wells (sub-rings)

A `well` spoke opens a nested ring. **Only provide `spokes`** — at runtime the sub-ring is
laid out on the *parent's* arc and radius, and a **Back** spoke is added automatically in the
slot where the well sits. So:

- a well holds **at most 6** spokes (Back reserves the 7th slot),
- its own `arc`/`radius` are ignored,
- you **dwell** on the well to open it and **dwell on Back** to return — same place, in and out.

```yaml
- label: Nav
  glyph: arrow.up.and.down.and.arrow.left.and.right
  well:
    spokes:
      - { label: Left,  glyph: arrow.left,  key: left }
      - { label: Right, glyph: arrow.right, key: right }
```

## Center (release-at-hub)

Release at the hub fires the halo's `center` steps. If you **omit** `center`, it starts a
**dictation** — that's the default for the action wheel and every well. A **finish ring must
set** `center` (otherwise releasing at its center would start a *new* dictation) — use
`[ {do: send} ]` to send what you dictated, or add a key to submit:

```yaml
center: [ {do: send}, {key: return} ]   # finish ring: send the dictation, then Return
```

## Finish ring

Shown after you stop a hands-free dictation — release on a spoke to commit. It's just a halo
(usually 2–3 spokes like Send / Send+Return / Cancel) whose `center` typically sends.

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

## Per-app matching

The frontmost app's bundle ID selects a profile (`apps: [bundleID]`). A profile listing fewer
apps wins over a broader one, so a single-app profile overrides a group it also belongs to.
Find a bundle ID with: `osascript -e 'id of app "Safari"'` or `mdls -name kMDItemCFBundleIdentifier /Applications/Safari.app`.

## Gotchas

- **Integers only** for `spanDegrees` / `centerDegrees` / `radius` — decimals serialize as
  scientific notation and read oddly.
- **The app rewrites the file** on any save and regenerates the `#` header; **hand-written
  comments elsewhere are lost**. Don't keep notes in the file.
- **Left/right mouse buttons (0/1) can't be the summon button** — they're needed for clicking.
- **Max 7 spokes per ring** (6 inside a well). Past that, flick targets get too cramped — nest.
- Edits apply on the **next summon** (the file is watched). No relaunch needed.
- `glyph` must be a valid SF Symbol; verify names against Apple's SF Symbols app.
