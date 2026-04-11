# Test Infrastructure -- Cloud Platforms (Shared Patterns)

This is a routing document. For detailed, platform-specific test
infrastructure guidance, read the appropriate skill doc:

| Platform | Skill Document |
|---|---|
| **Azure** (Key Vault, VMs, Storage, etc.) | `docs/skills/test-infra-azure.md` |
| **Azure DevOps** (Projects, Pipelines, Repos) | `docs/skills/test-infra-azure-devops.md` |
| **AWS** | `docs/skills/test-infra-aws.md` *(planned)* |
| **GCP** | `docs/skills/test-infra-gcp.md` *(planned)* |

---

## Shared Conventions (All Cloud Platforms)

These conventions apply to **every** cloud platform test directory.

### Credential Management

- **`tf.secret`** -- Shell-sourceable file with provider credentials.
  Never committed to git. Must be `source`d before every Terraform and
  `az`/`aws`/`gcloud` command in the Taskfile.
- Sensitive Terraform variables are injected via `TF_VAR_*` exports in
  `tf.secret`, not stored in `terraform.tfvars`.

### `.gitignore` (within `.test/`)

```
tf.secret
*.secret
terraform.tfstate*
.terraform/
output/
workspaceInfo.yaml
kubeconfig
```

### Standard Terraform Files

| File | Purpose |
|---|---|
| `main.tf` | Cloud resources to provision |
| `provider.tf` / `providers.tf` | Provider configuration |
| `backend.tf` | Backend config (always `local {}` for tests) |
| `vars.tf` / `variables.tf` | Input variable declarations |
| `terraform.tfvars` | Non-sensitive concrete values |
| `tf.secret` | Credential exports (gitignored) |

### Standard Taskfile Tasks

Every cloud `.test/Taskfile.yaml` must implement:

| Task | Purpose |
|---|---|
| `default` | `check-unpushed-commits` → `generate-rwl-config` → `run-rwl-discovery` |
| `clean` | Terraform destroy → `delete-slxs` → `clean-rwl-discovery` |
| `build-infra` | `source tf.secret` + `terraform init` + `terraform apply` |
| `check-unpushed-commits` | Verify code is committed and pushed |
| `generate-rwl-config` | Write `workspaceInfo.yaml` with cloud-specific config |
| `run-rwl-discovery` | Start RunWhen Local container and run discovery |
| `validate-generation-rules` | Validate `.runwhen/generation-rules/*.yaml` |

### Test Resource Tagging

Always tag cloud resources for identification and cleanup:

```hcl
tags = {
  "env"       : "test",
  "lifecycle" : "deleteme",
  "product"   : "runwhen"
}
```

### Creating Test Scenarios

Provision resources in **both healthy and unhealthy** states so the
CodeBundle's health checks have realistic conditions to detect:

- Healthy: A properly configured resource passing all checks
- Unhealthy: A resource with a known deficiency (expiring cert, missing
  encryption, failed pipeline, etc.)

---

## Common Mistakes (All Platforms)

1. **Missing `source terraform/tf.secret`** -- Must be called before
   every Terraform or cloud CLI command in the Taskfile.

2. **Committing `tf.secret`** -- This file contains real credentials.
   Ensure `.gitignore` covers it.

3. **Not scoping `codeBundles`** -- Always limit to the current bundle:
   `codeBundles: ["$codebundle"]`.

4. **Forgetting `check-unpushed-commits`** -- RunWhen Local pulls from
   the remote branch. Uncommitted/unpushed code is invisible to discovery.

5. **Using remote Terraform backend** -- Test infrastructure uses local
   state (`backend "local" {}`). Never use remote state for ephemeral
   test resources.
