# Test Infrastructure -- Azure Platform

This guide covers how to author `.test/` directories for Azure cloud
CodeBundles in `rw-cli-codecollection` and `azure-c7n-codecollection`.

Read this **after** reading `docs/creator/sre-mode-guide.md`.

---

## Directory Structure

Azure test infrastructure **always** uses Terraform to provision real
Azure resources, plus a `tf.secret` file for credential management:

```
.test/
├── Taskfile.yaml
├── terraform/
│   ├── main.tf             # Azure resources to test against
│   ├── provider.tf         # azurerm (and optionally azuread) providers
│   ├── backend.tf          # Terraform backend config
│   ├── vars.tf             # Input variable declarations
│   ├── terraform.tfvars    # Concrete values (resource names, tags, etc.)
│   └── tf.secret           # Credential env vars (gitignored)
└── README.md
```

**`tf.secret`** is a shell-sourceable file with Azure SP credentials.
It is **never committed** and must be created manually:

```bash
export ARM_SUBSCRIPTION_ID="..."
export AZ_TENANT_ID="..."
export AZ_CLIENT_ID="..."
export AZ_CLIENT_SECRET="..."
```

---

## Standard Task Names

| Task | Purpose |
|---|---|
| `default` | `check-unpushed-commits` → `generate-rwl-config` → `run-rwl-discovery` |
| `clean` | `check-and-cleanup-terraform` → `delete-slxs` → `clean-rwl-discovery` |
| `build-infra` | `build-terraform-infra` |
| `check-unpushed-commits` | Verify CodeBundle code is committed & pushed |
| `generate-rwl-config` | Write `workspaceInfo.yaml` with Azure cloud config |
| `run-rwl-discovery` | Start RunWhen Local container and run discovery |
| `validate-generation-rules` | Validate `.runwhen/generation-rules/*.yaml` against JSON schema |
| `build-terraform-infra` | `source tf.secret` + `terraform apply` |
| `cleanup-terraform-infra` | `source tf.secret` + `terraform destroy` |
| `check-terraform-infra` | Check if Terraform state has resources |
| `check-and-cleanup-terraform` | Conditional destroy if infra exists |
| `upload-slxs` | Upload generated SLXs to RunWhen Platform |
| `delete-slxs` | Delete SLXs from RunWhen Platform |

---

## Complete Taskfile

Based on real `azure-kv-health`:

```yaml
version: "3"

tasks:
  default:
    desc: "Run/refresh config"
    cmds:
      - task: check-unpushed-commits
      - task: generate-rwl-config
      - task: run-rwl-discovery

  clean:
    desc: "Run cleanup tasks"
    cmds:
      - task: check-and-cleanup-terraform
      - task: delete-slxs
      - task: clean-rwl-discovery

  build-infra:
    desc: "Build test infrastructure"
    cmds:
      - task: build-terraform-infra

  check-unpushed-commits:
    desc: Check if outstanding commits or file updates need to be pushed before testing.
    vars:
      BASE_DIR: "../"
    cmds:
      - |
        echo "Checking for uncommitted changes..."
        UNCOMMITTED_FILES=$(git diff --name-only HEAD | grep -E "^${BASE_DIR}(\.runwhen|[^/]+)" | grep -v "/\.test/" || true)
        if [ -n "$UNCOMMITTED_FILES" ]; then
          echo "✗ Uncommitted changes found:"
          echo "$UNCOMMITTED_FILES"
          exit 1
        else
          echo "√ No uncommitted changes."
        fi
      - |
        echo "Checking for unpushed commits..."
        git fetch origin
        UNPUSHED_FILES=$(git diff --name-only origin/$(git rev-parse --abbrev-ref HEAD) HEAD | grep -E "^${BASE_DIR}(\.runwhen|[^/]+)" | grep -v "/\.test/" || true)
        if [ -n "$UNPUSHED_FILES" ]; then
          echo "✗ Unpushed commits found:"
          echo "$UNPUSHED_FILES"
          exit 1
        else
          echo "√ No unpushed commits."
        fi
    silent: true

  generate-rwl-config:
    desc: "Generate RunWhen Local configuration (workspaceInfo.yaml)"
    env:
      ARM_SUBSCRIPTION_ID: "{{.ARM_SUBSCRIPTION_ID}}"
      AZ_TENANT_ID: "{{.AZ_TENANT_ID}}"
      AZ_CLIENT_SECRET: "{{.AZ_CLIENT_SECRET}}"
      AZ_CLIENT_ID: "{{.AZ_CLIENT_ID}}"
      RW_WORKSPACE: '{{.RW_WORKSPACE | default "my-workspace"}}'
    cmds:
      - |
        source terraform/tf.secret
        repo_url=$(git config --get remote.origin.url)
        branch_name=$(git rev-parse --abbrev-ref HEAD)
        codebundle=$(basename "$(dirname "$PWD")")
        AZURE_SUBSCRIPTION_ID=$ARM_SUBSCRIPTION_ID
        subscription_name=$(az account show --subscription ${AZURE_SUBSCRIPTION_ID} --query name -o tsv)

        pushd terraform > /dev/null
        resource_group=$(terraform show -json terraform.tfstate | jq -r '
          .values.root_module.resources[] |
          select(.type == "azurerm_resource_group") | .values.name')
        popd > /dev/null

        if [ -z "$resource_group" ]; then
          echo "Error: Missing resource_group details. Ensure Terraform plan has been applied."
          exit 1
        fi

        cat <<EOF > workspaceInfo.yaml
        workspaceName: "$RW_WORKSPACE"
        workspaceOwnerEmail: authors@runwhen.com
        defaultLocation: location-01-us-west1
        defaultLOD: detailed
        cloudConfig:
          azure:
            subscriptionId: "$ARM_SUBSCRIPTION_ID"
            tenantId: "$AZ_TENANT_ID"
            clientId: "$AZ_CLIENT_ID"
            clientSecret: "$AZ_CLIENT_SECRET"
            resourceGroupLevelOfDetails:
              $resource_group: detailed
        codeCollections:
        - repoURL: "$repo_url"
          branch: "$branch_name"
          codeBundles: ["$codebundle"]
        custom:
          subscription_name: $subscription_name
        EOF
    silent: true

  run-rwl-discovery:
    desc: "Run RunWhen Local Discovery on test infrastructure"
    cmds:
      - |
        source terraform/tf.secret
        CONTAINER_NAME="RunWhenLocal"
        if docker ps -q --filter "name=$CONTAINER_NAME" | grep -q .; then
          docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME
        elif docker ps -a -q --filter "name=$CONTAINER_NAME" | grep -q .; then
          docker rm $CONTAINER_NAME
        fi

        sudo rm -rf output || { echo "Failed to remove output directory"; exit 1; }
        mkdir output && chmod 777 output

        docker run --name $CONTAINER_NAME -p 8081:8081 \
          -v "$(pwd)":/shared \
          -d ghcr.io/runwhen-contrib/runwhen-local:latest

        docker exec -w /workspace-builder $CONTAINER_NAME ./run.sh $1 --verbose

        echo "Review generated config files under output/workspaces/"
    silent: true

  validate-generation-rules:
    desc: "Validate YAML files in .runwhen/generation-rules"
    cmds:
      - |
        for cmd in curl yq ajv; do
          if ! command -v $cmd &> /dev/null; then
            echo "Error: $cmd is required but not installed."
            exit 1
          fi
        done
        temp_dir=$(mktemp -d)
        curl -s -o "$temp_dir/generation-rule-schema.json" \
          https://raw.githubusercontent.com/runwhen-contrib/runwhen-local/refs/heads/main/src/generation-rule-schema.json
        for yaml_file in ../.runwhen/generation-rules/*.yaml; do
          echo "Validating $yaml_file"
          json_file="$temp_dir/$(basename "${yaml_file%.*}.json")"
          yq -o=json "$yaml_file" > "$json_file"
          ajv validate -s "$temp_dir/generation-rule-schema.json" -d "$json_file" \
            --spec=draft2020 --strict=false \
          && echo "$yaml_file is valid." || echo "$yaml_file is invalid."
        done
        rm -rf "$temp_dir"
    silent: true

  build-terraform-infra:
    desc: "Run terraform apply"
    cmds:
      - |
        source terraform/tf.secret
        export TF_VAR_sp_principal_id=$(az ad sp show --id $AZ_CLIENT_ID --query id -o tsv)
        export TF_VAR_subscription_id=$ARM_SUBSCRIPTION_ID
        export TF_VAR_tenant_id=$AZ_TENANT_ID
        if [ -d "terraform" ]; then
          cd terraform
        else
          echo "Terraform directory not found."
          exit 1
        fi
        terraform init
        echo "Starting Terraform Build..."
        terraform apply -auto-approve || {
          echo "Failed to build Terraform infrastructure."
          exit 1
        }
        echo "Terraform infrastructure build completed."
    silent: true

  cleanup-terraform-infra:
    desc: "Cleanup deployed Terraform infrastructure"
    cmds:
      - |
        source terraform/tf.secret
        export TF_VAR_sp_principal_id=$(az ad sp show --id $AZ_CLIENT_ID --query id -o tsv)
        export TF_VAR_subscription_id=$ARM_SUBSCRIPTION_ID
        export TF_VAR_tenant_id=$AZ_TENANT_ID
        if [ -d "terraform" ]; then
          cd terraform
        else
          echo "Terraform directory not found."
          exit 1
        fi
        echo "Starting cleanup of Terraform infrastructure..."
        terraform destroy -auto-approve || {
          echo "Failed to clean up Terraform infrastructure."
          exit 1
        }
        echo "Terraform infrastructure cleanup completed."
    silent: true

  check-terraform-infra:
    desc: "Check if Terraform has any deployed infrastructure"
    cmds:
      - |
        source terraform/tf.secret
        export TF_VAR_sp_principal_id=$(az ad sp show --id $AZ_CLIENT_ID --query id -o tsv)
        export TF_VAR_subscription_id=$ARM_SUBSCRIPTION_ID
        export TF_VAR_tenant_id=$AZ_TENANT_ID
        if [ ! -d "terraform" ]; then
          echo "Terraform directory not found."
          exit 1
        fi
        cd terraform
        if [ ! -f "terraform.tfstate" ]; then
          echo "No Terraform state file found. No infrastructure is deployed."
          exit 0
        fi
        resources=$(terraform state list)
        if [ -n "$resources" ]; then
          echo "Deployed infrastructure detected."
          echo "$resources"
        else
          echo "No deployed infrastructure found in Terraform state."
        fi
    silent: true

  check-and-cleanup-terraform:
    desc: "Check and clean up deployed Terraform infrastructure if it exists"
    cmds:
      - |
        infra_output=$(task check-terraform-infra | tee /dev/tty)
        if echo "$infra_output" | grep -q "Deployed infrastructure detected"; then
          echo "Infrastructure detected; proceeding with cleanup."
          task cleanup-terraform-infra
        else
          echo "No deployed infrastructure found; no cleanup required."
        fi
    silent: true

  clean-rwl-discovery:
    desc: "Check and clean up RunWhen Local discovery output"
    cmds:
      - |
        sudo rm -rf output
        rm -f workspaceInfo.yaml
    silent: true
```

