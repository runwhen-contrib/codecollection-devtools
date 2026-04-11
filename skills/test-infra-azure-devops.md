---
description: How to author .test/ directories for Azure DevOps CodeBundles
globs: "**/.test/**,**/codebundles/**"
alwaysApply: false
---

# Test Infrastructure -- Azure DevOps Platform

This guide covers how to author `.test/` directories for Azure DevOps
CodeBundles. Azure DevOps CodeBundles use the `azure_devops` enricher in
RunWhen Local and test against real Azure DevOps organizations.

Read this **after** reading `docs/creator/sre-mode-guide.md`.

---

## Directory Structure

```
.test/
├── Taskfile.yaml
├── terraform/
│   ├── main.tf             # DevOps projects, repos, pipelines, agent pools
│   ├── providers.tf        # azurerm + azuredevops + time providers
│   ├── backend.tf          # Terraform backend config
│   ├── variables.tf        # Input variable declarations
│   ├── terraform.tfvars    # Org name, resource group, location, tags
│   └── tf.secret           # Credential env vars (gitignored)
└── README.md
```

### `tf.secret`

Azure DevOps requires both Azure RM credentials **and** DevOps-specific
credentials. The `tf.secret` file:

```bash
export ARM_SUBSCRIPTION_ID="..."
export AZURE_TENANT_ID="..."
export AZURE_CLIENT_ID="..."
export AZURE_CLIENT_SECRET="..."
export AZURE_DEVOPS_ORG="my-devops-org"

# Terraform provider vars (azuredevops provider uses these)
export TF_VAR_client_id="$AZURE_CLIENT_ID"
export TF_VAR_client_secret="$AZURE_CLIENT_SECRET"
export TF_VAR_tenant_id="$AZURE_TENANT_ID"
export TF_VAR_service_principal_id="$AZURE_CLIENT_ID"
export TF_VAR_azure_devops_org="$AZURE_DEVOPS_ORG"
```

The `azuredevops` provider authenticates via service principal, not PATs.

---

## Key Differences from Standard Azure

| Aspect | Standard Azure | Azure DevOps |
|---|---|---|
| **Provider** | `azurerm` only | `azurerm` + `azuredevops` |
| **cloudConfig key** | `azure` | `azure` with nested `devops` section |
| **Discovery scoping** | `resourceGroupLevelOfDetails` | `devops.organizationUrl` |
| **Test fixtures** | Cloud resources (VMs, Key Vaults) | Projects, repos, pipelines, agent pools |
| **Env vars in tf.secret** | `ARM_*` + `AZ_*` | `ARM_*` + `AZURE_*` + `AZURE_DEVOPS_ORG` |

---

## Standard Task Names

Same as standard Azure, plus:

| Task | Purpose |
|---|---|
| `test-all-scenarios` | (Optional) Run scenario-based tests |
| `test-agent-scenarios` | (Optional) Test agent pool scenarios |
| `test-security-scenarios` | (Optional) Test security/endpoint scenarios |

---

## workspaceInfo.yaml -- Azure DevOps Specific

The critical difference is the `devops` section under `cloudConfig.azure`:

```yaml
workspaceName: "$RW_WORKSPACE"
workspaceOwnerEmail: authors@runwhen.com
defaultLocation: location-01-us-west1
defaultLOD: detailed
cloudConfig:
  azure:
    subscriptionId: "$ARM_SUBSCRIPTION_ID"
    tenantId: "$AZURE_TENANT_ID"
    clientId: "$AZURE_CLIENT_ID"
    clientSecret: "$AZURE_CLIENT_SECRET"
    devops:
      organizationUrl: "https://dev.azure.com/$AZURE_DEVOPS_ORG"
codeCollections:
- repoURL: "$repo_url"
  branch: "$branch_name"
  codeBundles: ["$codebundle"]
```

The `devops.organizationUrl` tells the `azure_devops` enricher which
organization to scan. Without it, no Azure DevOps resources are discovered.

---

## Terraform Providers

### `providers.tf`

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = "~> 1.8.1"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9.1"
    }
  }
  required_version = ">= 1.0.0"
}

provider "azurerm" {
  features {}
}

