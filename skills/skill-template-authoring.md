---
description: How to author a portable SKILL-TEMPLATE.md manifest inside each CodeBundle (Skill Template). Use when adding or updating skill templates, preparing CodeBundles for registry.runwhen.com, or translating Robot Framework Tasks into AI-agent tool descriptions.
globs: "**/codebundles/**,**/SKILL-TEMPLATE.md,**/runbook.robot,**/sli.robot"
alwaysApply: false
---

# CodeBundle `SKILL-TEMPLATE.md` Authoring Guide

This guide covers how to add a `SKILL-TEMPLATE.md` manifest to a CodeBundle
**Skill Template**. The manifest is portable, AI-agent-friendly metadata that
lets any agent understand the bundle's tools, monitor, inputs, secrets, and
scripts without reading Robot Framework source first.

The runtime is unchanged. `runbook.robot`, `sli.robot`, and bash scripts remain
the source of truth. `SKILL-TEMPLATE.md` is additive and *points* at them.

---

## Skill Template vs Skill

| Layer | Location | File | What it is |
|---|---|---|---|
| **Skill Template** | CodeBundle in the codecollection repo | `SKILL-TEMPLATE.md` | Unconfigured authoring artifact with `${VAR}` placeholders |
| **Skill** | Rendered SLX (RunWhen workspace output) | `SKILL.md` | Fully configured instance produced by `runwhen-local` / workspace-builder |

**Authoring flow:**

```
codebundles/<name>/          runwhen-local / workspace-builder          SLX output
├── runbook.robot     ──►   binds variables + secrets from         ──►  SKILL.md
├── sli.robot               generation rules / workspaceInfo            (rendered Skill)
├── *.sh
└── SKILL-TEMPLATE.md       SLX = fully rendered Skill instance
    (Skill Template)
```

- **Skill Templates** live in the repo. Agents and authors edit them.
- **Skills** are rendered at generation time. An agent handed an SLX directory
  gets `SKILL.md` with concrete values, not `${AKS_CLUSTER}` placeholders.
- Do **not** commit rendered `SKILL.md` files into the codecollection repo.

This aligns with `registry.runwhen.com`, which surfaces **Skills** (rendered)
built from **Skill Templates** (repo CodeBundles).

---

## Terminology Mapping

Use the new terms in `SKILL-TEMPLATE.md` body copy. Keep Robot filenames and
platform fields unchanged.

| Existing term | New term in manifest | Where it appears |
|---|---|---|
| Robot Framework **Task** in `runbook.robot` | **Tool** | Each runbook task → one tool entry |
| Robot Framework **Task** in `sli.robot` | **Monitor check** | Each SLI task → one monitor sub-check |
| **SLI** / `sli.robot` / Service Level Indicator | **Monitor** | `runtime.monitor`, `## Monitor` section |
| **CodeBundle** (directory in repo) | **Skill Template** | The authoring artifact |
| Rendered SLX / configured CodeBundle | **Skill** | Output `SKILL.md` (not stored in repo) |
| Robot `[Documentation]` | Tool / monitor description | Frontmatter + per-entry prose |
| `RW.Core.Import User Variable` | **Input variable** | `## Inputs` table |
| `RW.Core.Import Secret` | **Secret** | `## Secrets` table |
| `RW.CLI.Run Bash File` (`bash_file=...`) | **Underlying script** | Per-tool reference |
| `RW.Core.Push Metric ... sub_name=<x>` | **Monitor sub-check** `<x>` | Per-monitor `Sub-metric name` line |
| `[Tags]` | Tool / monitor capability tags | Per-entry reference |

---

## File Location

Place `SKILL-TEMPLATE.md` at the root of each CodeBundle directory:

```
codebundles/<bundle-name>/
├── SKILL-TEMPLATE.md    <-- Skill Template manifest (author in repo)
├── README.md
├── runbook.robot
├── sli.robot            (if present)
├── <script>.sh
└── ...
```

