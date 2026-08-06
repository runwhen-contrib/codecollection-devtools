---
description: How to handle Azure authentication when authoring CodeBundles (secrets, az cli auth, service principals, managed identity)
globs: "**/codebundles/azure-*/**,**/.runwhen/**"
alwaysApply: false
---

# Azure Authentication -- CodeBundle Authoring

This guide covers how Azure credentials flow through the RunWhen
runtime (`rw-base-runtime`) and the patterns CodeBundles must follow
so that the `az` CLI works in **both** production and local dev (`ro`)
modes.

---

## Secret Reference Format

At runtime, the platform injects `RW_SECRETS_KEYS` -- a JSON map of
secret names to provider references:

```json
{"azure_credentials": "azure:sp@cli"}
```

The reference format is `<provider>:<type>@<source>`:

| Provider | Meaning | Companion secrets required |
|---|---|---|
| `azure:sp` | Service Principal (client credentials) | `az_clientId`, `az_tenantId`, `az_clientSecret` |
| `azure:identity` | Managed Identity (system- or user-assigned, from the environment) | none |

| Source | Effect at import time |
|---|---|
| `cli` | Calls `azure_utils.az_login()` -- runs `az login --service-principal` (SP) or `az login --identity` (managed identity) against the shared `AZURE_CONFIG_DIR`. The `az` CLI is authenticated for the rest of the suite. |
| `kubeconfig:<resource_group>/<cluster_name>` | Generates an AKS kubeconfig via `az aks get-credentials` and writes it to `$KUBECONFIG` (1-hour filesystem cache). |

Note the companion-secret naming: Azure SP secrets use the
`az_clientId` / `az_tenantId` / `az_clientSecret` camelCase keys in the
secrets config (not `AZURE_CLIENT_ID` env-style names).

---

## Key Insight: Import-Time Auth

When a CodeBundle runs:

```robot
${azure_credentials}=    RW.Core.Import Secret    azure_credentials
```

and the configured value is an `azure:*@cli` reference, the **import
itself performs the `az login`**. By the time Suite Initialization
completes, `az` is already authenticated -- no further auth commands
are needed in production.

In **dev mode** (`ro`, `RW_FROM_FILE`), no login happens at import.
Auth then resolves through a fallback chain:

1. **Env vars** -- `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` /
   `AZURE_TENANT_ID` exported by the developer (consumed by Azure SDKs;
   the `az` CLI ignores these unless a script calls `az login` with
   them).
2. **Local `az` session** -- a developer who previously ran
   `az login` has cached tokens. Note `ro` redirects
   `AZURE_CONFIG_DIR` to an isolated temp dir, so the developer's
   `~/.azure` session is only visible when their environment
   propagates it.

Azure client secrets **expire** -- the most common production failure
is an expired `az_clientSecret`. CodeBundles should detect this and
raise a clear issue (see below).

---

## Required Suite Initialization Pattern

Azure CodeBundles should import credentials with error handling so an
expired/invalid secret produces a severity-1 issue instead of a bare
suite failure (reference: `azure-aks-triage`):

```robot
Suite Initialization
    ${azure_credentials_status}=    Run Keyword And Return Status
    ...    RW.Core.Import Secret    azure_credentials    type=string    description=The secret containing AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET, AZURE_SUBSCRIPTION_ID    pattern=\w*
    IF    ${azure_credentials_status}
        ${azure_credentials}=    RW.Core.Import Secret
        ...    azure_credentials
        ...    type=string
        ...    description=The secret containing AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET, AZURE_SUBSCRIPTION_ID
        ...    pattern=\w*
    END
    IF    not ${azure_credentials_status}
        RW.Core.Add Issue
        ...    severity=1
        ...    expected=Azure service principal credentials should be valid and not expired
        ...    actual=Azure service principal authentication failed during suite initialization
        ...    title=Azure Authentication Failed - Service Principal Credentials Expired or Invalid
        ...    details=Azure authentication failed during suite setup. The service principal client secret may be expired or invalid.
        ...    next_steps=Renew Azure service principal client secret in Azure portal: https://aka.ms/NewClientSecret\nUpdate workspace secrets with new client secret\nVerify AZURE_CLIENT_ID, AZURE_TENANT_ID, and AZURE_CLIENT_SECRET are correct
        ${azure_credentials}=    Set Variable    ${EMPTY}
    END
    ${AZ_RESOURCE_GROUP}=    RW.Core.Import User Variable    AZ_RESOURCE_GROUP
    ...    type=string
    ...    description=The resource group to perform actions against.
    ...    pattern=\w*
    ${OS_PATH}=    Get Environment Variable    PATH
    Set Suite Variable    ${AZ_RESOURCE_GROUP}    ${AZ_RESOURCE_GROUP}
    Set Suite Variable    ${azure_credentials}    ${azure_credentials}
    Set Suite Variable
    ...    &{env}
    ...    AZ_RESOURCE_GROUP=${AZ_RESOURCE_GROUP}
    ...    PATH=$PATH:${OS_PATH}
```

