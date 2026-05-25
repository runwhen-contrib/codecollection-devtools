---
description: How to author a portable SKILL.md manifest inside each CodeBundle so any AI agent can discover its tools, required variables, secrets, and underlying scripts. Use when adding or updating a SKILL.md for a CodeBundle, when preparing CodeBundles to be consumed as AI Agent Skills, or when translating Robot Framework Tasks into AI-agent tool descriptions.
globs: "**/codebundles/**,**/SKILL.md,**/runbook.robot,**/sli.robot"
alwaysApply: false
---

# CodeBundle `SKILL.md` Authoring Guide

This guide covers how to add a `SKILL.md` manifest to a CodeBundle.
The `SKILL.md` is a portable, AI-agent-friendly description that lets
any agent invoke the bundle's tools without first having to read the
Robot Framework source.

The runtime is unchanged. `runbook.robot`, `sli.robot`, and the bash
scripts remain the source of truth. `SKILL.md` is an additive manifest
that *points* at them.

---

## Terminology Mapping

CodeBundles are being repositioned as AI Agent Skills. Use the new
terms in `SKILL.md` body copy and section names, but keep filenames,
Robot identifiers, and platform fields unchanged.

| Existing term | New term in `SKILL.md` | Where it appears |
|---|---|---|
| Robot Framework **Task** in `runbook.robot` (line under `*** Tasks ***`) | **Tool** | Each runbook task becomes one tool entry |
| Robot Framework **Task** in `sli.robot` (a `RW.Core.Push Metric` step) | **Monitor check** | Each SLI task becomes one monitor sub-check |
| **SLI** / `sli.robot` / Service Level Indicator | **Monitor** | Frontmatter `runtime.monitor`, `## Monitor` body section |
| **CodeBundle** (directory in repo) | **Skill Template** | The unconfigured authoring artifact |
| Configured / rendered / runtime CodeBundle (vars + secrets bound) | **Skill** | What an agent actually invokes |
| Robot `Documentation`, `[Documentation]` | Tool / monitor description | Frontmatter description + per-tool prose |
| `RW.Core.Import User Variable` | **Input variable** | `## Inputs` table |
| `RW.Core.Import Secret` | **Secret** | `## Secrets` table |
| `RW.CLI.Run Bash File` (`bash_file=...`) | **Underlying script** | Per-tool reference |
| `RW.Core.Push Metric ... sub_name=<x>` | **Monitor sub-check** `<x>` | Per-monitor `Score dimension` line |
| `[Tags]` (`access:read-only`, `data:config`, …) | Tool / monitor capability tags | Per-tool reference |

This mapping aligns with the public vocabulary used by
`registry.runwhen.com`, where bundles are surfaced as **Skills** with
**Tools** (diagnostic/remediation actions) and **Monitors** (continuous
health scoring). Use these new terms in `SKILL.md` body copy so an
agent can talk about the bundle in registry-consistent language.

`SKILL.md` MUST NOT rename the Robot files themselves -- `runbook.robot`,
`sli.robot`, and the script names stay exactly as they are. The
manifest only re-describes them in the new vocabulary.

---

## File Location

Place `SKILL.md` at the root of each CodeBundle directory, alongside
`runbook.robot`:

```
codebundles/<bundle-name>/
├── SKILL.md           <-- manifest
├── README.md
├── runbook.robot
├── sli.robot          (if present)
├── <script>.sh
└── ...
```

One `SKILL.md` per CodeBundle. Do not create a separate manifest for
`sli.robot`; describe both robots inside the same file.

---

## Required Frontmatter

```yaml
---
name: <codebundle-directory-name>
description: <one-sentence third-person summary>. Use when <trigger conditions>.
runtime:
  runbook: runbook.robot
  monitor: sli.robot      # omit if the bundle has no sli.robot
  runner: ro              # the in-repo wrapper; falls back to `robot`
platforms: [<Azure|AWS|GCP|Kubernetes|...>]
resource_types: [<aks_cluster|deployment|s3_bucket|...>]
access: read-only         # or read-write if any tool mutates state
---
```

