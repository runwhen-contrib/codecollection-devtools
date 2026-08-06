---
description: How to handle AWS authentication when authoring CodeBundles (secrets, aws cli auth, IRSA, access keys, assume role)
globs: "**/codebundles/aws-*/**,**/.runwhen/**"
alwaysApply: false
---

# AWS Authentication -- CodeBundle Authoring

This guide covers how AWS credentials flow through the RunWhen runtime
(`rw-base-runtime`) and the patterns CodeBundles must follow so that
the `aws` CLI works in **both** production and local dev (`ro`) modes.

---

## Secret Reference Format

At runtime, the platform injects `RW_SECRETS_KEYS` -- a JSON map of
secret names to provider references:

```json
{"aws_credentials": "aws:access_key@cli"}
```

The reference format is `<provider>:<type>@<source>`:

| Provider | Meaning | Companion secrets required |
|---|---|---|
| `aws:irsa` | IAM Roles for Service Accounts -- pod web-identity token from the environment (`AWS_WEB_IDENTITY_TOKEN_FILE`) | none (optional `AWS_ROLE_ARN` for cross-account) |
| `aws:access_key` | Explicit long-lived keys | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (optional `AWS_SESSION_TOKEN`) |
| `aws:assume_role` | Assume a role, optionally with base credentials | `AWS_ROLE_ARN` (or `aws_role_arn`); optional `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` |
| `aws:default` | Default credential chain (env, shared config, instance profile) | none |
| `aws:workload_identity` | IRSA, used for **EKS kubeconfig** generation | none (optional `AWS_ROLE_ARN`) |
| `aws:cli` | Explicit credentials, used for **EKS kubeconfig** generation | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |

| Source | Effect at import time |
|---|---|
| `cli` | Calls the matching `aws_utils.aws_login_*()` -- writes credentials into the shared `AWS_CONFIG_DIR` and verifies identity. The `aws` CLI is authenticated for the rest of the suite. |
| `kubeconfig:<region>/<cluster_name>` | Generates an EKS kubeconfig via `aws eks update-kubeconfig` and writes it to `$KUBECONFIG` (1-hour filesystem cache). |

Notes:

- `aws:irsa@cli` automatically chains `aws_login_assume_role()` when
  `AWS_ROLE_ARN` is also present in the secrets config -- this is the
  cross-account access pattern.
- `aws:irsa` only supports `@cli`. For EKS kubeconfigs use
  `aws:workload_identity@kubeconfig:...`.

---

## Key Insight: Import-Time Auth

When a CodeBundle runs:

```robot
${aws_credentials}=    RW.Core.Import Secret    aws_credentials
```

and the configured value is an `aws:*@cli` reference, the **import
itself performs the AWS login**. By the time Suite Initialization
completes, `aws` is already authenticated -- no further auth commands
are needed in production.

In **dev mode** (`ro`, `RW_FROM_FILE`), no login happens at import.
Auth then resolves through the standard AWS fallback chain:

1. **Env vars** -- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` /
   `AWS_SESSION_TOKEN` exported by the developer.
2. **Shared config** -- the developer's `~/.aws/credentials` and
   `~/.aws/config` from a prior `aws configure` or SSO login.
3. **Instance/container identity** -- EC2 instance profile, ECS task
   role, or IRSA web-identity token when running inside AWS.

Unlike GCP, there is **no CodeBundle-side login command** to add --
AWS auth is entirely environment-driven. The CodeBundle's job is to
pass the environment through cleanly and validate auth early.

---

## Required Suite Initialization Pattern

```robot
Suite Initialization
    ${aws_credentials}=    RW.Core.Import Secret    aws_credentials
    ...    type=string
    ...    description=AWS credentials from the workspace (from aws-auth block; e.g. aws:access_key@cli, aws:irsa@cli).
    ...    pattern=\w*
    ${AWS_REGION}=    RW.Core.Import User Variable    AWS_REGION
    ...    type=string
    ...    description=AWS Region
    ...    pattern=\w*
    ...    example=us-east-1
    ${OS_PATH}=    Get Environment Variable    PATH
    Set Suite Variable    ${AWS_REGION}    ${AWS_REGION}
    Set Suite Variable    ${aws_credentials}    ${aws_credentials}
    Set Suite Variable
    ...    &{env}
    ...    AWS_REGION=${AWS_REGION}
    ...    AWS_DEFAULT_REGION=${AWS_REGION}
    ...    PATH=$PATH:${OS_PATH}
```

Why each piece matters:

- **Import `aws_credentials` even if scripts never read its value** --
  the import is what triggers `@cli` login in production. Skipping the
  import skips authentication entirely.
- **`AWS_DEFAULT_REGION`** -- many AWS CLI commands and SDKs read this
  instead of `AWS_REGION`; set both.
- **Dictionary-style env (`&{env}`)** -- the AWS codebundles use
  key=value pairs rather than a JSON string; either form works with
  `RW.CLI`.
- **No `aws configure` / `aws login` in the CodeBundle** -- credentials
  come from the runtime environment, never from interactive commands.

Apply this pattern to **both** `runbook.robot` and `sli.robot`.

---

## Validating Auth in Tasks

Because there is no login command to fail loudly, AWS CodeBundles
should detect auth failures in script output and surface them as
issues (reference: `aws-eks-health`):

```robot
${auth_failed}=    Run Keyword And Return Status    Should Contain    ${process.stdout}    get-caller-identity failed
IF    ${auth_failed}
    RW.Core.Add Issue
    ...    severity=2
    ...    expected=AWS authentication should succeed
    ...    actual=AWS authentication failed
    ...    title=AWS Authentication Failed
    ...    next_steps=Check AWS credentials with 'aws sts get-caller-identity'\nVerify the IAM role has required permissions
    RETURN
