---
description: How to author generation rules and templates for Azure and Azure DevOps CodeBundles
globs: "**/.runwhen/**,**/codebundles/**"
alwaysApply: false
---

# Generation Rules -- Azure and Azure DevOps Platforms

This guide covers generation rules for two separate platforms:
**`azure`** (Azure cloud resources) and **`azure_devops`**
(Azure DevOps services). Each uses its own platform identifier and has
distinct resource types, qualifiers, and template variables.

---

## Part 1: Azure Cloud (`platform: azure`)

### Platform Identifier

```yaml
apiVersion: runwhen.com/v1
kind: GenerationRules
spec:
  platform: azure
  generationRules:
    - resourceTypes:
        - azure_compute_virtual_machines
```

### Resource Types

Azure resource types come from **CloudQuery table names**. The exact
available types depend on which CloudQuery Azure provider tables are
configured. Common examples:

| resourceType | Azure Service |
|---|---|
| `azure_compute_virtual_machines` | VMs |
| `azure_compute_disks` | Managed Disks |
| `azure_storage_accounts` | Storage Accounts |
| `azure_storage_containers` | Blob Containers |
| `azure_keyvault_vaults` | Key Vaults |
| `azure_keyvault_keys` | Key Vault Keys |
| `azure_keyvault_secrets` | Key Vault Secrets |
| `azure_network_virtual_networks` | Virtual Networks |
| `azure_network_subnets` | Subnets |
| `azure_network_security_groups` | NSGs |
| `azure_subscription_subscriptions` | Subscriptions |
| `azure_resources_resource_groups` | Resource Groups |
| `azure_ad_users` | Azure AD Users |
| `azure_ad_groups` | Azure AD Groups |

### Match Rule Properties (Azure)

| Property | Matches Against |
|---|---|
| `name` | Resource name |
| `tags` | All tag keys + values |
| `tag-keys` | Only tag keys |
| `tag-values` | Only tag values |

Any property name not in the built-in list is treated as a JSON path
into the raw CloudQuery resource data.

### Qualifiers (Azure)

| Qualifier | Value Source |
|---|---|
| `resource` | Resource name |
| `resource_group` | Azure Resource Group name |
| `subscription_id` | Azure Subscription ID |
| `subscription_name` | Azure Subscription display name |

Common qualifier patterns:

```yaml
# Per resource per resource group
qualifiers: ["resource", "resource_group"]

# Per resource group per subscription
qualifiers: ["resource_group", "subscription_id"]
```

### Standard Template Variables (Azure)

| Variable | Type | Description |
|---|---|---|
| `resource_group` | Object | Resource group (has `.name`) or minimal stub |
| `subscription_id` | String | Azure Subscription ID |
| `subscription_name` | String | Azure Subscription display name |

Plus all standard variables (`workspace`, `default_location`,
`repo_url`, `ref`, `slx_name`, `match_resource`, `custom`, `secrets`).

### Template Anatomy (Azure)

#### SLX Template

```yaml
apiVersion: runwhen.com/v1
kind: ServiceLevelX
metadata:
  name: {{slx_name}}
  labels:
    {% include "common-labels.yaml" %}
  annotations:
    {% include "common-annotations.yaml" %}
spec:
  imageURL: https://storage.googleapis.com/runwhen-nonprod-shared-images/icons/azure/{resource}.svg
  alias: "{{match_resource.resource.name}} Azure Health"
  configProvided:
    - name: AZ_RESOURCE_GROUP
      value: "{{resource_group.name}}"
    - name: AZ_SUBSCRIPTION_ID
      value: "{{subscription_id}}"
  owners:
    - {{workspace.owner_email}}
```

#### Auth Include

Use `{% include "azure-auth.yaml" ignore missing %}` for secrets:

```yaml
secretsProvided:
{% if wb_version %}
  {% include "azure-auth.yaml" ignore missing %}
{% else %}
  - name: AZURE_CREDENTIALS
    workspaceKey: {{custom.azure_credentials_secret | default("AZURE_CREDENTIALS")}}
{% endif %}
```

### Cloud Custodian (`azure-c7n-codecollection`)

For CodeBundles in `azure-c7n-codecollection`:

- `repoUrl` defaults to
  `https://github.com/runwhen-contrib/azure-c7n-codecollection.git`
- Always include `AZ_RESOURCE_GROUP` and `AZ_SUBSCRIPTION_ID` in
  `configProvided`
- Use `azure-auth.yaml` include for auth

---

## Part 2: Azure DevOps (`platform: azure_devops`)

### Platform Identifier

```yaml
apiVersion: runwhen.com/v1
kind: GenerationRules
spec:
  platform: azure_devops
  generationRules:
    - resourceTypes:
        - repository
```

### Resource Types

Azure DevOps resource types come from the Azure DevOps indexer:

| resourceType | Description |
|---|---|
| `repository` | Git repositories |
| `pipeline` | Build/release pipelines |
| `project` | Azure DevOps projects |

### Match Rule Properties (Azure DevOps)

| Property | Matches Against |
|---|---|
| `name` | Resource name |
| `id` | Resource ID |
| `url` | Resource URL |
| `revision` | Revision number |

### Qualifiers (Azure DevOps)

| Qualifier | Value Source |
|---|---|
| `resource` | Resource name |
| `project.name` | Azure DevOps project name |
| `organization` | Azure DevOps organization |

### Standard Template Variables (Azure DevOps)

| Variable | Type | Description |
|---|---|---|
| `project` | Object | Project resource (has `.name`) |
| `organization` | String | Organization name |

### Template Anatomy (Azure DevOps)

```yaml
apiVersion: runwhen.com/v1
kind: ServiceLevelX
metadata:
  name: {{slx_name}}
spec:
  configProvided:
    - name: AZURE_DEVOPS_PROJECT
      value: "{{project.name}}"
    - name: AZURE_DEVOPS_ORG
      value: "{{organization}}"
```

Auth include: `{% include "azure-devops-auth.yaml" ignore missing %}`

### Level of Detail (Azure DevOps)

Azure DevOps always operates at `DETAILED` level -- there is no LOD
filtering.

---

## Common Mistakes

1. **Mixing `azure` and `azure_devops`** -- These are completely
   separate platforms with different resource types, qualifiers, and
   auth mechanisms.

2. **Omitting `platform:` for Azure resources** -- Unlike Kubernetes,
   Azure resources require explicit `platform: azure`.

3. **Using Kubernetes qualifiers** -- `namespace`, `cluster` are
   Kubernetes-only. Use `resource_group`, `subscription_id` for Azure
   and `project.name`, `organization` for Azure DevOps.

4. **Hardcoding Azure credentials** -- Always use the
   `azure-auth.yaml` or `azure-devops-auth.yaml` includes.

5. **Assuming resource name fields** -- Azure resource naming varies by
   table. Some use `display_name`, others `name`. The enricher resolves
   names using a per-table mapping with fallbacks.