### Field rules

| Field | Rules |
|---|---|
| `name` | Lowercase, hyphenated, must equal the CodeBundle directory name |
| `description` | Third-person ("Triages…", "Checks…"), <=200 chars. Always include "Use when …" trigger phrase |
| `runtime.runbook` | Path to `runbook.robot` relative to the bundle directory |
| `runtime.monitor` | Optional; path to `sli.robot` if the bundle has one. The file name stays `sli.robot`; only the manifest key uses the new "Monitor" term |
| `runtime.runner` | Always `ro` for this devcontainer; agents may fall back to `robot` |
| `platforms` | Pull from Robot `Metadata    Supports    ...` line |
| `resource_types` | The cloud/Kubernetes resource(s) the bundle targets |
| `access` | `read-only` if every tool tag is `access:read-only`, else `read-write` |

---

## Body Sections (in this order)

1. `# <Display Name>` -- copy from Robot `Metadata    Display Name`
2. `## Summary` -- 1-3 sentence what + why, mirroring the README
3. `## Tools` -- one subsection per Robot Task in `runbook.robot` (see below)
4. `## Monitor` -- present **only** when `sli.robot` exists. Describes
   the continuous health-scoring monitor and lists each sub-check
5. `## Inputs` -- table of every `RW.Core.Import User Variable`
6. `## Secrets` -- table of every `RW.Core.Import Secret`
7. `## Outputs` -- artifacts produced (JSON files, report sections,
   monitor metric)
8. `## How to invoke` -- preferred runner + standalone-script fallback
9. `## Source files` -- bullet list of every script with one-line purpose

Keep the manifest under ~400 lines. Link to `README.md` for deeper
narrative context rather than duplicating it.

---

## `## Tools` Section Format

Every entry under `*** Tasks ***` in `runbook.robot` becomes one tool.
Tasks in `sli.robot` are described separately under `## Monitor`. Use
this template per tool:

```markdown
### <Display title with placeholders preserved>

<Verbatim text from the task's `[Documentation]` line.>

- **Robot task name**: `<exact name including ${VAR} placeholders>`
- **Robot file**: `runbook.robot`
- **Underlying script**: `<bash_file>` (omit if pure Robot)
- **Tags**: `access:read-only`, `data:config`, ...
- **Reads**: `<inputs the tool consumes>`
- **Writes**: `<JSON artifacts the tool produces>`
- **Issues raised**: <short list of `RW.Core.Add Issue` titles, or "none">
```

Rules:

- Preserve the **exact** Robot task name (with `` `${VAR}` `` markers)
  so an agent can map the tool back to the runbook entry.
- Pull the description verbatim from `[Documentation]`. Do not
  paraphrase or add new content.
- Tags are copied as a comma-separated list from the `[Tags]` line.

---

## `## Monitor` Section Format

Include this section **only** when the bundle has an `sli.robot`. The
monitor produces a continuous 0-1 health score and is the registry's
"Monitor" surface for the skill.

```markdown
## Monitor

<Verbatim text from `sli.robot`'s top-level `Documentation` metadata.>

- **Robot file**: `sli.robot`
- **Score range**: `0.0` (failing) to `1.0` (healthy)
- **Aggregation**: arithmetic mean of the sub-checks below
- **Recommended interval**: `<intervalSeconds from the SLI template, e.g. 180s>`
- **Tags**: `<comma-separated tags shared across sub-checks, if any>`

### Sub-checks

Each entry maps to a `*** Tasks ***` block in `sli.robot` that calls
`RW.Core.Push Metric ... sub_name=<x>`.

#### <Display title of the sub-check, with placeholders preserved>

<Verbatim text from the SLI task's `[Documentation]` line.>

- **Robot task name**: `<exact task name>`
- **Sub-metric name**: `<sub_name from RW.Core.Push Metric>`
- **Underlying script**: `<bash_file>` (omit if pure Robot)
- **Tags**: `<comma-separated tags from [Tags]>`
- **Reads**: `<inputs the sub-check consumes>`
- **Pass condition**: `<the boolean expression that yields 1 vs 0>`
```

