---
description: How to author generation rules and templates for GCP CodeBundles
globs: "**/.runwhen/**,**/codebundles/**"
alwaysApply: false
---

# Generation Rules -- GCP Platform

This guide covers how to author `.runwhen/generation-rules/` and
`.runwhen/templates/` for GCP CodeBundles in `rw-cli-codecollection`.

---

## Platform Identifier

GCP resources must explicitly set `platform: gcp`:

```yaml
apiVersion: runwhen.com/v1
kind: GenerationRules
spec:
  platform: gcp
  generationRules:
    - resourceTypes:
        - compute_instance
```

---

## Resource Types

GCP resource type names correspond to **CloudQuery table names** as
registered by the indexer. The exact available types depend on which
CloudQuery GCP provider tables are configured. Common examples:

| resourceType | GCP Service |
|---|---|
| `project` | GCP Projects |
| `compute_instance` | Compute Engine VMs |
| `storage_bucket` | Cloud Storage Buckets |
| `sql_instance` | Cloud SQL Instances |
| `gke_cluster` | GKE Clusters |
| `cloud_function` | Cloud Functions |
| `pubsub_topic` | Pub/Sub Topics |
| `pubsub_subscription` | Pub/Sub Subscriptions |

The `project` resource type is special -- it has its own handling for
LOD configuration via `projectLevelOfDetails` in the platform config.

---

## Match Rule Properties (GCP)

The GCP enricher does **not** define built-in property names beyond
`name`. Any property name is resolved as a JSON path into the raw
CloudQuery resource data:

| Property | Matches Against |
|---|---|
| `name` | Resource name |
| *(any other)* | JSON path into raw resource data |

GCP does **not** support `tags`, `tag-keys`, or `tag-values` as
built-in property names (unlike AWS and Azure). To match on labels,
use JSON paths:

```yaml
matchRules:
  - type: pattern
    pattern: "production"
    properties: [labels/environment]
```

---

## Qualifier Hierarchy

GCP has a simple qualifier set:

| Qualifier | Value Source |
|---|---|
| `resource` | Resource name |
| `project` | GCP project ID |

Common qualifier patterns:

```yaml
# One SLX per resource per project
qualifiers: ["resource", "project"]

# One SLX per project
qualifiers: ["project"]
```

---

## Level of Detail

GCP LOD is derived from the parent `project` resource's LOD
configuration. Projects can have their LOD set via the
`projectLevelOfDetails` map in the platform's cloud config:

```yaml
cloudConfig:
  gcp:
    projects: ["my-project-id"]
    projectLevelOfDetails:
      my-project-id: detailed
```

If a resource has no associated project, `get_level_of_detail` returns
`None` (the engine may skip generating output items).

---

## Standard Template Variables (GCP)

| Variable | Type | Description |
|---|---|---|
| `project` | Object | GCP project resource (has `.name` = project ID) |

Plus all standard variables (`workspace`, `default_location`,
`repo_url`, `ref`, `slx_name`, `match_resource`, `custom`, `secrets`).

Note that `project.name` is the **project ID** (e.g., `my-project-123`),
not the display name.

---

## Template Anatomy

### SLX Template

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
  imageURL: https://storage.googleapis.com/runwhen-nonprod-shared-images/icons/gcp/{resource}.svg
  alias: "{{match_resource.resource.name}} GCP Health"
  configProvided:
    - name: GCP_PROJECT_ID
      value: "{{project.name}}"
  owners:
    - {{workspace.owner_email}}
```

### Taskset Template

```yaml
apiVersion: runwhen.com/v1
kind: Runbook
metadata:
  name: {{slx_name}}
  labels:
    {% include "common-labels.yaml" %}
  annotations:
    {% include "common-annotations.yaml" %}
spec:
  location: {{default_location}}
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
    pathToRobot: codebundles/{codebundle-dir-name}/runbook.robot
  configProvided:
    - name: GCP_PROJECT_ID
      value: "{{project.name}}"
  secretsProvided:
  {% if wb_version %}
    {% include "gcp-auth.yaml" ignore missing %}
  {% else %}
    - name: gcp_credentials_json
      workspaceKey: {{custom.gcp_credentials_secret | default("gcp_credentials_json")}}
  {% endif %}
```

### Auth Include

Always use `{% include "gcp-auth.yaml" ignore missing %}` for GCP
secrets.

### Icon Paths

GCP icons are at:
`https://storage.googleapis.com/runwhen-nonprod-shared-images/icons/gcp/`

---

## Common Mistakes

1. **Omitting `platform: gcp`** -- Without this, resources default to
   Kubernetes and won't match.

2. **Using `tags` as a property name** -- Unlike AWS/Azure, GCP does
   not have built-in `tags`/`tag-keys`/`tag-values` handling. Use JSON
   paths to match on labels or other fields.

3. **Confusing `project.name` with display name** -- In GCP templates,
   `project.name` is the **project ID**, not the human-readable display
   name.

4. **Using Kubernetes qualifiers** -- `namespace`, `cluster` are
   Kubernetes-only. GCP only supports `project` and `resource` as
   qualifiers.

5. **Hardcoding GCP credentials** -- Always use the `gcp-auth.yaml`
   include.