Upload/delete SLXs and `check-rwp-config` tasks follow the same pattern
as the Kubernetes skill. See `test-infra-kubernetes.md` for those tasks.
The Azure version additionally uploads secrets to the RunWhen Platform:

```yaml
  upload-slxs:
    cmds:
      - task: check-rwp-config
      - |
        source terraform/tf.secret
        # Upload secrets first
        URL="https://${RW_API_URL}/api/v3/workspaces/${RW_WORKSPACE}/secrets"
        PAYLOAD="{\"secrets\": {\"az_subscriptionId\": \"${ARM_SUBSCRIPTION_ID}\", \"az_clientId\": \"${AZ_CLIENT_ID}\", \"az_tenantId\": \"${AZ_TENANT_ID}\", \"az_clientSecret\": \"${AZ_CLIENT_SECRET}\"}}"
        curl -X POST "$URL" \
          -H "Authorization: Bearer $RW_PAT" \
          -H "Content-Type: application/json" \
          -d "$PAYLOAD" -s
        # Then upload SLXs (same loop as Kubernetes)
        ...
```

---

## Terraform Files

### `provider.tf`

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.18.0"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "azuread" {}
```

Customize the `features` block for the Azure resource type being tested.

### `vars.tf`

```hcl
variable "resource_group" {
  type = string
}

