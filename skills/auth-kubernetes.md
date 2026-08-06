---
description: How to handle Kubernetes authentication when authoring CodeBundles (kubeconfig secrets, cloud-generated kubeconfigs, KUBECONFIG handling)
globs: "**/codebundles/k8s-*/**,**/codebundles/*-cluster-*/**"
alwaysApply: false
---

# Kubernetes Authentication -- CodeBundle Authoring

This guide covers how kubeconfigs flow through the RunWhen runtime
(`rw-base-runtime`) and the patterns CodeBundles must follow so that
`kubectl` (or `oc`) works in **both** production and local dev (`ro`)
modes.

For cloud-provider CLI auth (gcloud/az/aws), see the companion skills
`auth-gcp.md`, `auth-azure.md`, and `auth-aws.md`. This skill covers
only the kubeconfig side.

---

## Secret Reference Format

At runtime, the platform injects `RW_SECRETS_KEYS` -- a JSON map of
secret names to provider references. Kubernetes access comes from
either a **direct kubeconfig** or a **cloud-generated kubeconfig**:

```json
{"kubeconfig": "k8s:file@secret/my-cluster-kubeconfig/kubeconfig"}
```

### Direct kubeconfig providers

| Provider | Meaning |
|---|---|
| `k8s:file@<kind>/<name>/<data-key>[@namespace]` | Read the kubeconfig from a Secret/ConfigMap in the cluster the worker pod runs in |
| `k8s:env@<kind>/<name>/<data-key>[@namespace]` | Same, resolved via the pod's environment/service account |

### Cloud-generated kubeconfig providers

These authenticate to the cloud first, then generate a kubeconfig for
a managed cluster:

| Provider reference | Cluster type | Companion secrets |
|---|---|---|
| `gcp:adc@kubeconfig:<cluster>/<zone>` | GKE via ADC | none |
| `gcp:sa@kubeconfig:<cluster>/<zone>` | GKE via service account | `gcp_projectId`, `gcp_serviceAccountKey` |
| `azure:identity@kubeconfig:<resource_group>/<cluster>` | AKS via managed identity | none |
| `azure:sp@kubeconfig:<resource_group>/<cluster>` | AKS via service principal | `az_clientId`, `az_tenantId`, `az_clientSecret` |
| `aws:workload_identity@kubeconfig:<region>/<cluster>` | EKS via IRSA | none (optional `AWS_ROLE_ARN`) |
| `aws:cli@kubeconfig:<region>/<cluster>` | EKS via explicit keys | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |

**Effect at import time (all providers):** the kubeconfig content is
written to the path in `$KUBECONFIG` (set by the runtime before Robot
starts), and the Robot suite variable `${KUBECONFIG}` is set to that
path. Generated kubeconfigs are cached on the filesystem for 1 hour,
keyed by cluster and credential identity.

---

## Key Insight: Import-Time Kubeconfig Materialization

When a CodeBundle runs:

```robot
${kubeconfig}=    RW.Core.Import Secret    kubeconfig
```

the runtime **writes the kubeconfig to `$KUBECONFIG` during the
import**. `kubectl` needs no further setup in production.

Unlike cloud CLI secrets -- whose `@cli` values are *status strings*
-- kubeconfig secret values are always real kubeconfig YAML in both
production and dev mode, so materializing them with `secret_file__`
is safe and meaningful.

In **dev mode** (`ro`, `RW_FROM_FILE`), the secret is the kubeconfig
YAML as a string. No file is written at import, so the CodeBundle must
materialize it itself -- this is what `secret_file__kubeconfig` does
(see below).

---

## Required Suite Initialization Pattern

```robot
Suite Initialization
    ${kubeconfig}=    RW.Core.Import Secret    kubeconfig
    ...    type=string
    ...    description=The kubernetes kubeconfig yaml containing connection configuration used to connect to cluster(s).
    ...    pattern=\w*
    ...    example=For examples, start here https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/
    ${KUBERNETES_DISTRIBUTION_BINARY}=    RW.Core.Import User Variable    KUBERNETES_DISTRIBUTION_BINARY
    ...    type=string
    ...    description=Which binary to use for Kubernetes CLI commands.
    ...    enum=[kubectl,oc]
    ...    example=kubectl
    ...    default=kubectl
    ${CONTEXT}=    RW.Core.Import User Variable    CONTEXT
    ...    type=string
    ...    description=Which Kubernetes context to operate within.
    ...    pattern=\w*
    ...    example=my-main-cluster
    ${NAMESPACE}=    RW.Core.Import User Variable    NAMESPACE
    ...    type=string
    ...    description=The name of the namespace to search.
    ...    pattern=\w*
    ...    example=my-namespace
    ${OS_PATH}=    Get Environment Variable    PATH
    Set Suite Variable    ${kubeconfig}    ${kubeconfig}
    Set Suite Variable    ${KUBERNETES_DISTRIBUTION_BINARY}    ${KUBERNETES_DISTRIBUTION_BINARY}
    Set Suite Variable    ${CONTEXT}    ${CONTEXT}
    Set Suite Variable    ${NAMESPACE}    ${NAMESPACE}
    Set Suite Variable
    ...    ${env}
    ...    {"KUBECONFIG":"./${kubeconfig.key}","PATH":"$PATH:${OS_PATH}","KUBERNETES_DISTRIBUTION_BINARY":"${KUBERNETES_DISTRIBUTION_BINARY}","CONTEXT":"${CONTEXT}","NAMESPACE":"${NAMESPACE}"}
```

And every task that shells out must pass the secret so it is
materialized as a file:

