# SLI Authoring Guide

This guide covers how to build Service Level Indicators (SLIs) for
CodeBundles. An SLI is a lightweight, periodic health check that produces
a 0-to-1 score. The score drives alerting: when it drops below a
threshold the associated runbook is triggered automatically.

---

## When to Build an SLI

**Always include an SLI** for health/monitoring CodeBundles.  Use this
decision tree:

| Bundle type | Examples | SLI approach |
|-------------|----------|--------------|
| Health / monitoring | `*-healthcheck`, `*-health`, `*-monitor` | **In-repo `sli.robot`** with a dedicated SLI template |
| Operational / triage | `*-ops`, `*-triage`, `*-restart`, `*-remediate` | **Cron-scheduler SLI** that periodically triggers the runbook |
| Chaos / one-off | `*-chaos-*`, manual remediation | Typically no SLI (runbook is on-demand only) |

**Rule of thumb:** if the bundle answers the question "is this resource
healthy right now?", it needs an in-repo SLI. If it answers "perform
this action", use the cron-scheduler pattern so the platform can still
run it periodically.

---

## SLI Design Principles

1. **Lightweight** -- must complete in under 30 seconds
2. **Frequent** -- runs every 30-600 seconds (`intervalSeconds` in the
   template, typically 180 for namespace-level, 300-600 for
   resource-level)
3. **Read-only** -- never modify resources; use `access:read-only` tags
4. **Idempotent** -- safe to run continuously without side effects
5. **Binary dimensions** -- each check produces 0 (failing) or 1 (passing),
   aggregated as an arithmetic mean for the final score
6. **Configurable thresholds** -- use `RW.Core.Import User Variable`
   with sensible defaults so each deployment can tune sensitivity
7. **Safe error handling** -- wrap JSON parsing in `TRY/EXCEPT`; default
   to a reasonable value (typically 0 for strict, 1 for optional checks)

---

## Model 1: In-Repo `sli.robot`

This is the standard pattern for health-check bundles. The `sli.robot`
file lives alongside `runbook.robot` in the CodeBundle directory.

### Structure

```robot
*** Settings ***
Metadata          Author    rw-codebundle-agent
Documentation     Measures the health of <resource> by scoring <dimensions>.
                  ...Produces a value between 0 (completely failing) and 1 (fully passing).
Metadata          Display Name    <Display Name>
Metadata          Supports    Kubernetes,AKS,EKS,GKE,OpenShift
Suite Setup       Suite Initialization
Library           BuiltIn
Library           RW.Core
Library           RW.CLI
Library           RW.platform
Library           OperatingSystem
Library           Collections

*** Keywords ***
Suite Initialization
    ${kubeconfig}=    RW.Core.Import Secret    kubeconfig
    ...    type=string
    ...    description=The kubernetes kubeconfig yaml containing connection configuration.
    ...    pattern=\w*
    ${NAMESPACE}=    RW.Core.Import User Variable    NAMESPACE
    ...    type=string
    ...    description=The Kubernetes namespace to check.
    ...    pattern=\w*
    ${CONTEXT}=    RW.Core.Import User Variable    CONTEXT
    ...    type=string
    ...    description=Which Kubernetes context to operate within.
    ...    pattern=\w*
    ${SOME_THRESHOLD}=    RW.Core.Import User Variable    SOME_THRESHOLD
    ...    type=string
    ...    description=Maximum acceptable count before the check fails.
    ...    pattern=^\d+$
    ...    default=5
    ${KUBERNETES_DISTRIBUTION_BINARY}=    RW.Core.Import User Variable    KUBERNETES_DISTRIBUTION_BINARY
    ...    type=string
    ...    enum=[kubectl,oc]
    ...    default=kubectl
    Set Suite Variable    ${kubeconfig}    ${kubeconfig}
    Set Suite Variable    ${NAMESPACE}    ${NAMESPACE}
    Set Suite Variable    ${CONTEXT}    ${CONTEXT}
    Set Suite Variable    ${SOME_THRESHOLD}    ${SOME_THRESHOLD}
    Set Suite Variable    ${KUBERNETES_DISTRIBUTION_BINARY}    ${KUBERNETES_DISTRIBUTION_BINARY}
    Set Suite Variable    ${env}    {"KUBECONFIG":"./${kubeconfig.key}"}

*** Tasks ***
Check Dimension A and Score
    [Documentation]    Checks <dimension A> and produces a binary 0/1 score.
    [Tags]    access:read-only    data:config
    ${result}=    RW.CLI.Run Cli
    ...    cmd=${KUBERNETES_DISTRIBUTION_BINARY} get <resource> --context ${CONTEXT} -n ${NAMESPACE} -o json
    ...    env=${env}
    ...    secret_file__kubeconfig=${kubeconfig}
    # Parse and count issues
    ${count}=    <parse logic producing an integer>
    ${threshold}=    Convert To Integer    ${SOME_THRESHOLD}
    ${score_a}=    Evaluate    1 if ${count} <= ${threshold} else 0
    Set Suite Variable    ${score_a}
    RW.Core.Push Metric    ${score_a}    sub_name=dimension_a

Check Dimension B and Score
    [Documentation]    Checks <dimension B>.
    [Tags]    access:read-only    data:config
    # ... similar pattern ...
    ${score_b}=    Evaluate    1 if <condition> else 0
    Set Suite Variable    ${score_b}
    RW.Core.Push Metric    ${score_b}    sub_name=dimension_b

Generate Aggregate Health Score
    [Documentation]    Averages sub-scores into the final 0-1 metric.
    ${health_score}=    Evaluate    (${score_a} + ${score_b}) / 2
    ${health_score}=    Convert to Number    ${health_score}    2
    RW.Core.Add to Report    Health Score: ${health_score}
    RW.Core.Push Metric    ${health_score}
```