Why each piece matters:

- **Error-handled import** -- expired client secrets are the #1 Azure
  failure mode; a clear issue beats a raw `ImportError` suite failure.
- **Import triggers login** -- in production with `azure:*@cli`, the
  import performs `az login`. Skipping the import skips auth entirely.
- **No `az login` in tasks or scripts** -- auth happens at import; the
  `AZURE_CONFIG_DIR` cache carries it through the suite.
- **`AZURE_SUBSCRIPTION_ID`** -- import it (as a user variable or part
  of the credentials secret) when scripts need
  `az account set --subscription`.

Apply this pattern to **both** `runbook.robot` and `sli.robot`.

---

## Validating Auth in Tasks

Detect auth failures in script output and surface them (reference:
`azure-aks-triage`):

```robot
${auth_failed}=    Run Keyword And Return Status    Should Contain    ${resource_health.stdout}    Authentication failed
${token_expired}=    Run Keyword And Return Status    Should Contain    ${resource_health.stdout}    client secret keys
IF    ${auth_failed} or ${token_expired}
    RW.Core.Add Issue
    ...    severity=2
    ...    expected=Azure authentication should succeed
    ...    actual=Azure authentication failed
    ...    title=Azure Authentication Failed
    ...    next_steps=Check Azure service principal credentials are not expired\nRenew client secret: https://aka.ms/NewClientSecret\nTest with: az login --service-principal --username <client-id> --password <client-secret> --tenant <tenant-id>
    RETURN
END
```

Scripts should probe early and print a recognizable marker:

```bash
if ! az account show >/dev/null 2>&1; then
  echo "Authentication failed: az account show could not retrieve the current account"
  exit 1
fi
```

---

## Runtime Environment (what the platform sets for you)

`runrobot.py` prepares these before Robot starts. Do **not** override
them:

| Variable | Value | Purpose |
|---|---|---|
| `AZURE_CONFIG_DIR` | `$TMPDIR/shared_config/<cred-hash>/.azure` | az CLI token cache, shared across executions but isolated per credential set |
| `AZURE_CORE_COLLECT_TELEMETRY` | `false` (defaulted) | disables az telemetry |
| `KUBECONFIG` | execution-specific `.kube/config` | written by `azure:*@kubeconfig:...` imports |

The `<cred-hash>` is derived from the workspace, vault config, and the
secret provider references in use -- two different tenants or service
principals never share a config dir. Overriding `AZURE_CONFIG_DIR` in
a CodeBundle breaks token caching and cross-execution isolation.

The base image ships `az` and `kubelogin`. You do not need to install
them.

---

## Scripts That Need Bearer Tokens (REST)

The platform's intent is that **Import Secret handles all auth**.
Scripts should use the `az` CLI directly -- no client-secret handling,
no `az login`, no MSAL/token-endpoint code. Only fetch a token when
hitting a REST endpoint with no `az` equivalent (e.g. raw
`management.azure.com` or Resource Graph calls), and fetch it from the
session the import established:

```bash
fetch_access_token() {
    local token
    token=$(az account get-access-token --query accessToken -o tsv 2>/dev/null) || true
    if [ -z "${token:-}" ]; then
        echo "Failed to retrieve an Azure access token from the authenticated az session." >&2
        return 1
    fi
    echo "$token"
}
```