```robot
${rsp}=    RW.CLI.Run Bash File
...    bash_file=my_check.sh
...    env=${env}
...    secret_file__kubeconfig=${kubeconfig}
```

Why each piece matters:

- **`secret_file__kubeconfig=${kubeconfig}`** -- tells `RW.CLI` to
  write the secret value to a file named `${kubeconfig.key}` in the
  task's working directory. In production the kubeconfig already
  exists at `$KUBECONFIG`; the materialized copy is a harmless
  duplicate. In dev mode this is what makes `kubectl` work at all.
- **`"KUBECONFIG":"./${kubeconfig.key}"`** -- points kubectl at the
  materialized file. This deliberately shadows the runtime-set
  `$KUBECONFIG` so the CodeBundle behaves identically in both modes.
- **`KUBERNETES_DISTRIBUTION_BINARY`** -- supports OpenShift (`oc`)
  without forking the CodeBundle; scripts use
  `${KUBERNETES_DISTRIBUTION_BINARY}` instead of bare `kubectl`.
- **`CONTEXT`** -- multi-context kubeconfigs need `--context`; import
  it and pass it through to scripts.

Apply this pattern to **both** `runbook.robot` and `sli.robot`.

---

## Runtime Environment (what the platform sets for you)

`runrobot.py` prepares these before Robot starts:

| Variable | Value | Purpose |
|---|---|---|
| `KUBECONFIG` | execution-specific `.kube/config` | target path for cloud-generated kubeconfigs; isolated per execution |

Unlike the cloud CLIs, kubectl has **no shared credential cache** --
each execution gets a fresh kubeconfig path, and generated kubeconfigs
are cached separately (1-hour TTL) under the cloud provider's config
dir (`CLOUDSDK_CONFIG` / `AZURE_CONFIG_DIR` / `AWS_CONFIG_DIR`), keyed
by cluster and credential identity.

The base image ships `kubectl`, `helm`, `istioctl`,
`gke-gcloud-auth-plugin` (GKE exec auth), and `kubelogin` (AKS
Entra-ID auth). You do not need to install them.

---

## Shell Script Conventions

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${KUBECONFIG:?Must set KUBECONFIG}"
: "${NAMESPACE:?Must set NAMESPACE}"
: "${KUBERNETES_DISTRIBUTION_BINARY:=kubectl}"

$KUBERNETES_DISTRIBUTION_BINARY get pods -n "$NAMESPACE" --context "${CONTEXT:-}" -o json
```

Rules:

1. **Never hardcode `kubectl`** -- use
   `${KUBERNETES_DISTRIBUTION_BINARY}` so OpenShift works.
2. **Never write to `~/.kube`** or run `kubectl config use-context`
   to mutate shared state; pass `--context` per command.
3. **Always start with `set -euo pipefail`** and validate
   `KUBECONFIG` is set.
4. **Probe connectivity early** (`kubectl version --request-timeout=10s`
   or `kubectl get ns --request-timeout=10s`) and print a greppable
   failure marker so tasks can raise an auth/connectivity issue
   instead of reporting "no resources found".
5. **Degrade gracefully** on discovery commands (`2>/dev/null || echo "[]"`).

---

## Cloud-Managed Clusters: Pair Both Secrets

For GKE/AKS/EKS CodeBundles that use `kubectl`, import **both** the
cloud CLI secret and the kubeconfig secret:

```json
{
  "gcp_credentials": "gcp:adc@cli",
  "kubeconfig": "gcp:adc@kubeconfig:my-cluster/us-central1"
}
```

The CLI secret authenticates `gcloud`/`az`/`aws` for control-plane
calls (describe cluster, list node pools); the kubeconfig secret
materializes data-plane access for `kubectl`. Reference:
`gke-cluster-health`, `azure-aks-triage`, `aws-eks-health`.

---

## Generation Rules / Templates

In `.runwhen/templates/*-taskset.yaml`, provide the kubeconfig secret
the same way as cloud credentials:

```yaml
  secretsProvided:
  {% if wb_version %}
    {% include "gcp-auth.yaml" ignore missing %}
  {% else %}
    - name: kubeconfig
      workspaceKey: {{custom.kubeconfig_secret | default("kubeconfig")}}
  {% endif %}
```

---

## Common Mistakes

1. **Missing `secret_file__kubeconfig` on tasks** -- works in
   production (runtime already wrote `$KUBECONFIG`) but fails in dev
   mode where nothing materializes the file.

2. **Overriding `KUBECONFIG` with a hardcoded path** -- breaks the
   execution-isolated path the runtime manages. Use
   `./${kubeconfig.key}` (dev-safe) or leave the runtime value
   untouched.

3. **Hardcoding `kubectl`** -- excludes OpenShift. Use
   `${KUBERNETES_DISTRIBUTION_BINARY}`.

4. **Using only a cloud CLI secret for kubectl** -- `gcp:adc@cli`
   authenticates `gcloud` but does not write a kubeconfig; kubectl
   calls fail with "no configuration provided". Pair with the
   `@kubeconfig:` variant.

5. **Treating connectivity failures as empty results** -- an
   unreachable API server looks like "zero pods". Probe early and
   raise an issue.

6. **Hardcoding contexts or namespaces** -- import them as user
   variables; the same CodeBundle runs against many clusters.

---

## Reference Implementation

`codebundles/k8s-certmanager-healthcheck` is the canonical example:

- Suite Init: import `kubeconfig` secret +
  `KUBERNETES_DISTRIBUTION_BINARY` / `CONTEXT` / `NAMESPACE` vars
- Tasks: `secret_file__kubeconfig=${kubeconfig}` on every CLI call
- Scripts: plain `$KUBERNETES_DISTRIBUTION_BINARY` calls