### Key Patterns

- **`RW.Core.Push Metric ${score} sub_name=<dimension>`** -- push each
  sub-metric for dashboard drill-down
- **Final `RW.Core.Push Metric ${aggregate}`** -- the primary metric
  without `sub_name` is what the platform uses for alerting
- **`RW.Core.Add to Report`** -- one-liner summary visible in the UI
- **`RW.CLI.Run Cli` + `Parse Cli Json Output`** -- standard data
  collection from kubectl/az/gcloud/aws
- **`Evaluate 1 if <pass_condition> else 0`** -- binary scoring per dimension
- **Mean aggregation** -- `(${a} + ${b} + ... + ${n}) / N`

### Real Example: k8s-namespace-healthcheck

Three dimensions: warning events, container restarts, pods not ready.
Each scored binary 0/1, averaged to produce the final health score.

```
namespace_health = (event_score + restart_score + pod_readiness_score) / 3
```

---

## Model 2: Cron-Scheduler SLI

For operational bundles that don't have a natural health metric but
should still run periodically. The SLI template points to
`rw-workspace-utils/cron-scheduler-sli/sli.robot` which triggers the
associated runbook on a schedule.

**No `sli.robot` file is needed in your CodeBundle.** Only the SLI
template is required.

### When to Use

- The runbook itself IS the health check (e.g., it creates issues when
  problems are found)
- There's no clean 0-1 metric to derive from the resource
- You want periodic execution without building separate SLI logic

### SLI Template for Cron-Scheduler

```yaml
apiVersion: runwhen.com/v1
kind: ServiceLevelIndicator
metadata:
  name: {{slx_name}}
  labels:
    {% include "common-labels.yaml" %}
  annotations:
    {% include "common-annotations.yaml" %}
spec:
  displayUnitsLong: Health Score
  displayUnitsShort: score
  locations:
    - {{default_location}}
  description: Periodically triggers <bundle-name> runbook for <resource>.
  codeBundle:
    repoUrl: https://github.com/runwhen-contrib/rw-workspace-utils.git
    ref: main
    pathToRobot: codebundles/cron-scheduler-sli/sli.robot
  intervalStrategy: intermezzo
  intervalSeconds: 300
  configProvided:
    - name: CRON_SCHEDULE
      value: "*/30 * * * *"
    - name: TARGET_SLX
      value: ""
    - name: DRY_RUN
      value: "false"
  secretsProvided: []
```

---

## Generation Rule Integration

The generation rules file **MUST** include `- type: sli` in
`outputItems` to have the SLI deployed alongside the SLX and runbook.

### outputItems

```yaml
outputItems:
  - type: slx
  - type: sli                                    # <-- required
  - type: runbook
    templateName: <bundle-name>-taskset.yaml
```

