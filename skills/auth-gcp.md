---
description: How to handle GCP authentication when authoring CodeBundles (secrets, gcloud/bq auth, service accounts, ADC)
globs: "**/codebundles/gcp-*/**,**/codebundles/gke-*/**,**/.runwhen/**"
alwaysApply: false
---

# GCP Authentication -- CodeBundle Authoring

This guide covers how GCP credentials flow through the RunWhen runtime
(`rw-base-runtime`) and the patterns CodeBundles must follow so that
`gcloud`, `bq`, and `gsutil` work in **both** production and local dev
(`ro`) modes.

---

## Secret Reference Format

At runtime, the platform injects `RW_SECRETS_KEYS` -- a JSON map of
secret names to provider references:

```json
{"gcp_credentials": "gcp:adc@cli"}
```

The reference format is `<provider>:<type>@<source>`:

| Provider | Meaning | Companion secrets required |
|---|---|---|
| `gcp:adc` | Application Default Credentials (ambient identity: GCE/GKE metadata server, Workload Identity, or an existing `GOOGLE_APPLICATION_CREDENTIALS`) | none (optional `gcp_projectId`) |
| `gcp:sa` | Service Account key | `gcp_projectId`, `gcp_serviceAccountKey` |

| Source | Effect at import time |
|---|---|
| `cli` | Calls `gcp_utils.gcloud_login()` -- runs `gcloud auth activate-service-account` (SA) or verifies ADC, then `gcloud config set project`. gcloud/bq are authenticated for the rest of the suite. |
| `kubeconfig:<cluster>/<zone>` | Generates a GKE kubeconfig via `get-credentials` and writes it to `$KUBECONFIG` (1-hour filesystem cache). |

---

## Key Insight: Import-Time Auth

When a CodeBundle runs:

```robot
${gcp_credentials}=    RW.Core.Import Secret    gcp_credentials
```

and the configured value is `gcp:adc@cli` or `gcp:sa@cli`, the
**import itself performs the gcloud login**. By the time Suite
Initialization completes, `gcloud`/`bq` are already authenticated --
no further auth commands are needed in production.

In **dev mode** (`ro`, `RW_FROM_FILE`), no login happens at import.
Auth then resolves through a fallback chain:

1. **Key file from the secret** -- `RW_FROM_FILE` (or an env var)
   provides a raw JSON key; `secret_file__` materializes it and
   `gcloud auth activate-service-account --key-file=...` logs in.
2. **`GOOGLE_APPLICATION_CREDENTIALS` already set** -- if the developer
   exported a path to a key or ADC file, `gcloud`/`bq` use it directly.
3. **Local gcloud session / ADC** -- a developer who previously ran
   `gcloud auth login` or `gcloud auth application-default login` is
   already authenticated; `gcloud`/`bq` pick up those ambient
   credentials with no CodeBundle action at all.

The `|| true` on the activation command is what makes this chain work:
if there is no key file (cases 2-3), the command fails harmlessly and
execution falls through to the ambient credentials. Note that `ro`
redirects `CLOUDSDK_CONFIG` to an isolated temp dir, so a local gcloud
*session* in `~/.config/gcloud` is only visible when the developer's
environment propagates it (e.g. via `GOOGLE_APPLICATION_CREDENTIALS`
pointing at `~/.config/gcloud/application_default_credentials.json`) --
but ADC via that file path works regardless of `CLOUDSDK_CONFIG`.

**Therefore every GCP CodeBundle must include the defensive auth
pattern below** so it works in all of these modes.

---

## Required Suite Initialization Pattern

```robot
Suite Initialization
    ${gcp_credentials}=    RW.Core.Import Secret    gcp_credentials
    ...    type=string
    ...    description=GCP service account json used to authenticate with GCP APIs.
    ...    pattern=\w*
    ...    example={"type": "service_account","project_id":"myproject-ID"}
    ${GCP_PROJECT_ID}=    RW.Core.Import User Variable    GCP_PROJECT_ID
    ...    type=string
    ...    description=The GCP Project ID to scope the API to.
    ...    pattern=\w*
    ...    example=myproject-id
    ${OS_PATH}=    Get Environment Variable    PATH
    Set Suite Variable    ${GCP_PROJECT_ID}    ${GCP_PROJECT_ID}
    Set Suite Variable    ${gcp_credentials}    ${gcp_credentials}
    Set Suite Variable
    ...    ${env}
    ...    {"CLOUDSDK_CORE_PROJECT":"${GCP_PROJECT_ID}","GOOGLE_APPLICATION_CREDENTIALS":"./${gcp_credentials.key}","PATH":"$PATH:${OS_PATH}","GCP_PROJECT_ID":"${GCP_PROJECT_ID}"}
    RW.CLI.Run CLI
    ...    cmd=gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS" || true
    ...    env=${env}
    ...    secret_file__gcp_credentials=${gcp_credentials}
```