provider "azuredevops" {
  org_service_url = var.azure_devops_org_url != null ? var.azure_devops_org_url : "https://dev.azure.com/${var.azure_devops_org}"
  client_id       = var.client_id
  tenant_id       = var.tenant_id
  client_secret   = var.client_secret
}
```

The `azuredevops` provider authenticates using a service principal -- the
same SP credentials used for Azure RM, but passed explicitly to the provider.

---

## Terraform Resources -- Test Fixture Patterns

Azure DevOps test infra creates a complete project with realistic resources:

### Project + Repository

```hcl
resource "azuredevops_project" "test_project" {
  name               = "DevOps-Triage-Test"
  visibility         = "private"
  version_control    = "Git"
  work_item_template = "Agile"
  description        = "Project for testing Azure DevOps triage scripts"
}

resource "azuredevops_git_repository" "test_repo" {
  project_id = azuredevops_project.test_project.id
  name       = "test-pipeline-repo"
  initialization {
    init_type = "Clean"
  }
}
```

### Variable Groups

```hcl
resource "azuredevops_variable_group" "test_vars" {
  project_id   = azuredevops_project.test_project.id
  name         = "Test Pipeline Variables"
  allow_access = true
  variable {
    name  = "RESOURCE_GROUP"
    value = azurerm_resource_group.rg.name
  }
}
```

### Agent Pools

```hcl
resource "azuredevops_agent_pool" "test_pool" {
  name           = "Test-Agent-Pool"
  auto_provision = false
  auto_update    = true
}

resource "azuredevops_agent_queue" "test_queue" {
  project_id    = azuredevops_project.test_project.id
  agent_pool_id = azuredevops_agent_pool.test_pool.id
}

resource "azuredevops_pipeline_authorization" "test_auth" {
  project_id  = azuredevops_project.test_project.id
  resource_id = azuredevops_agent_queue.test_queue.id
  type        = "queue"
}
```

### Service Endpoints

```hcl
resource "azuredevops_serviceendpoint_azurerm" "test_endpoint" {
  project_id                = azuredevops_project.test_project.id
  service_endpoint_name     = "Test-Azure-Connection"
  azurerm_spn_tenantid      = data.azurerm_client_config.current.tenant_id
  azurerm_subscription_id   = data.azurerm_client_config.current.subscription_id
  azurerm_subscription_name = "Test Subscription"
  credentials {
    serviceprincipalid  = var.client_id
    serviceprincipalkey = var.client_secret
  }
}
```

### Pipeline YAML + Build Definitions

Create pipeline YAML files via Terraform and upload to the repo:

```hcl
resource "local_file" "success_pipeline_yaml" {
  content  = <<-EOT
    trigger:
    - master
    pool:
      name: ${azuredevops_agent_pool.test_pool.name}
    steps:
    - script: |
        echo "Running successful pipeline"
      displayName: 'Run successful script'
  EOT
  filename = "${path.module}/success-pipeline.yml"
}

resource "azuredevops_git_repository_file" "success_pipeline_file" {
  repository_id       = azuredevops_git_repository.test_repo.id
  file                = "success-pipeline.yml"
  content             = local_file.success_pipeline_yaml.content
  branch              = "refs/heads/master"
  commit_message      = "Add success pipeline YAML"
  overwrite_on_create = true
  depends_on          = [azuredevops_git_repository.test_repo]
}

resource "azuredevops_build_definition" "success_pipeline" {
  project_id = azuredevops_project.test_project.id
  name       = "Success-Pipeline"
  path       = "\\Test"
  ci_trigger { use_yaml = true }
  repository {
    repo_type   = "TfsGit"
    repo_id     = azuredevops_git_repository.test_repo.id
    branch_name = "refs/heads/master"
    yml_path    = "success-pipeline.yml"
  }
  variable_groups = [azuredevops_variable_group.test_vars.id]
  depends_on = [
    azuredevops_git_repository_file.success_pipeline_file,
    azuredevops_pipeline_authorization.test_auth
  ]
}
```

### Test Scenario Pattern

Create multiple pipelines to test different health scenarios:

| Pipeline | Purpose |
|---|---|
| `Success-Pipeline` | Healthy baseline -- should pass all checks |
| `Failing-Pipeline` | Uses `exit 1` to create a failed build |
| `Long-Running-Pipeline` | Uses `sleep 300` to simulate slow builds |

This gives the health check CodeBundle realistic test conditions.

---

## Variables

### `variables.tf`

```hcl
variable "azure_devops_org" {
  description = "Azure DevOps organization name"
  type        = string
}

