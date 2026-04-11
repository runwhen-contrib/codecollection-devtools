---
description: How to author generation rules and templates for AWS CodeBundles
globs: "**/.runwhen/**,**/codebundles/**"
alwaysApply: false
---

# Generation Rules -- AWS Platform

This guide covers how to author `.runwhen/generation-rules/` and
`.runwhen/templates/` for AWS CodeBundles, including Cloud Custodian
(`aws-c7n-codecollection`) and CLI-based bundles in
`rw-cli-codecollection`.

---

## Platform Identifier

AWS resources must explicitly set `platform: aws` in the generation
rules spec:

```yaml
apiVersion: runwhen.com/v1
kind: GenerationRules
spec:
  platform: aws
  generationRules:
    - resourceTypes:
        - s3_bucket
```

---

## Resource Types

AWS resource type names correspond to **CloudQuery table names** as
registered by the indexer. These are *not* enumerated in the enricher
code -- they come from whatever resources the CloudQuery AWS provider
discovers. Common examples:

| resourceType | AWS Service |
|---|---|
| `s3_bucket` | S3 Buckets |
| `ec2_instance` | EC2 Instances |
| `rds_instance` | RDS Instances |
| `lambda_function` | Lambda Functions |
| `elb_load_balancer` | Classic Load Balancers |
| `elbv2_load_balancer` | ALB/NLB |
| `iam_role` | IAM Roles |
| `cloudwatch_alarm` | CloudWatch Alarms |
| `ecs_cluster` | ECS Clusters |
| `eks_cluster` | EKS Clusters |

The exact available types depend on which CloudQuery tables are
configured in the workspace's `cloudConfig`.

---

## Match Rule Types

AWS supports the same match rule system as all platforms
(`pattern`, `exists`, `custom-variable`, `and`, `or`, `not`).
See `generation-rules-kubernetes.md` for the full match rule reference.

### AWS-Specific Property Names

The AWS enricher recognizes these built-in property names for `pattern`
rules:

| Property | Matches Against |
|---|---|
| `name` | Resource name |
| `tags` | All tag keys + values |
| `tag-keys` | Only tag keys |
| `tag-values` | Only tag values |
| `account_id` | AWS Account ID |
| `region` | AWS Region |
| `service` | AWS Service name (from ARN) |
| `arn` | Full ARN string |
| `is_public` | Public access status |
| `auth_type` | Authentication method used |
| `account_alias` | Account alias |
| `account_name` | Account name from config |
| `assume_role_arn` | Assumed role ARN |
| `auth_secret` | Auth secret name |

Any property name not in the built-in list is treated as a JSON path
into the raw CloudQuery resource data.

---

## Qualifier Hierarchy

AWS qualifiers scope how SLXs are grouped:

| Qualifier | Value Source |
|---|---|
| `resource` | Resource name |
| `account_id` | AWS Account ID |
| `region` | AWS Region |
| `service` | Service name from ARN |
| `is_public` | Public flag (stringified) |
| `arn` | Full ARN |
| `auth_type` | Authentication type |
| `account_alias` | Account alias |
| `account_name` | Account name |
| `assume_role_arn` | Assumed role ARN |
| `auth_secret` | Auth secret name |

Common qualifier patterns:

```yaml
# One SLX per resource per account per region
qualifiers: ["resource", "account_id", "region"]

# One SLX per account
qualifiers: ["account_id"]
```

---

## Level of Detail

AWS uses the same `basic` / `detailed` LOD system. LOD can be set via
resource tags with keys `lod`, `levelofdetail`, or `level-of-detail`.
Default is whatever `DEFAULT_LOD` is configured in the workspace.

---

## Standard Template Variables (AWS)

These are automatically injected by the AWS enricher:

| Variable | Type | Description |
|---|---|---|
| `account_id` | String | AWS Account ID |
| `region` | String | AWS Region |
| `service` | String | Service name from ARN |
| `is_public` | String | "True" or "False" |
| `arn` | String | Full ARN |
| `auth_type` | String | Auth method (e.g., `aws_explicit`) |
| `account_alias` | String | Account alias |
| `account_name` | String | Account friendly name |
| `assume_role_arn` | String | Role ARN if using assume-role |
| `auth_secret` | String | K8s secret name for credentials |
| `tag_{key}` | String | One variable per resource tag |

Plus all the standard variables (`workspace`, `default_location`,
`repo_url`, `ref`, `slx_name`, `match_resource`, `custom`, `secrets`,
etc.) described in the Kubernetes guide.

---

## Template Anatomy

### SLX Template (AWS)

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
  imageURL: https://storage.googleapis.com/runwhen-nonprod-shared-images/icons/aws/{resource}.svg
  alias: "{{match_resource.resource.name}} AWS Health"
  asMeasuredBy: {Measure description.}
  configProvided:
    - name: AWS_REGION
      value: "{{region}}"
    - name: AWS_ACCOUNT_ID
      value: "{{account_id}}"
  owners:
    - {{workspace.owner_email}}
  statement: "{Healthy state description.}"
```

### Taskset Template (AWS)

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
    repoUrl: https://github.com/runwhen-contrib/aws-c7n-codecollection.git
    {% endif %}
    {% if ref %}
    ref: {{ref}}
    {% else %}
    ref: main
    {% endif %}
    pathToRobot: codebundles/{codebundle-dir-name}/runbook.robot
  configProvided:
    - name: AWS_REGION
      value: "{{region}}"
    - name: AWS_ACCOUNT_ID
      value: "{{account_id}}"
  secretsProvided:
  {% if wb_version %}
    {% include "aws-auth.yaml" ignore missing %}
  {% else %}
    - name: AWS_ACCESS_KEY_ID
      workspaceKey: {{custom.aws_access_key_id_secret | default("AWS_ACCESS_KEY_ID")}}
    - name: AWS_SECRET_ACCESS_KEY
      workspaceKey: {{custom.aws_secret_access_key_secret | default("AWS_SECRET_ACCESS_KEY")}}
  {% endif %}
```

### Auth Include

AWS templates should use `{% include "aws-auth.yaml" ignore missing %}`
for secrets. This lets the platform provide the appropriate auth
mechanism (explicit keys, assume-role, or IRSA).

### Icon Paths

AWS icons are at:
`https://storage.googleapis.com/runwhen-nonprod-shared-images/icons/aws/`

---

## aws-c7n-codecollection Specifics

When authoring CodeBundles for the `aws-c7n-codecollection`:

- The `repoUrl` defaults to
  `https://github.com/runwhen-contrib/aws-c7n-codecollection.git`
- Cloud Custodian policies are embedded in the runbook.robot using
  `RW.CLI.Run Bash File`
- Always include `AWS_REGION` and `AWS_ACCOUNT_ID` in `configProvided`
- Use `aws-auth.yaml` include for secrets

---

## Common Mistakes

1. **Omitting `platform: aws`** -- Without this, resources are treated
   as Kubernetes and won't match.

2. **Hardcoding AWS credentials** -- Always use the `aws-auth.yaml`
   include or equivalent platform-provided auth.

3. **Using Kubernetes qualifiers** -- `namespace`, `cluster`, `context`
   are Kubernetes-specific. Use `account_id`, `region`, etc. for AWS.

4. **Assuming specific CloudQuery table names** -- Resource type names
   come from CloudQuery. Verify which tables are available in the
   workspace's cloud configuration.

5. **Not providing `account_name` in templates** -- For multi-account
   setups, `account_name` provides a human-readable identifier vs.
   just the numeric `account_id`.