Why each piece matters:

- **`secret_file__gcp_credentials=${gcp_credentials}`** -- the
  `secret_file__` prefix tells `RW.CLI` to materialize the secret value
  as a file named `${gcp_credentials.key}` in the task's working
  directory.
- **`"GOOGLE_APPLICATION_CREDENTIALS":"./${gcp_credentials.key}"`** --
  points gcloud/bq at that materialized file.
- **`gcloud auth activate-service-account ... || true`** -- in dev mode
  with a key file this performs the real login; without one it fails
  harmlessly and gcloud/bq fall back to ambient local auth
  (`GOOGLE_APPLICATION_CREDENTIALS`, local ADC). In production with
  `gcp:adc@cli` / `gcp:sa@cli`, import-time auth already happened and
  the secret value is a status string (not a key file), so the command
  fails harmlessly there too. **Never omit `|| true`.**
- **`CLOUDSDK_CORE_PROJECT`** -- sets the default project for all
  gcloud/bq commands so scripts don't need `--project` everywhere.

Apply this pattern to **both** `runbook.robot` and `sli.robot`.

---

## Runtime Environment (what the platform sets for you)

`runrobot.py` prepares these before Robot starts. Do **not** override
them:

| Variable | Value | Purpose |
|---|---|---|
| `CLOUDSDK_CONFIG` | `$TMPDIR/shared_config/<cred-hash>/.gcloud` | gcloud credential cache, shared across executions but isolated per credential set |
| `AZURE_CONFIG_DIR` | `$TMPDIR/shared_config/<cred-hash>/.azure` | same for Azure |
| `AWS_CONFIG_DIR` | `$TMPDIR/shared_config/<cred-hash>/.aws` | same for AWS |
| `KUBECONFIG` | execution-specific `.kube/config` | written by `gcp:*@kubeconfig:...` imports |
| `CODEBUNDLE_TEMP_DIR` | execution-specific `cb-temp/` | scratch space |

The `<cred-hash>` is derived from the workspace, vault config, and the
secret provider references in use -- two different service accounts
never share a gcloud config dir. Overriding `CLOUDSDK_CONFIG` in a
CodeBundle breaks credential caching and cross-execution isolation.

The base image ships `gcloud` (+ `gke-gcloud-auth-plugin`), `bq`, and
`gsutil`. You do not need to install them.

---

## Scripts That Need Bearer Tokens (curl / REST)

The platform's intent is that **Import Secret handles all auth**.
Scripts should use `gcloud` / `bq` / `gsutil` directly -- no JWT
signing, no key-file parsing, no custom token exchange. Only fetch a
token when hitting a REST endpoint with no gcloud equivalent (e.g.
PromQL on `monitoring.googleapis.com`), and fetch it from the session
the import established:

```bash
fetch_access_token() {
    local token
    token=$(gcloud auth application-default print-access-token 2>/dev/null) || true
    if [ -z "${token:-}" ]; then
        token=$(gcloud auth print-access-token 2>/dev/null) || true
    fi
    if [ -z "${token:-}" ]; then
        echo "Failed to retrieve a GCP access token from the authenticated gcloud session." >&2
        return 1
    fi
    echo "$token"
}
```

That is the entire token story. If this fails, the answer is to fix
the CodeBundle's Suite Initialization -- not to add key handling.

**Do not put `GOOGLE_APPLICATION_CREDENTIALS` in the task env.** With
`gcp:adc@cli` the secret value is a status string, not a key; pointing
the env var at the materialized file poisons the ambient ADC the
import established (gcloud's ADC lookup reads it, chokes, and every
subsequent call 401s). The Suite Init activate command references the
materialized path directly instead:

```robot
Set Suite Variable
...    ${env}
...    {"PATH":"$PATH:${OS_PATH}","GCP_PROJECT_ID":"${GCP_PROJECT_ID}"}
RW.CLI.Run CLI
...    cmd=gcloud auth activate-service-account --key-file="./${gcp_credentials.key}" || true
...    env=${env}
...    secret_file__gcp_credentials=${gcp_credentials}
```

After activation, the session lives in `CLOUDSDK_CONFIG` -- nothing
else needs the file.

---

## Shell Script Conventions

Scripts receive auth through the environment -- they should **not**
re-authenticate:

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${GCP_PROJECT_ID:?Must set GCP_PROJECT_ID}"

