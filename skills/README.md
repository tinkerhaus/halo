# Halo agent skills

Skills that let an LLM coding agent (Claude Code, etc.) set up and customize **Halo** for
you — its config is the product, so an agent can do it all by editing one YAML file.

## `halo-config`

Teaches an agent the full `config.yaml` schema and how to edit it: spokes, per-app profiles,
wells, keystrokes/macros, dictation, and shell scripting. Once installed, just ask:

> "Add a spoke to my browser wheel that reopens the last closed tab."
> "Make a Slack profile with a wheel for reactions and thread replies."
> "When I dictate in my terminal, send it to my coding agent instead of pasting."

## Install (Claude Code)

```bash
# clone + copy the skill into your skills folder
git clone https://github.com/tinkerhaus/halo
mkdir -p ~/.claude/skills
cp -r halo/skills/halo-config ~/.claude/skills/
```

Or without cloning the whole repo:

```bash
mkdir -p ~/.claude/skills/halo-config
curl -sL https://github.com/tinkerhaus/halo/archive/refs/heads/main.tar.gz \
  | tar -xz -C ~/.claude/skills/halo-config --strip-components=3 halo-main/skills/halo-config
```

Restart your agent so it picks up the new skill. Then ask it to configure Halo.

## Use it without installing

Point your agent at the raw file:

> "Read https://raw.githubusercontent.com/tinkerhaus/halo/main/skills/halo-config/SKILL.md
> and use it to add a Save (⌘S) spoke to my Halo default wheel."

The agent edits `~/Library/Application Support/Halo/config.yaml`; your changes apply on the
next summon (the file is watched live).