One `SKILL-TEMPLATE.md` per CodeBundle. Describe both `runbook.robot` and
`sli.robot` in the same file when both exist.

---

## Required Frontmatter

```yaml
---
name: <codebundle-directory-name>
kind: skill-template
description: <one-sentence third-person summary>. Use when <trigger conditions>.
runtime:
  runbook: runbook.robot
  monitor: sli.robot      # omit if no sli.robot
  executor: worker
  entrypoint: /home/runwhen/robot-runtime/runrobot.sh
  base_image: rw-base-runtime
platforms: [Azure, AKS, Kubernetes]
resource_types: [aks_cluster]
access: read-only
---
```

| Field | Rules |
|---|---|
| `name` | Lowercase, hyphenated; equals the CodeBundle directory name |
| `kind` | Always `skill-template` for repo manifests |
| `description` | Third-person, <=200 chars, includes "Use when …" |
| `runtime.runbook` | Path to `runbook.robot` relative to bundle dir |
| `runtime.monitor` | Optional; path to `sli.robot`. File name stays `sli.robot` |
| `runtime.executor` | Always `worker` — the process inside the runtime image that runs Robot |
| `runtime.entrypoint` | `runrobot.sh` path from `rw-base-runtime` (`/home/runwhen/robot-runtime/`) |
| `runtime.base_image` | `rw-base-runtime` — ships worker binary + robot-runtime scripts |
| `platforms` | From Robot `Metadata    Supports    ...` |
| `resource_types` | Cloud/K8s resource(s) the bundle targets |
| `access` | `read-only` if all tool tags are `access:read-only`, else `read-write` |

**Do not** put `runner: ro` in frontmatter. `ro` is a devcontainer-only test
wrapper in `codecollection-devtools`; production execution is scheduled by the
platform **runner** (location orchestrator) and executed by the **worker**
inside the `rw-base-runtime` image via `runrobot.sh`, with `RW_PATH_TO_ROBOT`
pointing at the bound robot file under `/home/runwhen/collection/`.

Rendered `SKILL.md` (on the SLX) omits `kind: skill-template` and replaces
`${VAR}` placeholders with bound values from `configProvided` / `secretsProvided`.

---

## Body Sections (in order)

1. `# <Display Name>` — from Robot `Metadata    Display Name`
2. `## Summary` — 1–3 sentences mirroring README
3. `## Tools` — one subsection per `runbook.robot` task
4. `## Monitor` — only when `sli.robot` exists
5. `## Inputs` — all `RW.Core.Import User Variable` entries
6. `## Secrets` — all `RW.Core.Import Secret` entries
7. `## Outputs` — JSON artifacts and monitor metric
8. `## How to invoke` — production worker path, optional local dev (`ro`), standalone scripts
9. `## Source files` — scripts with one-line purpose

Keep under ~400 lines. Link to `README.md` for deeper context.

---

## `## Tools` Format

One entry per `*** Tasks ***` block in `runbook.robot`:

```markdown
### <Display title with `${VAR}` placeholders preserved>

<Verbatim `[Documentation]` text.>

- **Robot task name**: <code>Exact Task Name `${VAR}` ...</code>
- **Robot file**: `runbook.robot`
- **Underlying script**: `<bash_file>` (omit if pure Robot)
- **Tags**: `access:read-only`, `data:config`, ...
- **Reads**: `VAR1`, `VAR2`
- **Writes**: `artifact.json`
- **Issues raised**: issues via `RW.Core.Add Issue` when checks fail
```

Use `<code>...</code>` for robot task names so `` `${VAR}` `` backticks do not
break markdown.

---

## `## Monitor` Format

Only when `sli.robot` exists. The monitor is the registry's continuous health
scoring surface (formerly SLI).