Rules:

- One `#### <sub-check>` block per `*** Tasks ***` entry in `sli.robot`
  that pushes a metric.
- The aggregate `RW.Core.Push Metric` (no `sub_name`) is the monitor's
  primary score; do not add a separate sub-check entry for it.
- If `sli.robot` points at the cron-scheduler pattern (its `pathToRobot`
  in the SLI template is `codebundles/cron-scheduler-sli/sli.robot`),
  set `runtime.monitor: cron-scheduler` instead of a file path and use
  this short body in place of sub-checks:

  ```markdown
  ## Monitor

  Cron-scheduler monitor. The platform invokes `## Tools` on a fixed
  schedule (`CRON_SCHEDULE`) and surfaces issues raised by the runbook
  rather than a continuous numeric score.

  - **Mode**: `cron-scheduler`
  - **Default schedule**: `*/30 * * * *`
  ```

---

## `## Inputs` Table

One row per `RW.Core.Import User Variable` block in `runbook.robot`
and `sli.robot` (deduplicated by name).

```markdown
| Name | Type | Description | Default | Required |
|---|---|---|---|---|
| `AZ_RESOURCE_GROUP` | string | The resource group to perform actions against. | — | yes |
| `RW_LOOKBACK_WINDOW` | string | Time window in minutes to look back for activities/events. | `60` | no |
```

- `Type` comes from the `type=` argument (`string`, `int`, etc.).
- `Description` is the Robot `description=` value, verbatim.
- `Default` is the `default=` value, or `—` when none is set.
- `Required` is `yes` when no default is provided, `no` otherwise.

---

## `## Secrets` Table

One row per `RW.Core.Import Secret`.

```markdown
| Name | Description | Required |
|---|---|---|
| `azure_credentials` | Secret with `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_SUBSCRIPTION_ID` | yes |
```

For `kubeconfig`, note the file-mount semantics in the Description.

---

## `## How to invoke`

Provide two paths so agents without Robot Framework still have a way in.

```markdown
### Preferred: Robot Framework runner (`ro`)

```bash
cd codebundles/<bundle-name>
export AZ_RESOURCE_GROUP=...
export AKS_CLUSTER=...
ro runbook.robot
```

### Standalone scripts (no Robot)

Each tool is also runnable as a plain bash script. Set the variables
listed in `## Inputs`, then invoke the matching script from `## Tools`:

```bash
export AZ_RESOURCE_GROUP=...
export AKS_CLUSTER=...
bash aks_resource_health.sh   # produces az_resource_health.json
```
```

The standalone path lets an external AI agent run individual tools
without parsing Robot output, which is the primary reason this manifest
exists.

---

## Authoring Workflow

When adding a `SKILL.md` to an existing CodeBundle:

1. Read `runbook.robot` end-to-end. List every entry under
   `*** Tasks ***` and every `RW.Core.Import User Variable` /
   `RW.Core.Import Secret` in `Suite Initialization`.
2. Read `sli.robot` if present. Its tasks become **monitor sub-checks**,
   not tools. Merge its `RW.Core.Import User Variable` /
   `RW.Core.Import Secret` entries into the bundle-wide `## Inputs` /
   `## Secrets` tables.
3. Read each `<script>.sh` mentioned via `bash_file=` to confirm what
   JSON artifacts it writes (they appear later as `cat <file>.json`
   inside the runbook).
4. Pull `Display Name`, `Documentation`, and `Supports` from the
   Robot `*** Settings ***` block to populate frontmatter and the
   top-level heading.
5. Fill the template top-down. Keep terminology consistent: Robot
   tasks in `runbook.robot` become **Tools**; Robot tasks in
   `sli.robot` become **Monitor sub-checks**.
6. Validate against the checklist below.

---

## Worked Example (azure-aks-triage)

