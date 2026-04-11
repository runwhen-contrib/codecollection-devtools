# Generation Rules -- Kubernetes Platform

This guide covers how to author `.runwhen/generation-rules/` and
`.runwhen/templates/` for Kubernetes CodeBundles. This is the default
platform in RunWhen Local -- if no `platform:` is specified, the
discovery engine assumes Kubernetes.

---

## Platform Identifier

Kubernetes is the **default**. You can omit `platform:` entirely, or
set it explicitly:

```yaml
apiVersion: runwhen.com/v1
kind: GenerationRules
spec:
  # platform: kubernetes  -- optional, this is the default
  generationRules:
    - resourceTypes:
        - deployment
```

---

## Built-in Resource Types

These are the native Kubernetes resource types recognized by the
discovery engine (from `KubernetesResourceType`):

| resourceType | Kubernetes Kind |
|---|---|
| `cluster` | Cluster (virtual) |
| `namespace` | Namespace |
| `deployment` | Deployment |
| `daemonset` | DaemonSet |
| `statefulset` | StatefulSet |
| `ingress` | Ingress |
| `service` | Service |
| `pod` | Pod |
| `persistentvolumeclaim` | PersistentVolumeClaim |
| `custom` | Any CRD (requires `group`, `version`, `kind`) |

### Custom Resource Types (CRDs)

For CRDs like Prometheus Operator resources, Cert-Manager, etc., use
the `custom` type with a dict specifying the CRD's API group:

```yaml
resourceTypes:
  - custom:
      group: monitoring.coreos.com
      version: v1
      kind: prometheuses
```

The `kind` here is the **plural name** (lowercase) as returned by
`kubectl api-resources`, not the singular Kind name. The `version` can
be `"*"` to match any version.

**Common CRD resource types:**

| CRD | group | kind (plural) |
|---|---|---|
| Prometheus | `monitoring.coreos.com` | `prometheuses` |
| Alertmanager | `monitoring.coreos.com` | `alertmanagers` |
| ServiceMonitor | `monitoring.coreos.com` | `servicemonitors` |
| Certificate | `cert-manager.io` | `certificates` |
| Issuer | `cert-manager.io` | `issuers` |

You can also reference CRDs using the full `group/kind` string format
in the `resourceTypes` list:

```yaml
resourceTypes:
  - prometheuses.monitoring.coreos.com
```

---

## Match Rule Types

Match rules determine which discovered resources trigger SLX generation.
All entries in `matchRules` are **AND'd** together.

### `pattern` -- Property Matching

Match a regex pattern against one or more resource properties:

```yaml
matchRules:
  - type: pattern
    pattern: ".+"
    properties: [name]
    mode: substring    # or: exact (default: substring)
```

**Built-in property names** (handled specially by the Kubernetes enricher):

| Property | Matches Against |
|---|---|
| `name` | Resource name |
| `labels` | All label keys + values |
| `label-keys` | Only label keys |
| `label-values` | Only label values |
| `annotations` | All annotation keys + values |
| `annotation-keys` | Only annotation keys |
| `annotation-values` | Only annotation values |

**JSON path properties** -- Any property name not in the built-in list
is treated as a JSON path into the raw resource data:

```yaml
matchRules:
  - type: pattern
    pattern: "nginx"
    properties: [spec/tls/hosts]
    mode: substring
```

Use `//` to escape literal slashes in path components (e.g.,
annotation keys containing `/`):

```yaml
properties: [metadata/annotations/kubernetes.io//ingress.class]
```

### `exists` -- Path Existence Check

Check whether a JSON path exists in the resource data:

```yaml
matchRules:
  - type: exists
    path: spec/tls
    matchEmpty: false   # default: false
```

### `custom-variable` -- Workspace Variable Match

Match against workspace-level custom variables (from `workspaceInfo.yaml`
custom definitions):

```yaml
matchRules:
  - type: custom-variable
    path: kubernetes_distribution
    pattern: "openshift"
    mode: substring
```

### Compound Match Rules

#### `and` -- All Must Match

```yaml
matchRules:
  - type: and
    matches:
      - type: pattern
        pattern: ".+"
        properties: [name]
        mode: substring
      - type: pattern
        pattern: ".+"
        properties: [spec/tls/hosts]
        mode: substring
```