### SLI Template File

Place the template at `.runwhen/templates/<bundle-name>-sli.yaml`.

**Naming convention:** `<bundle-name>-sli.yaml` (matches the
`baseTemplateName` from the generation rules).

### In-Repo SLI Template Structure

```yaml
apiVersion: runwhen.com/v1
kind: ServiceLevelIndicator
metadata:
  name: {{slx_name}}
  labels:
    {% include "common-labels.yaml" %}
  annotations:
    {% include "common-annotations.yaml" %}
spec:
  displayUnitsLong: OK
  displayUnitsShort: ok
  locations:
    - {{default_location}}
  description: <What this SLI measures>.
  codeBundle:
    {% if repo_url %}
    repoUrl: {{repo_url}}
    {% else %}
    repoUrl: https://github.com/runwhen-contrib/rw-cli-codecollection.git
    {% endif %}
    {% if ref %}
    ref: {{ref}}
    {% else %}
    ref: main
    {% endif %}
    pathToRobot: codebundles/<bundle-name>/sli.robot
  intervalStrategy: intermezzo
  intervalSeconds: 180
  configProvided:
    - name: NAMESPACE
      value: {{match_resource.resource.metadata.namespace}}
    - name: CONTEXT
      value: {{context}}
    - name: KUBERNETES_DISTRIBUTION_BINARY
      value: {{custom.kubernetes_distribution_binary | default("kubectl")}}
    # ... additional config matching sli.robot variables ...
  secretsProvided:
  {% if wb_version %}
    {% include "kubernetes-auth.yaml" ignore missing %}
  {% else %}
    - name: kubeconfig
      workspaceKey: {{custom.kubeconfig_secret_name}}
  {% endif %}
  alertConfig:
    tasks:
      persona: eager-edgar
      sessionTTL: 10m
```

### Key Template Fields

| Field | Purpose |
|-------|---------|
| `pathToRobot` | Points to this bundle's `sli.robot` (in-repo) or `cron-scheduler-sli/sli.robot` (scheduler) |
| `intervalSeconds` | How often to run (30-600; 180 is common) |
| `intervalStrategy` | Always `intermezzo` |
| `configProvided` | Must match every `RW.Core.Import User Variable` in `sli.robot` |
| `secretsProvided` | Must match every `RW.Core.Import Secret` in `sli.robot` |
| `alertConfig.tasks.persona` | Usually `eager-edgar` (triggers runbook on failure) |

---

## Checklist for SLI Implementation

Use this checklist when building or reviewing a CodeBundle:

- [ ] Does the bundle have a clear health metric? If yes, build an in-repo `sli.robot`
- [ ] If no clear metric but periodic execution is useful, use the cron-scheduler pattern
- [ ] `sli.robot` produces a 0-1 score via `RW.Core.Push Metric`
- [ ] Each dimension is pushed with `sub_name=<dimension_name>`
- [ ] Final aggregate is pushed without `sub_name` (primary metric)
- [ ] `RW.Core.Add to Report` includes a human-readable summary
- [ ] Thresholds come from `RW.Core.Import User Variable` with defaults
- [ ] Generation rules include `- type: sli` in `outputItems`
- [ ] `.runwhen/templates/<bundle-name>-sli.yaml` template exists
- [ ] Template `configProvided` matches all `sli.robot` variables
- [ ] Template `secretsProvided` matches all `sli.robot` secrets
- [ ] SLI completes in under 30 seconds

---

## Common Mistakes

1. **Missing `- type: sli` in generation rules** -- the SLI template
   exists but is never deployed because `outputItems` doesn't list it
2. **`configProvided` mismatch** -- template provides `NAMESPACE` but
   `sli.robot` imports `TARGET_NAMESPACE`; names must match exactly
3. **SLI too heavy** -- running full triage logic in the SLI; keep it
   to simple counts/thresholds, leave deep analysis to the runbook
4. **No aggregate metric** -- pushing only sub-metrics without a final
   `Push Metric` (no `sub_name`); the platform needs the primary metric
5. **Hardcoded thresholds** -- use `Import User Variable` with defaults
   so deployments can tune sensitivity
6. **Missing error handling** -- a parse failure crashes the SLI instead
   of producing a degraded score; always wrap JSON parsing in `TRY/EXCEPT`