END
```

Scripts should probe early and print a recognizable marker:

```bash
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "AWS credentials not configured or get-caller-identity failed"
  exit 1
fi
```

---

## Runtime Environment (what the platform sets for you)

`runrobot.py` prepares these before Robot starts. Do **not** override
them:

| Variable | Value | Purpose |
|---|---|---|
| `AWS_CONFIG_DIR` | `$TMPDIR/shared_config/<cred-hash>/.aws` | AWS config cache, shared across executions but isolated per credential set |
| `AWS_CONFIG_FILE` | `$AWS_CONFIG_DIR/config` | |
| `AWS_SHARED_CREDENTIALS_FILE` | `$AWS_CONFIG_DIR/credentials` | written by `aws:*@cli` imports |
| `AWS_EC2_METADATA_DISABLED` | `true` (defaulted) | prevents metadata-server hangs outside AWS |
| `KUBECONFIG` | execution-specific `.kube/config` | written by `aws:*@kubeconfig:...` imports |

The `<cred-hash>` is derived from the workspace, vault config, and the
secret provider references in use -- two different roles or key pairs
never share a config dir. Overriding `AWS_CONFIG_DIR` or the
credentials-file paths in a CodeBundle breaks caching and isolation.

The base image ships the `aws` CLI v2. You do not need to install it.

---

## Scripts That Need Direct API Access

The platform's intent is that **Import Secret handles all auth**.
Scripts should use the `aws` CLI with `--output json` / `--query`
directly -- no SigV4 signing, no credential-file parsing, no
`~/.aws` manipulation. Every AWS API the CLI can't reach directly is
rare; when one comes up, use the CLI's own escape hatches
(`aws <service> ... --endpoint-url`, or `aws sts` for identity) rather
than hand-signing requests.

**Do not parse the materialized secret file.** With `aws:*@cli`
providers the secret value is a *status string*
(`"AWS CLI authenticated with access key a1b2c3d4..."`), not
credentials. A script that reads `secret_file__aws_credentials`
expecting keys gets garbage. Credentials live in the runtime-managed
`AWS_SHARED_CREDENTIALS_FILE`, written by the import.

---

## Shell Script Conventions

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?Must set AWS_REGION}"

# aws CLI is already authenticated by the runtime/Suite Initialization.
aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION"
```

Rules:

1. **Never run `aws configure`, `aws sso login`, or write to
   `~/.aws`** from a script.
2. **Always start with `set -euo pipefail`** and validate required env
   vars.
3. **Pass `--region` explicitly** or rely on `AWS_DEFAULT_REGION`;
   never hardcode regions.
4. **Degrade gracefully** on discovery commands (`2>/dev/null || echo "[]"`)
   so a permission gap yields an empty result, not a crash.
5. **Probe auth early** with `aws sts get-caller-identity` and print a
   greppable failure marker (see above).

---

## EKS Kubeconfig Variant

For CodeBundles that shell out to `kubectl` against EKS, import a
kubeconfig secret instead of (or in addition to) the CLI secret:

```json
{
  "aws_credentials": "aws:irsa@cli",
  "kubeconfig": "aws:workload_identity@kubeconfig:us-east-1/my-cluster"
}
```

The import writes the kubeconfig to `$KUBECONFIG` (already set by the
runtime). Reference: `aws-eks-health`.

---

## Generation Rules / Templates

In `.runwhen/templates/*-taskset.yaml`, always use the auth include:

```yaml
  secretsProvided:
  {% if wb_version %}
    {% include "aws-auth.yaml" ignore missing %}
  {% else %}
    - name: aws_credentials
      workspaceKey: {{custom.aws_credentials_secret | default("aws_credentials")}}
  {% endif %}
```

---

## Common Mistakes

1. **Rolling your own auth in scripts** -- SigV4 signing, parsing
   credential files, custom session-token handling. This is the
   platform's job: Import Secret authenticates the session, scripts
   use the `aws` CLI.

2. **Parsing the materialized secret file** -- with `aws:*@cli` the
   secret value is a status string, not keys. Scripts must never read
   `secret_file__aws_credentials` expecting credentials.

3. **Forgetting to import the secret** -- no import, no `@cli` login,
   every AWS call fails with `Unable to locate credentials`.

4. **Running `aws configure` in scripts** -- clobbers the
   runtime-managed credential files and breaks isolation between
   credential contexts.

5. **Hardcoding regions or account IDs** -- always import via
   `RW.Core.Import User Variable` and pass `--region`.

6. **Not surfacing auth failures** -- a silent `AccessDenied` looks
   like "no resources found". Probe with `get-caller-identity` and
   raise a severity-2 issue.

7. **Overriding `AWS_CONFIG_DIR` / `AWS_SHARED_CREDENTIALS_FILE`** --
   destroys the shared credential cache and per-credential isolation.

6. **Hardcoding credentials** -- always use the `aws-auth.yaml`
   include in templates; never inline keys in templates or scripts.

---

## Reference Implementation

`codebundles/aws-eks-health` is the canonical example:

- Suite Init: import `aws_credentials` + region vars, build env, no
  login commands
- Scripts: plain `aws` calls with early `get-caller-identity` probe
- Templates: `{% include "aws-auth.yaml" ignore missing %}`