This bundle has no `sli.robot`, so the manifest omits both
`runtime.monitor` and the `## Monitor` body section. For a bundle that
also ships a monitor (e.g. `k8s-deployment-healthcheck`), set
`runtime.monitor: sli.robot` and add a `## Monitor` block listing one
`#### Sub-check` per metric-pushing task in `sli.robot`.

```markdown
---
name: azure-aks-triage
description: Triages an Azure AKS cluster across resource health, configuration, network, activities, version support, and cost optimization. Use when investigating AKS cluster health issues, validating configuration, or assessing node-pool cost savings.
runtime:
  runbook: runbook.robot
  runner: ro
platforms: [Azure, AKS, Kubernetes]
resource_types: [aks_cluster]
access: read-only
---

# Azure AKS Triage

## Summary

Runs diagnostic checks against an AKS cluster: Azure-reported resource
health, cluster + network configuration, recent activities, Kubernetes
version support, and 30-day node-pool cost-optimization analysis.

## Tools

### Check for Resource Health Issues Affecting AKS Cluster `${AKS_CLUSTER}` In Resource Group `${AZ_RESOURCE_GROUP}`

Fetch a list of issues that might affect the AKS cluster.

- **Robot task name**: `Check for Resource Health Issues Affecting AKS Cluster \`${AKS_CLUSTER}\` In Resource Group \`${AZ_RESOURCE_GROUP}\``
- **Robot file**: `runbook.robot`
- **Underlying script**: `aks_resource_health.sh`
- **Tags**: `aks`, `config`, `access:read-only`, `data:config`
- **Reads**: `AZ_RESOURCE_GROUP`, `AKS_CLUSTER`, `AZURE_RESOURCE_SUBSCRIPTION_ID`, `azure_credentials`
- **Writes**: `az_resource_health.json`
- **Issues raised**: Resource-health timeouts, auth failures, Azure-reported availability issues

### Check Configuration Health of AKS Cluster `${AKS_CLUSTER}` In Resource Group `${AZ_RESOURCE_GROUP}`

Fetch the config of the AKS cluster in azure.

- **Robot task name**: `Check Configuration Health of AKS Cluster \`${AKS_CLUSTER}\` In Resource Group \`${AZ_RESOURCE_GROUP}\``
- **Robot file**: `runbook.robot`
- **Underlying script**: `aks_cluster_health.sh`
- **Tags**: `AKS`, `config`, `access:read-only`, `data:config`
- **Reads**: `AZ_RESOURCE_GROUP`, `AKS_CLUSTER`, `AZURE_RESOURCE_SUBSCRIPTION_ID`, `azure_credentials`
- **Writes**: `az_cluster_health.json`
- **Issues raised**: Configuration timeouts, auth failures, per-issue entries from `az_cluster_health.json`

<!-- ... one entry per remaining task ... -->

## Inputs

| Name | Type | Description | Default | Required |
|---|---|---|---|---|
| `AZ_RESOURCE_GROUP` | string | The resource group to perform actions against. | — | yes |
| `AKS_CLUSTER` | string | The Azure AKS cluster to triage. | — | yes |
| `RW_LOOKBACK_WINDOW` | string | Time window, in minutes, to look back for activities/events. | `60` | no |
| `TIMEOUT_SECONDS` | string | Timeout in seconds for tasks. | `900` | no |
| `AZURE_RESOURCE_SUBSCRIPTION_ID` | string | The Azure Subscription ID for the resource. | `""` | no |

## Secrets

| Name | Description | Required |
|---|---|---|
| `azure_credentials` | Secret containing `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_SUBSCRIPTION_ID`. | yes |

## Outputs

- `az_resource_health.json` -- Azure ResourceHealth API response
- `az_cluster_health.json` -- Cluster-config issues
- `aks_activities_issues.json` -- Activity-log issues
- `aks_version_support.json` -- Version-support issues
- `aks_cost_optimization_issues.json` -- Cost-optimization issues

## How to invoke

### Preferred: Robot Framework runner (`ro`)