# gcloud/bq are already authenticated by Suite Initialization.
# Just use them:
datasets=$(bq --project_id "$GCP_PROJECT_ID" ls --format=json 2>/dev/null || echo "[]")
```

Rules:

1. **Never call `gcloud auth` inside task scripts.** Auth happens once
   in Suite Initialization.
2. **Always start with `set -euo pipefail`** and validate required env
   vars with `: "${VAR:?Must set VAR}"`.
3. **Prefer `bq ls` / `bq show` over `INFORMATION_SCHEMA` queries.**
   INFORMATION_SCHEMA requires additional dataset-level permissions
   (`bigquery.tables.list`, `bigquery.routines.list`) that read-only
   service accounts often lack; `bq ls`/`bq show` work with basic
   viewer roles.
4. **Degrade gracefully**: `2>/dev/null || echo "[]"` on discovery
   commands so a permission gap produces an empty result, not a crash.
5. **Check all BigQuery access field variants** -- `bq show` returns
   public principals under `specialGroup`, `iamMember`, or
   `groupByEmail` depending on how they were granted:

   ```bash
   jq '[.[] | select(
     .specialGroup == "allUsers" or
     .iamMember == "allUsers" or
     .groupByEmail == "allUsers"
   )]'
   ```

6. **Emit JSON with `printf`, not `echo` with escaped backticks** --
   `\\\`` in a double-quoted string produces `\`` which is invalid
   JSON.
7. **Avoid `echo "$data" | while read` loops** -- the pipe runs the
   loop in a subshell and all variable assignments are lost. Use
   process substitution: `while read ... done < <(...)`.

---

## GKE Kubeconfig Variant

For CodeBundles that shell out to `kubectl` against GKE, import a
kubeconfig secret instead of (or in addition to) the CLI secret:

```json
{
  "gcp_credentials": "gcp:adc@cli",
  "kubeconfig": "gcp:adc@kubeconfig:my-cluster/us-central1"
}
```

The import writes the kubeconfig to `$KUBECONFIG` (already set by the
runtime) and `gcloud container clusters get-credentials` is handled by
the platform. Reference: `gke-cluster-health`.

---

## Generation Rules / Templates

In `.runwhen/templates/*-taskset.yaml`, always use the auth include
rather than hardcoding secret references:

```yaml
  secretsProvided:
  {% if wb_version %}
    {% include "gcp-auth.yaml" ignore missing %}
  {% else %}
    - name: gcp_credentials
      workspaceKey: {{custom.gcp_credentials_secret | default("gcp_credentials_json")}}
  {% endif %}
```

---

## Common Mistakes

1. **Rolling your own auth in scripts** -- JWT signing, key-file
   parsing, custom token exchange. This is the platform's job: Import
   Secret authenticates the session, scripts use `gcloud`/`bq`/`gsutil`.
   Found in `gcp-bucket-health` before fixes.

2. **Putting `GOOGLE_APPLICATION_CREDENTIALS` in the task env** -- with
   `gcp:adc@cli` the materialized secret file holds a status string,
   not a key; the env var then poisons the ambient ADC the import
   established and every API call 401s. Keep it out of `${env}`; the
   Suite Init activate command uses `./${gcp_credentials.key}` directly.

3. **Missing `gcloud auth activate-service-account` in Suite Init** --
   works in production (import-time auth) but fails in dev mode where
   the secret is a raw key. Found in `gcp-bucket-health`,
   `gcp-bigquery-dataset-health` before fixes.

4. **Omitting `|| true`** -- in production the secret value may be a
   status string (`"GCP CLI authenticated for project ..."`), not a
   JSON key. Without `|| true` the suite dies in Suite Setup.

5. **Chaining `gcloud auth ... &&` into every task command** --
   redundant re-authentication on every task. Authenticate once in
   Suite Initialization; tasks inherit the `CLOUDSDK_CONFIG` cache.

6. **Overriding `CLOUDSDK_CONFIG`** -- destroys the shared credential
   cache and per-credential isolation the runtime manages.

7. **Using INFORMATION_SCHEMA for BigQuery discovery** -- fails with
   `Access Denied` for viewer-level service accounts. Use `bq ls` /
   `bq show`.

8. **Only checking `.iamMember` for public access** -- misses
   `allAuthenticatedUsers` grants, which `bq show` reports under
   `specialGroup`.

9. **Hardcoding credentials or project IDs** -- always import via
   `RW.Core.Import Secret` / `RW.Core.Import User Variable` and use the
   `gcp-auth.yaml` include in templates.

---

## Reference Implementation

`codebundles/gke-cluster-health` is the canonical example:

- Suite Init: import secret, build env, `gcloud auth
  activate-service-account ... || true`
- Scripts: plain `gcloud` calls, no auth logic
- Templates: `{% include "gcp-auth.yaml" ignore missing %}`
