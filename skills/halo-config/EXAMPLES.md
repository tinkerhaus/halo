# Halo — example wheels

Paste-ready snippets. Drop a profile into `profiles:`, or a halo into `default:` /
`voice.finish:`. Common bundle IDs are listed at the bottom.

## Terminal / agent profile

```yaml
- name: Terminal / Agent
  apps: [com.apple.Terminal, com.googlecode.iterm2, com.mitchellh.ghostty, dev.warp.Warp-Stable]
  halo:
    arc: { spanDegrees: 210, centerDegrees: -90 }
    radius: 124
    spokes:
      - { label: Enter, glyph: return,              key: return }
      - { label: Up,    glyph: arrow.up,            key: up }
      - { label: Down,  glyph: arrow.down,          key: down }
      - { label: Tab,   glyph: arrow.right.to.line, key: tab }
      - { label: Esc,   glyph: escape,              key: esc }
      - { label: Stop,  glyph: stop.circle,         key: ctrl+c }
      - label: More
        glyph: ellipsis.circle
        well:
          spokes:
            - { label: ⇧Tab,   glyph: arrow.left.to.line, key: shift+tab }
            - { label: Search, glyph: magnifyingglass,     key: ctrl+r }
            - { label: Clear,  glyph: delete.left,         key: ctrl+u }
            - { label: EOF,    glyph: eject,               key: ctrl+d }
  finish:
    arc: { spanDegrees: 200, centerDegrees: -90 }
    radius: 108
    spokes:
      - { label: Send only, glyph: arrow.up, steps: [ {do: send} ] }
      - { label: Cancel,    glyph: xmark,    steps: [ {do: cancel} ] }
    center: [ {do: send}, {key: return} ]   # release at center = send + Enter (run it)
```

## Browser profile

```yaml
- name: Browser
  apps: [com.apple.Safari, com.google.Chrome, company.thebrowser.Browser, com.brave.Browser]
  halo:
    arc: { spanDegrees: 210, centerDegrees: -90 }
    radius: 124
    spokes:
      - { label: Back,    glyph: chevron.left,      key: cmd+[ }
      - { label: Forward, glyph: chevron.right,     key: cmd+] }
      - { label: Reload,  glyph: arrow.clockwise,   key: cmd+r }
      - { label: New Tab, glyph: plus.square,       key: cmd+t }
      - { label: Close,   glyph: xmark.square,      key: cmd+w }
      - { label: Find,    glyph: magnifyingglass,   key: cmd+f }
      - label: Tabs
        glyph: ellipsis.circle
        well:
          spokes:
            - { label: Address,  glyph: link,             key: cmd+l }
            - { label: Next Tab, glyph: chevron.right.2,  key: ctrl+tab }
            - { label: Prev Tab, glyph: chevron.left.2,   key: ctrl+shift+tab }
```

## Editor / IDE profile

```yaml
- name: Editor / IDE
  apps: [com.microsoft.VSCode, com.apple.dt.Xcode, dev.zed.Zed]
  halo:
    arc: { spanDegrees: 210, centerDegrees: -90 }
    radius: 124
    spokes:
      - { label: Save,    glyph: square.and.arrow.down, key: cmd+s }
      - { label: Undo,    glyph: arrow.uturn.backward,  key: cmd+z }
      - { label: Redo,    glyph: arrow.uturn.forward,   key: shift+cmd+z }
      - { label: Find,    glyph: magnifyingglass,       key: cmd+f }
      - { label: Comment, glyph: text.bubble,           key: cmd+/ }
```

## Dictation finish ring (the default after voice)

```yaml
voice:
  finish:
    arc: { spanDegrees: 200, centerDegrees: -90 }
    radius: 108
    spokes:
      - { label: Submit, glyph: return, steps: [ {do: send}, {key: return} ] }
      - { label: Cancel, glyph: xmark,  steps: [ {do: cancel} ] }
    center: [ {do: send} ]   # release at center = send the text as-is (no Return)
```

## Send a dictation to an AI agent

Add this spoke to a `finish` ring. After you dictate, flick to it to pipe your words to a
CLI agent instead of pasting them. (Replace `agy` with your tool.)

```yaml
- label: To Agent
  glyph: sparkles
  steps:
    - { bash: "agy -p \"$HALO_TRANSCRIPT\"" }   # fire-and-forget
```

Or **transform** your dictation and type the result back:

```yaml
- label: Polish
  glyph: wand.and.stars
  steps:
    - { bash: "your-llm 'fix grammar, keep meaning' \"$HALO_TRANSCRIPT\"", inject: true }
```

Or **chain** steps (each reads the previous one's output):

```yaml
- label: Summarize
  glyph: list.bullet.rectangle
  steps:
    - { bash: "clean \"$HALO_TRANSCRIPT\"", as: clean }   # $clean = cleaned dictation
    - { bash: "summarize \"$clean\"", inject: true }       # type the summary back
```

## Run a command from a normal wheel (no dictation)

```yaml
- { label: Notes, glyph: note.text, steps: [ { bash: "open -a Notes" } ] }
```

## Common bundle IDs

| App | Bundle ID |
|---|---|
| Terminal | `com.apple.Terminal` |
| iTerm2 | `com.googlecode.iterm2` |
| Ghostty | `com.mitchellh.ghostty` |
| Safari | `com.apple.Safari` |
| Chrome | `com.google.Chrome` |
| Arc | `company.thebrowser.Browser` |
| VS Code | `com.microsoft.VSCode` |
| Xcode | `com.apple.dt.Xcode` |
| Zed | `dev.zed.Zed` |
| Slack | `com.tinyspeck.slackmacgap` |
| Notes | `com.apple.Notes` |

Find any app's ID: `osascript -e 'id of app "Slack"'`