```bash
cd codebundles/azure-aks-triage
export AZ_RESOURCE_GROUP=my-rg
export AKS_CLUSTER=my-cluster
export AZURE_RESOURCE_SUBSCRIPTION_ID=...
ro runbook.robot
```

### Standalone scripts (no Robot)

```bash
export AZ_RESOURCE_GROUP=my-rg
export AKS_CLUSTER=my-cluster
bash aks_resource_health.sh        # az_resource_health.json
bash aks_cluster_health.sh         # az_cluster_health.json
bash aks_network.sh
bash aks_activities.sh             # aks_activities_issues.json
bash aks_version_support.sh        # aks_version_support.json
bash aks_cost_optimization.sh      # aks_cost_optimization_issues.json
```

## Source files

- `runbook.robot` -- orchestrates all tools and emits issues
- `aks_resource_health.sh` -- queries `Microsoft.ResourceHealth`
- `aks_cluster_health.sh` -- inspects cluster config + RBAC + network basics
- `aks_network.sh` -- network configuration recommendations
- `aks_activities.sh` -- activity-log warnings/errors
- `aks_version_support.sh` -- Kubernetes-version support window check
- `aks_cost_optimization.sh` -- 30-day utilization + savings estimates
```

---

## Validation Checklist

Before opening a PR with a new `SKILL.md`:

- [ ] File is at `codebundles/<bundle-name>/SKILL.md`
- [ ] Frontmatter `name` matches the directory name exactly
- [ ] `description` is third-person and contains a "Use when …" phrase
- [ ] `runtime.runbook` and (if present) `runtime.monitor` paths resolve
- [ ] `platforms` mirrors the Robot `Metadata    Supports    ...` line
- [ ] Every `*** Tasks ***` entry in `runbook.robot` has a corresponding `### Tool`
- [ ] Each tool lists its underlying `bash_file` (or notes "pure Robot")
- [ ] If `sli.robot` exists, `## Monitor` is present with one `####`
      sub-check per metric-pushing task
- [ ] `## Inputs` covers every `RW.Core.Import User Variable` (from
      both robots, deduplicated)
- [ ] `## Secrets` covers every `RW.Core.Import Secret`
- [ ] `## Outputs` lists every JSON artifact referenced by `cat *.json`
      and (when applicable) the monitor metric name
- [ ] `## How to invoke` shows both the `ro` and standalone-script paths
- [ ] No Robot files were renamed or moved

---

## Common Mistakes

1. **Renaming Robot files.** `SKILL.md` is additive. Never rename
   `runbook.robot`, `sli.robot`, or any `*.sh` script -- the platform
   runtime still loads them by their original names.

2. **Paraphrasing `[Documentation]`.** Copy verbatim. Agents use the
   prose to decide whether to invoke a tool; rewording loses the
   author's intent.

3. **Dropping `${VAR}` placeholders from tool titles.** The Robot task
   name is the primary key for tool lookup. Strip the placeholders and
   the agent can no longer cross-reference back to the runbook.

4. **Mixing tool inputs with bundle inputs.** `## Inputs` documents
   bundle-wide variables imported once in `Suite Initialization`. Per-
   tool inputs (the variables a tool actually reads) belong in the
   tool's `Reads:` line.

5. **Treating SLI tasks as tools.** Tasks in `sli.robot` are **monitor
   sub-checks**, not tools. They live under `## Monitor`, are keyed by
   their `sub_name=` metric, and never appear in the `## Tools`
   section. Mixing the two collapses the registry's tool/monitor
   distinction.

6. **Inventing trigger phrases.** Generation rules and `Supports`
   metadata already define when the bundle applies. Use them as the
   source of truth for the `Use when …` phrase rather than guessing.

7. **Bypassing secrets.** Standalone-script invocations still need
   the same auth as the Robot path. The `## How to invoke` section must
   make the env-var contract explicit (e.g. `AZURE_*` for Azure bundles)
   so an agent doesn't run the script unauthenticated.
