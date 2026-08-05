# Agent Rules

This repository provides agent-agnostic rules for AI coding assistants. All
skill files live in `.agents/` and are symlinked into agent-specific directories
at setup time.

## Directory layout

```
.agents/              # Canonical rule files (agent-agnostic)
├── *.mdc             # Generated from skills/ by `task install-skills`
└── .gitignore        # Prevents committing generated .mdc files

.cursor/rules -> ../.agents   # Symlink for Cursor IDE
```

## Adding a new agent

To add rules support for another IDE or AI agent:

```bash
# Create a symlink from the agent's expected rules directory to .agents/
ln -s ../.agents .your-agent/rules
```

Common agent rule directories:

| Agent / IDE | Rules path | Symlink command |
|-------------|-----------|-----------------|
| Cursor | `.cursor/rules/` | `ln -s ../.agents .cursor/rules` |
| Windsurf | `.windsurf/rules/` | `ln -s ../.agents .windsurf/rules` |
| Cline / Roo Code | `.clinerules/` | *(flat file, see below)* |

> **Note:** Some agents (like Cline) use flat files rather than directories.
> For these, concatenate the relevant `.mdc` files into the agent's expected
> format rather than symlinking.

## Source of truth

Rule files are authored as Markdown in `skills/` and installed into `.agents/`
by `task install-skills` (part of `task setup`). The `.mdc` files in `.agents/`
are generated and should not be committed.

To refresh rules after updating skills:

```bash
task install-skills
```