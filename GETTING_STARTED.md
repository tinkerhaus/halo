# Getting started with Halo

Halo is a **mouse-summoned radial command wheel** for macOS. Hold a mouse button anywhere, a ring
of *spokes* blooms at your cursor, flick toward one and release to fire it — a keystroke, a macro,
some text, or a shell command. Release at the **center** to dictate by voice (transcribed
on-device). The wheel automatically switches its layout based on the app you're in.

This guide takes you from install to a customized wheel with voice dictation and — if you want —
AI functions. It assumes macOS 14 or later.

---

## 1. Install

**From a release (easiest):** download the latest `.dmg` from the
[releases page](https://github.com/tinkerhaus/halo/releases), open it, and drag **Halo** into
`/Applications`.

> Halo is self-signed (not notarized), so on first launch macOS may say it can't verify the
> developer. Right-click the app → **Open**, or run once:
> `xattr -dr com.apple.quarantine /Applications/Halo.app`

**From source:** with the Swift toolchain installed (Xcode command-line tools):

```bash
git clone https://github.com/tinkerhaus/halo.git && cd halo
./create-dev-cert.sh        # once — a stable signing identity so permissions persist across rebuilds
./package.sh                # release build → build/Halo.app
mv build/Halo.app /Applications/ && open /Applications/Halo.app
```

Halo runs in the **menu bar** (look for the ring glyph) — there's no Dock icon.

---

## 2. Grant permissions

Open **System Settings → Privacy & Security** and grant Halo:

- **Accessibility** — to intercept the summon button and type keystrokes for you.
- **Input Monitoring** — to read mouse side-buttons (drivers like Logitech Options+ remap them).
- **Microphone** — for voice dictation.

> After granting a permission, **fully quit and relaunch Halo** — macOS caches permission state per
> running process, so a grant only takes effect on the next launch.

The first launch also downloads the on-device dictation model (~1.5 GB, once) from Hugging Face,
then prepares it for your Mac's Neural Engine. **The first prep can take a few minutes** — watch the
menu-bar menu for progress (`Downloading…` → `Optimizing…` → `Ready`). You can use the wheel for
keystrokes immediately; dictation lights up when it's ready.

---

## 3. Summon the wheel and fire a spoke

1. **Hold** your summon button (default: the **forward** side button) anywhere. A ring blooms at the
   cursor.
2. **Flick** toward a spoke and **release** to fire it.
3. **Pull into the empty wedge** (the gap in the ring) and release to **cancel** — nothing fires.

Out of the box you get a sensible default wheel, and app-specific wheels for browsers, terminals,
and editors. Switch to Safari and summon — you'll see Back/Forward/Reload/New-Tab/Find spokes.

---

## 4. Dictate by voice

1. Summon and **release at the center** (the hub). The hub becomes a live waveform — **speak**.
2. **Summon again** to stop. A **finish ring** appears with a preview of your transcript.
3. Flick to **Send** (type it where your cursor was), **Send + Return**, or **Cancel**.

Everything is on-device — no audio leaves your Mac.

---

## 5. Customize your wheels

There are two ways to shape Halo, and they edit the same thing:

**A. The visual editor.** Click the menu-bar icon → **Open Halo** → the **Wheels** pane. Drag to
reorder spokes, record keystrokes, nest sub-rings, and edit per-app profiles — all live.

**B. The config file.** Everything lives in one human-editable, self-documenting file:

```
~/Library/Application Support/Halo/config.yaml
```

It's **watched live** — save it and the change applies on your next summon (no restart). Every save
re-emits a commented `#` header documenting the exact schema, so the file teaches you as you go.

A spoke is `{ label, glyph, <one of>: key | text | steps | well }`:

```yaml
- { label: Save,   glyph: square.and.arrow.down, key: cmd+s }      # one keystroke
- { label: Sig,    glyph: signature,              text: "— Sent from Halo" }   # literal text
- { label: Search, glyph: magnifyingglass,        steps: [ { key: cmd+l }, { text: "halo" }, { key: return } ] }
```

`glyph` is an [SF Symbol](https://developer.apple.com/sf-symbols/) name; `key` is a readable chord
like `cmd+shift+z`, `ctrl+c`, or `up`.

> **Let an agent do it.** Install the [`halo-config` skill](skills/halo-config/SKILL.md) and ask
> Claude Code (or any agent): *"add a reopen-last-tab spoke to my browser wheel."* The skill teaches
> the full schema.

---

## 6. Per-app profiles

A **profile** binds a wheel to a set of apps by bundle ID; the frontmost app picks one (most
specific — fewest apps — wins):

```yaml
profiles:
  - name: Terminal
    apps: [com.apple.Terminal, com.googlecode.iterm2, com.mitchellh.ghostty]
    halo:
      arc: { spanDegrees: 210, centerDegrees: -90 }
      radius: 124
      spokes:
        - { label: Enter, glyph: return,      key: return }
        - { label: Stop,  glyph: stop.circle, key: ctrl+c }
        - { label: Up,    glyph: arrow.up,    key: up }
```

Find any app's bundle ID with `osascript -e 'id of app "Slack"'`.

---

## 7. AI functions (optional)

Halo can send your dictation to an LLM and type the reply back — *clean up*, *translate*, *answer*.
This is **config-only for now** (no settings UI yet), and it's safe to add incrementally: with no
model configured, a function call just passes your words through untouched.

**a. Point Halo at a model.** Any OpenAI-compatible endpoint works — a local server (Ollama, LM
Studio, vLLM) needs no key:

```yaml
llm:
  providers:
    local: { base: "http://localhost:11434/v1", model: "llama3.1" }
  default: local
```

For a cloud provider, store the key in the **Keychain** (never in the file) and reference it:

```bash
security add-generic-password -s Halo -a openai -w sk-your-key-here
```
```yaml
llm:
  providers:
    openai: { base: "https://api.openai.com/v1", model: "gpt-4o-mini", keyRef: "openai" }
  default: openai
```

**b. Define a function** — a name and a prompt. The dictation is its input:

```yaml
functions:
  clean:     { prompt: "Clean up this dictation — fix grammar and remove filler. Output only the text." }
  translate: { prompt: "Translate to {lang}. Output only the translation.", variables: { lang: French } }
```

**c. Call it from a spoke.** On your dictation finish ring, add a spoke whose step is the function
name — it cleans up what you said and types it in:

```yaml
- { label: Clean up, glyph: sparkles, steps: [ clean ] }
- { label: To French, glyph: globe,   steps: [ { translate: { lang: French } } ] }
```

**Context.** A function's prompt can include `{context}` — text pulled from the app you're dictating
into (lines before your cursor, or a shell command's output). And `when:` rules let the *same* app
show a different wheel depending on what's running — e.g. a Claude-Code wheel that appears only when
`claude` is running in your front terminal. See the
[`halo-config` skill](skills/halo-config/SKILL.md) → **AI functions** for the full schema.

---

## Where to go next

- **[`halo-config` skill](skills/halo-config/SKILL.md)** — the complete config schema (the agent can
  read it and configure Halo for you).
- The **`#` header** at the top of your `config.yaml` — always matches your installed version.
- **[README](README.md)** — architecture, build details, and how updates work.

Happy summoning. 🌀