#### `or` -- Any Must Match

```yaml
matchRules:
  - type: or
    matches:
      - type: pattern
        pattern: "nginx"
        properties: [annotations]
      - type: pattern
        pattern: "traefik"
        properties: [annotations]
```

#### `not` -- Negation

```yaml
matchRules:
  - type: not
    match:
      type: pattern
      pattern: "kube-system"
      properties: [name]
      mode: exact
```

### Cross-Resource Matching

A `pattern` rule can optionally specify a `resourceType` to match
against a *different* resource type. If matched, the resource is stored
in the template variables under `resources[resource_type_name]`:

```yaml
matchRules:
  - type: pattern
    resourceType: service
    pattern: "prometheus"
    properties: [name]
    mode: substring
```

---

## Qualifier Hierarchy

Qualifiers scope how SLXs are grouped. Available Kubernetes qualifiers:

| Qualifier | Value Source |
|---|---|
| `resource` | Resource name (one SLX per resource) |
| `namespace` | Namespace name |
| `cluster` | Cluster name |
| `context` | Kubernetes context name |
| `subscription_id` | Azure subscription ID (AKS clusters) |
| `subscription_name` | Azure subscription name (AKS clusters) |

Common qualifier patterns:

```yaml
# One SLX per resource per namespace per cluster (most granular)
qualifiers: ["resource", "namespace", "cluster"]

# One SLX per namespace per cluster
qualifiers: ["namespace", "cluster"]

# One SLX per cluster
qualifiers: ["cluster"]
```

---

## Level of Detail

Controls which output items are emitted based on the namespace's
configured LOD:

| Level | Value | When Used |
|---|---|---|
| `basic` | 1 | Default; emits for all namespaces |
| `detailed` | 2 | Only emits for namespaces at "detailed" LOD |

Set on each SLX definition:

```yaml
slxs:
  - baseName: k8s-deployment-hc
    qualifiers: ["resource", "namespace", "cluster"]
    levelOfDetail: detailed
```

---

## SLX Configuration

### `baseName` and `shortenedBaseName`

`baseName` is used to form the SLX directory name. If longer than 15
characters, it is automatically shortened. Provide `shortenedBaseName`
to control how it's shortened:

```yaml
slxs:
  - baseName: k8s-deployment-healthcheck
    shortenedBaseName: k8s-dep-hc
```

### `baseTemplateName`

Defaults to `baseName`. Used to form template file names:

```yaml
baseTemplateName: k8s-deployment-healthcheck
# Templates resolved: k8s-deployment-healthcheck-slx.yaml,
#                     k8s-deployment-healthcheck-taskset.yaml, etc.
```

### `outputItems`

Each output item generates one file per matched resource:

```yaml
outputItems:
  - type: slx
  - type: sli
  - type: runbook
    templateName: k8s-deployment-healthcheck-taskset.yaml
```

Supported types: `slx`, `sli`, `slo`, `runbook`, `taskset`, `workflow`.

If `templateName` is omitted, it defaults to
`{baseTemplateName}-{type}.yaml`.

Output items can have their own `levelOfDetail` and `templateVariables`:

```yaml
outputItems:
  - type: sli
    levelOfDetail: detailed
    templateVariables:
      CUSTOM_VAR: "some-value"
```

---

## Standard Template Variables (Kubernetes)

These variables are automatically available in all Kubernetes templates:

| Variable | Type | Description |
|---|---|---|
| `cluster` | Object | Cluster resource (has `.name`, `.context`) |
| `context` | String | Kubernetes context name |
| `namespace` | Object | Namespace resource (has `.name`) |
| `subscription_id` | String | Azure subscription ID (AKS only) |
| `subscription_name` | String | Azure subscription name (AKS only) |
| `match_resource` | Object | The matched resource (has `.resource.metadata.*`) |
| `workspace` | Dict | `{name, short_name, owner_email}` |
| `default_location` | String | Location ID from workspace config |
| `repo_url` | String | Code collection Git URL |
| `ref` | String | Git ref (branch/tag) |
| `slx_name` | String | Full SLX name (workspace--qualified) |
| `base_name` | String | SLX base name |
| `slx_directory_path` | String | Output directory for this SLX |
| `qualifiers` | Dict | Resolved qualifier values |
| `custom` | Dict | Custom definitions from workspaceInfo.yaml |
| `secrets` | Dict | Secrets from workspaceInfo.yaml |
| `wb_version` | String | RunWhen Local version |
| `child_resource_names` | List | Aggregated names (when no `resource` qualifier) |

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
  imageURL: https://storage.googleapis.com/runwhen-nonprod-shared-images/icons/kubernetes/resources/labeled/{icon}.svg
  alias: {{match_resource.resource.metadata.name}} {Display Name}
  asMeasuredBy: {What the SLI measures.}
  configProvided:
  - name: OBJECT_NAME
    value: {{match_resource.resource.metadata.name}}
  owners:
  - {{workspace.owner_email}}
  statement: {Healthy state description.}
  additionalContext:
    {% include "kubernetes-hierarchy.yaml" ignore missing %}
    qualified_name: "{{ match_resource.qualified_name }}"
  tags:
    {% include "kubernetes-tags.yaml" ignore missing %}
    - name: access
      value: read-only
```

### Taskset (Runbook) Template

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
    - name: NAMESPACE
      value: "{{match_resource.resource.metadata.namespace}}"
    - name: CONTEXT
      value: "{{context}}"
    - name: KUBERNETES_DISTRIBUTION_BINARY
      value: "{{custom.kubernetes_distribution_binary | default('kubectl')}}"
  secretsProvided:
  {% if wb_version %}
    {% include "kubernetes-auth.yaml" ignore missing %}
  {% else %}
    - name: kubeconfig
      workspaceKey: {{custom.kubeconfig_secret_name | default("kubeconfig")}}
  {% endif %}
```

### SLI Template

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
    pathToRobot: codebundles/{codebundle-dir-name}/sli.robot
  intervalStrategy: intermezzo
  intervalSeconds: 300
  configProvided:
    - name: NAMESPACE
      value: "{{match_resource.resource.metadata.namespace}}"
    - name: CONTEXT
      value: "{{context}}"
    - name: KUBERNETES_DISTRIBUTION_BINARY
      value: "{{custom.kubernetes_distribution_binary | default('kubectl')}}"
  secretsProvided:
  {% if wb_version %}
    {% include "kubernetes-auth.yaml" ignore missing %}
  {% else %}
    - name: kubeconfig
      workspaceKey: {{custom.kubeconfig_secret_name | default("kubeconfig")}}
  {% endif %}
```

### Icon Paths

Kubernetes icons are at:
`https://storage.googleapis.com/runwhen-nonprod-shared-images/icons/kubernetes/resources/labeled/`

| Resource | Icon |
|---|---|
| Deployment | `deploy.svg` |
| StatefulSet | `sts.svg` |
| DaemonSet | `ds.svg` |
| Service | `svc.svg` |
| Ingress | `ing.svg` |
| Pod | `pod.svg` |
| PVC | `pvc.svg` |
| Namespace | `ns.svg` |

---

## Common Mistakes

1. **Setting `platform: kubernetes`** -- It's the default, so omitting
   the platform field entirely is cleaner and conventional.

2. **Using CRD plural names directly as `resourceTypes`** -- For CRDs,
   use either the `custom:` dict form with `group/version/kind` or the
   full `{plural}.{group}` string form.

3. **Forgetting the `//` escape in JSON paths** -- Annotation keys like
   `kubernetes.io/ingress.class` contain slashes that must be escaped
   as `//` in property paths.

4. **Using `exact` mode when `substring` is needed** -- `exact` uses
   `pattern.match()` (anchored at start), while `substring` uses
   `pattern.search()`. Most rules should use `substring` (the default).

5. **Scoping to individual Pods** -- Pods are ephemeral. Prefer
   Deployment, StatefulSet, or DaemonSet as the resource type.

6. **Missing `kubernetes-auth.yaml` include** -- Always use the platform
   include for auth; never hardcode kubeconfig paths.

7. **`baseName` too long** -- Keep `baseName` under 15 characters or
   provide `shortenedBaseName`. Long names are auto-shortened, which
   may produce unreadable results.