That is the entire token story. If this fails, the answer is to fix
the CodeBundle's Suite Initialization -- not to add credential
handling.

**Do not parse the materialized secret file.** With `azure:*@cli`
providers the secret value is a *status string*
(`"Azure CLI authenticated for tenant a1b2c3d4... at ..."`), not a
credential bundle. A script that reads `secret_file__azure_credentials`
expecting `AZURE_CLIENT_ID`/`AZURE_CLIENT_SECRET` gets garbage -- and
any script that then runs its own `az login` with those "credentials"
clobbers the shared token cache.

---

## Shell Script Conventions

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${AZ_RESOURCE_GROUP:?Must set AZ_RESOURCE_GROUP}"

# az CLI is already authenticated by the runtime/Suite Initialization.
az aks show --resource-group "$AZ_RESOURCE_GROUP" --name "$AKS_CLUSTER" -o json
```

Rules:

1. **Never run `az login` inside task scripts.** Auth happens at
   import time in Suite Initialization.
2. **Always start with `set -euo pipefail`** and validate required env
   vars.
3. **Probe auth early** with `az account show` and print a greppable
   failure marker.
4. **Degrade gracefully** on discovery commands (`2>/dev/null || echo "[]"`).
5. **Watch for secret expiry markers** in stderr: `AADSTS7000222`
   (expired client secret), `client secret keys`, `Authentication failed`.

---

## AKS Kubeconfig Variant

For CodeBundles that shell out to `kubectl` against AKS, import a
kubeconfig secret instead of (or in addition to) the CLI secret:

```json
{
  "azure_credentials": "azure:sp@cli",
  "kubeconfig": "azure:sp@kubeconfig:my-resource-group/my-cluster"
}
```

The import writes the kubeconfig to `$KUBECONFIG` (already set by the
runtime) via `az aks get-credentials`. Reference: `azure-aks-triage`.

---

## Generation Rules / Templates

In `.runwhen/templates/*-taskset.yaml`, always use the auth include:

```yaml
  secretsProvided:
  {% if wb_version %}
    {% include "azure-auth.yaml" ignore missing %}
  {% else %}
    - name: azure_credentials
      workspaceKey: {{custom.azure_credentials_secret | default("azure_credentials")}}
  {% endif %}
```

---

## Common Mistakes

1. **Rolling your own auth in scripts** -- client-secret handling,
   token-endpoint calls, MSAL code. This is the platform's job: Import
   Secret authenticates the session, scripts use `az`. For REST-only
   endpoints, `az account get-access-token` is the whole mechanism.

2. **Parsing the materialized secret file** -- with `azure:*@cli` the
   secret value is a status string, not a credential bundle. Scripts
   must never read `secret_file__azure_credentials` expecting
   `AZURE_CLIENT_ID`/`AZURE_CLIENT_SECRET`.

3. **Letting an expired secret crash the suite** -- use the
   error-handled import pattern and raise a severity-1 issue with
   renewal steps.

4. **Running `az login` in scripts** -- clobbers the shared token
   cache and can race with other executions using the same credential
   context.

5. **Wrong companion-secret names** -- the provider expects
   `az_clientId` / `az_tenantId` / `az_clientSecret` in the secrets
   config; `AZURE_CLIENT_ID`-style names are not read by the
   `azure:sp` provider.

6. **Forgetting `az account set --subscription`** -- multi-subscription
   tenants need the subscription selected; pass
   `AZURE_SUBSCRIPTION_ID` and set it early in scripts.

7. **Overriding `AZURE_CONFIG_DIR`** -- destroys token caching and
   per-credential isolation.

8. **Not surfacing auth failures** -- a silent 401 looks like "no
   resources found". Probe with `az account show` and grep for
   expiry markers.

---

## Reference Implementation

`codebundles/azure-aks-triage` is the canonical example:

- Suite Init: error-handled `azure_credentials` import, severity-1
  issue on failure, no login commands in tasks
- Scripts: plain `az` calls with early `az account show` probe
- Templates: `{% include "azure-auth.yaml" ignore missing %}`