variable "azure_devops_org_url" {
  description = "Azure DevOps organization URL"
  type        = string
  default     = null
}

variable "client_id" {
  type      = string
  sensitive = true
}

variable "client_secret" {
  type      = string
  sensitive = true
}

variable "tenant_id" {
  type      = string
  sensitive = true
}

variable "service_principal_id" {
  type      = string
  sensitive = true
}

variable "resource_group" {
  type = string
}

variable "location" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

### `terraform.tfvars`

```hcl
resource_group = "azure-ado-triage"
location       = "Canada Central"
tags = {
  "env"       : "test",
  "lifecycle" : "deleteme",
  "product"   : "runwhen"
}
```

Note: `azure_devops_org`, `client_id`, `client_secret`, `tenant_id`, and
`service_principal_id` are injected via `TF_VAR_*` environment variables
from `tf.secret`, **not** stored in `terraform.tfvars`.

---

## Taskfile -- `generate-rwl-config` (Azure DevOps)

The key difference from standard Azure is the `AZURE_DEVOPS_ORG` env var
and the `devops.organizationUrl` in the generated config:

```yaml
  generate-rwl-config:
    desc: "Generate RunWhen Local config for Azure DevOps"
    env:
      ARM_SUBSCRIPTION_ID: "{{.ARM_SUBSCRIPTION_ID}}"
      AZURE_TENANT_ID: "{{.AZURE_TENANT_ID}}"
      AZURE_CLIENT_SECRET: "{{.AZURE_CLIENT_SECRET}}"
      AZURE_CLIENT_ID: "{{.AZURE_CLIENT_ID}}"
      AZURE_DEVOPS_ORG: "{{.AZURE_DEVOPS_ORG}}"
    cmds:
      - |
        source terraform/tf.secret
        repo_url=$(git config --get remote.origin.url)
        branch_name=$(git rev-parse --abbrev-ref HEAD)
        codebundle=$(basename "$(dirname "$PWD")")
        devops_org=$AZURE_DEVOPS_ORG
        cat <<EOF > workspaceInfo.yaml
        workspaceName: "${RW_WORKSPACE:-my-workspace}"
        workspaceOwnerEmail: authors@runwhen.com
        defaultLocation: location-01-us-west1
        defaultLOD: detailed
        cloudConfig:
          azure:
            subscriptionId: "$ARM_SUBSCRIPTION_ID"
            tenantId: "$AZURE_TENANT_ID"
            clientId: "$AZURE_CLIENT_ID"
            clientSecret: "$AZURE_CLIENT_SECRET"
            devops:
              organizationUrl: "https://dev.azure.com/$devops_org"
        codeCollections:
        - repoURL: "$repo_url"
          branch: "$branch_name"
          codeBundles: ["$codebundle"]
        EOF
    silent: true
```

---

## Common Mistakes

1. **Missing `azuredevops` provider** -- The `azuredevops` provider is
   separate from `azurerm`. Both are required. The DevOps provider needs
   explicit `client_id`, `tenant_id`, and `client_secret` fields.

2. **No `devops.organizationUrl` in workspaceInfo** -- Without this field,
   the `azure_devops` enricher has no organization to scan and will
   produce zero matches for generation rules.

3. **Using PAT instead of service principal** -- The Terraform provider
   and test infrastructure should use service principal authentication,
   not personal access tokens.

4. **Forgetting to create pipeline fixtures** -- Azure DevOps health
   checks need real pipelines (builds/runs) to inspect. Create at least
   one successful and one failing pipeline for realistic test coverage.

5. **Missing `depends_on` for pipeline files** -- Pipeline YAML files
   must be committed to the repo **before** creating the
   `azuredevops_build_definition` that references them.

6. **Not exporting `TF_VAR_*` in `tf.secret`** -- Sensitive variables
   like `client_id` and `client_secret` must be exported as `TF_VAR_*`
   so Terraform picks them up without storing them in `.tfvars`.