variable "location" {
  type    = string
  default = "East US"
}

variable "tags" {
  type = map(string)
}

variable "sp_principal_id" {
  type = string
}
```

The `sp_principal_id` is injected via `TF_VAR_sp_principal_id` in the
Taskfile (from `az ad sp show --id $AZ_CLIENT_ID`).

### `terraform.tfvars`

```hcl
resource_group = "azure-vm-triage"
location       = "East US"
kv_name        = "test-yoko"
tags = {
  "env"       : "test",
  "lifecycle" : "deleteme",
  "product"   : "runwhen"
}
```

Always tag test resources with `lifecycle: deleteme` for easy cleanup.

### `main.tf` -- Example (Key Vault)

```hcl
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group
  location = var.location
  tags     = var.tags
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                       = var.kv_name
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  sku_name                   = "standard"
  enable_rbac_authorization  = false
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
  tags                       = var.tags
  access_policy {
    tenant_id               = data.azurerm_client_config.current.tenant_id
    object_id               = data.azurerm_client_config.current.object_id
    key_permissions         = ["Backup", "Create", "Decrypt", "Delete", "Encrypt", "Get", "Import", "List", "Purge", "Recover", "Restore", "Sign", "UnwrapKey", "Update", "Verify", "WrapKey", "GetRotationPolicy", "SetRotationPolicy"]
    secret_permissions      = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
    certificate_permissions = ["Get", "List", "Create", "Update", "Delete", "Recover", "Purge"]
  }
}

resource "azurerm_key_vault_secret" "expiring_secret" {
  name            = "${var.kv_name}-secret"
  value           = "ThisIsASecret"
  key_vault_id    = azurerm_key_vault.kv.id
  expiration_date = timeadd(timestamp(), "24h")
  tags            = var.tags
}

output "keyvault_name" {
  value = azurerm_key_vault.kv.name
}
```

Key patterns:
- **Resource group first** -- all Azure resources belong to an RG
- **`data "azurerm_client_config" "current"`** -- used for tenant ID and object ID
- **Test scenarios** -- create resources in both healthy and unhealthy states
  (e.g., an expiring secret with a 24h TTL that the health check should flag)
- **Outputs** -- expose resource names for validation

### `backend.tf`

```hcl
terraform {
  backend "local" {}
}
```

Most test infrastructure uses local state. Never use remote state for
ephemeral test resources.

---

## workspaceInfo.yaml -- Azure-Specific Fields

### `resourceGroupLevelOfDetails`

Scope discovery to only the test resource group:

```yaml
cloudConfig:
  azure:
    subscriptionId: "$ARM_SUBSCRIPTION_ID"
    tenantId: "$AZ_TENANT_ID"
    clientId: "$AZ_CLIENT_ID"
    clientSecret: "$AZ_CLIENT_SECRET"
    resourceGroupLevelOfDetails:
      my-test-rg: detailed
```

### `custom` section

```yaml
custom:
  subscription_name: my-subscription-name
```

The `subscription_name` is fetched at runtime via:
```bash
subscription_name=$(az account show --subscription ${AZURE_SUBSCRIPTION_ID} --query name -o tsv)
```

---

## Common Mistakes

1. **Missing `source terraform/tf.secret`** -- Every Terraform-related
   task must source credentials before running. Without this, `az` and
   `terraform` commands fail silently or with auth errors.

2. **Not setting `TF_VAR_sp_principal_id`** -- Many Azure Terraform
   configs require the service principal's object ID for RBAC. Source
   it from `az ad sp show --id $AZ_CLIENT_ID --query id -o tsv`.

3. **Committing `tf.secret`** -- Add `tf.secret`, `terraform.tfstate*`,
   `.terraform/`, and `output/` to `.gitignore`.

4. **Not using `resourceGroupLevelOfDetails`** -- Without this, discovery
   scans the entire subscription, which is slow and produces noise.

5. **Forgetting `purge_protection_enabled = false`** -- For test Key Vault
   resources, disable purge protection so `terraform destroy` actually
   cleans up.

6. **Missing tags** -- Always tag test resources with `lifecycle: deleteme`
   for easy manual cleanup if Terraform destroy fails.
