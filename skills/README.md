# Configure Halo with any LLM

[`halo-config/SKILL.md`](halo-config/SKILL.md) is **one self-contained file** that teaches an
LLM how to write your Halo `config.yaml`. No install machinery — use it however you like:

**Paste it.** Copy the file's contents into ChatGPT, Claude, or any chat, then ask:
> "Add a reopen-last-tab spoke to my Halo browser wheel."

**Point at it.** Give your agent the raw URL:
> https://raw.githubusercontent.com/tinkerhaus/halo/main/skills/halo-config/SKILL.md

**Install it (Claude Code).** It's also a valid skill — one file:
```bash
mkdir -p ~/.claude/skills/halo-config
curl -sL https://raw.githubusercontent.com/tinkerhaus/halo/main/skills/halo-config/SKILL.md \
  -o ~/.claude/skills/halo-config/SKILL.md
```

Either way, the LLM edits `~/Library/Application Support/Halo/config.yaml`; your changes apply
on the next summon.