```markdown
## Monitor

<Verbatim `sli.robot` top-level Documentation.>

- **Robot file**: `sli.robot`
- **Score range**: `0.0` (failing) to `1.0` (healthy)
- **Aggregation**: arithmetic mean of sub-checks below
- **Recommended interval**: `180s`

### Sub-checks

#### <Sub-check title>

<Verbatim `[Documentation]`.>

- **Robot task name**: <code>...</code>
- **Sub-metric name**: `<sub_name>`
- **Underlying script**: `<bash_file>` (if any)
- **Tags**: ...
- **Reads**: ...
- **Pass condition**: `<Evaluate expression>` (when present)
```

For cron-scheduler bundles (SLI template points at `cron-scheduler-sli`):

```yaml
runtime:
  monitor: cron-scheduler
```

```markdown
## Monitor

Cron-scheduler monitor. Platform invokes `## Tools` on `CRON_SCHEDULE`
and surfaces runbook issues rather than a numeric score.

- **Mode**: `cron-scheduler`
- **Default schedule**: `*/30 * * * *`
```

Do **not** list SLI tasks under `## Tools`. They belong under `## Monitor`.

---

## `## How to invoke` Format

Three invocation paths, in this order:

```markdown
## How to invoke

### Production (RunWhen runner / worker)

The platform **runner** schedules work on a location **worker**. The worker
image (`rw-base-runtime`) executes Robot via `runrobot.sh` with
`RW_PATH_TO_ROBOT` set to the bound path, e.g.
`/home/runwhen/collection/codebundles/<bundle-name>/runbook.robot`.

Tools and monitors are selected by the platform from the SLX `pathToRobot`
reference — not by invoking `ro` or bare `robot` locally.

### Local development (devcontainer only)

`ro` is a dev-time wrapper in `codecollection-devtools` for authoring and
manual test runs. It is **not** the enterprise runtime.

```bash
cd codebundles/<bundle-name>
export VAR=...
ro runbook.robot
```

### Standalone scripts (no Robot)

<bash invocations for individual tools when an agent cannot run Robot>
```

---

## Regeneration

Use the bundled generator after editing robot files:

```bash
python3 scripts/generate_skill_md.py /path/to/codecollection
python3 scripts/generate_skill_md.py /path/to/codecollection --bundle azure-aks-triage
```

Writes `SKILL-TEMPLATE.md` and removes legacy `SKILL.md` if present.

---

## Validation Checklist

- [ ] File is at `codebundles/<name>/SKILL-TEMPLATE.md` (not `SKILL.md`)
- [ ] Frontmatter includes `kind: skill-template`
- [ ] `name` matches directory name
- [ ] `description` is third-person with "Use when …"
- [ ] Every `runbook.robot` task has a `### Tool` entry
- [ ] If `sli.robot` exists, `## Monitor` lists all sub-checks with `sub_name`
- [ ] `## Inputs` / `## Secrets` cover all Robot imports (deduplicated)
- [ ] No rendered `SKILL.md` committed to the codecollection repo
- [ ] Robot files unchanged

---

## Common Mistakes

1. **Committing `SKILL.md` to the repo.** Only `SKILL-TEMPLATE.md` belongs in
   the codecollection. `SKILL.md` is workspace-builder's rendered output on the SLX.

2. **Renaming Robot files.** The manifest is additive; never rename
   `runbook.robot`, `sli.robot`, or `*.sh`.

3. **Listing SLI tasks as tools.** Monitor sub-checks go under `## Monitor`.

4. **Paraphrasing `[Documentation]`.** Copy verbatim from Robot source.

5. **Dropping `${VAR}` placeholders.** Required for template → skill rendering.

6. **Mixing template and skill terminology.** Repo = Skill Template /
   `SKILL-TEMPLATE.md`. SLX = Skill / `SKILL.md`.

7. **Using `runner: ro` in frontmatter.** `ro` is devcontainer-only. Production
   uses the platform runner + worker + `runrobot.sh` inside `rw-base-runtime`.
