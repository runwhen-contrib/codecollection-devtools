---
description: How to author .test/ directories for Kubernetes CodeBundles
globs: "**/.test/**,**/codebundles/**"
alwaysApply: false
---

# Test Infrastructure -- Kubernetes Platform

This guide covers how to author `.test/` directories for Kubernetes
CodeBundles in `rw-cli-codecollection`.

Read this **after** reading `docs/creator/sre-mode-guide.md`.

---

## Directory Structure

Kubernetes test infrastructure uses **two distinct patterns** depending
on whether the CodeBundle needs purpose-built resources:

### Pattern A -- Static Manifests (preferred for most K8s bundles)

```
.test/
├── Taskfile.yaml
├── kubernetes/
│   └── manifest.yaml      # Static K8s manifests (Namespace, Deployment, PVC, etc.)
└── README.md              # Optional
```

### Pattern B -- Terraform (complex setups, e.g. Istio, EKS)

```
.test/
├── Taskfile.yaml
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf
│   └── versions.tf
└── README.md
```

---

## Standard Task Names

Every Taskfile must implement these tasks. They form the contract that
developers and CI systems rely on:

| Task | Purpose |
|---|---|
| `default` | `check-unpushed-commits` → `generate-rwl-config` → `run-rwl-discovery` |
| `clean` | Tear down infra + delete SLXs + clean discovery output |
| `build-infra` | Create test resources (manifests or Terraform) |
| `check-unpushed-commits` | Verify CodeBundle code is committed & pushed |
| `generate-rwl-config` | Write `workspaceInfo.yaml` for RunWhen Local |
| `run-rwl-discovery` | Start RunWhen Local container and run discovery |
| `validate-generation-rules` | Validate `.runwhen/generation-rules/*.yaml` against JSON schema |
| `upload-slxs` | Optional: upload generated SLXs to RunWhen Platform |
| `delete-slxs` | Optional: delete SLXs from RunWhen Platform |
| `clean-rwl-discovery` | Remove `output/` and `workspaceInfo.yaml` |

---

## Pattern A: Static Manifests Taskfile

This is the standard Taskfile for Kubernetes bundles that create test
resources via `kubectl apply`. Based on real `k8s-pvc-healthcheck`:

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
      - task: remove-kubernetes-objects
      - task: delete-slxs
      - task: clean-rwl-discovery

  build-infra:
    desc: "Build test infrastructure"
    cmds:
      - task: create-kubernetes-objects

  create-kubernetes-objects:
    desc: "Apply manifests from kubernetes directory using kubectl"
    cmds:
     - kubectl apply -f kubernetes/*
    silent: true

  remove-kubernetes-objects:
    desc: "Delete kubernetes objects"
    cmds:
     - kubectl delete -f kubernetes/*
    silent: true

  check-unpushed-commits:
    desc: Check if outstanding commits or file updates need to be pushed before testing.
    vars:
      BASE_DIR: "../"
    cmds:
      - |
        echo "Checking for uncommitted changes in $BASE_DIR and $BASE_DIR.runwhen, excluding '.test'..."
        UNCOMMITTED_FILES=$(git diff --name-only HEAD | grep -E "^${BASE_DIR}(\.runwhen|[^/]+)" | grep -v "/\.test/" || true)
        if [ -n "$UNCOMMITTED_FILES" ]; then
          echo "✗"
          echo "Uncommitted changes found:"
          echo "$UNCOMMITTED_FILES"
          echo "Remember to commit & push changes before executing the run-rwl-discovery task."
          echo "------------"
          exit 1
        else
          echo "√"
          echo "No uncommitted changes in specified directories."
          echo "------------"
        fi
      - |
        echo "Checking for unpushed commits in $BASE_DIR and $BASE_DIR.runwhen, excluding '.test'..."
        git fetch origin
        UNPUSHED_FILES=$(git diff --name-only origin/$(git rev-parse --abbrev-ref HEAD) HEAD | grep -E "^${BASE_DIR}(\.runwhen|[^/]+)" | grep -v "/\.test/" || true)
        if [ -n "$UNPUSHED_FILES" ]; then
          echo "✗"
          echo "Unpushed commits found:"
          echo "$UNPUSHED_FILES"
          echo "Remember to push changes before executing the run-rwl-discovery task."
          echo "------------"
          exit 1
        else
          echo "√"
          echo "No unpushed commits in specified directories."
          echo "------------"
        fi
    silent: true

  generate-rwl-config:
    desc: "Generate RunWhen Local configuration (workspaceInfo.yaml)"
    env:
      RW_WORKSPACE: '{{.RW_WORKSPACE | default "my-workspace"}}'
    cmds:
      - |
        repo_url=$(git config --get remote.origin.url)
        branch_name=$(git rev-parse --abbrev-ref HEAD)
        codebundle=$(basename "$(dirname "$PWD")")

        namespace=$(yq e 'select(.kind == "Namespace") | .metadata.name' kubernetes/manifest.yaml -N)
        cat <<EOF > workspaceInfo.yaml
        workspaceName: "$RW_WORKSPACE"
        workspaceOwnerEmail: authors@runwhen.com
        defaultLocation: location-01
        defaultLOD: none
        cloudConfig:
          kubernetes:
            kubeconfigFile: /shared/kubeconfig
            namespaceLODs:
              $namespace: detailed
            namespaces:
              - $namespace
        codeCollections:
        - repoURL: "$repo_url"
          branch: "$branch_name"
          codeBundles: ["$codebundle"]
        custom:
          kubeconfig_secret_name: "kubeconfig"
          kubernetes_distribution_binary: kubectl
        EOF
    silent: true

  run-rwl-discovery:
    desc: "Run RunWhen Local Discovery on test infrastructure"
    cmds:
      - |
        CONTAINER_NAME="RunWhenLocal"
        if docker ps -q --filter "name=$CONTAINER_NAME" | grep -q .; then
          echo "Stopping and removing existing container $CONTAINER_NAME..."
          docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME
        elif docker ps -a -q --filter "name=$CONTAINER_NAME" | grep -q .; then
          echo "Removing existing stopped container $CONTAINER_NAME..."
          docker rm $CONTAINER_NAME
        else
          echo "No existing container named $CONTAINER_NAME found."
        fi

        echo "Cleaning up output directory..."
        sudo rm -rf output || { echo "Failed to remove output directory"; exit 1; }
        mkdir output && chmod 777 output || { echo "Failed to set permissions"; exit 1; }

        echo "Starting new container $CONTAINER_NAME..."

        kubeconfig=$(echo $RW_FROM_FILE | jq -r .kubeconfig)

        docker run --name $CONTAINER_NAME -p 8081:8081 \
          -v "$(pwd)":/shared \
          -v $kubeconfig:/shared/kubeconfig \
          -d ghcr.io/runwhen-contrib/runwhen-local:latest || {
          echo "Failed to start container"; exit 1;
        }

        echo "Running workspace builder script in container..."
        docker exec -w /workspace-builder $CONTAINER_NAME ./run.sh $1 --verbose || {
          echo "Error executing script in container"; exit 1;
        }

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

  clean-rwl-discovery:
    desc: "Check and clean up RunWhen Local discovery output"
    cmds:
      - |
        sudo rm -rf output
        rm -f workspaceInfo.yaml
        rm -f kubeconfig
    silent: true
```

---

## Static Manifest Example (`kubernetes/manifest.yaml`)

Create a dedicated namespace with the resources the CodeBundle checks.
Based on real `k8s-pvc-healthcheck`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: test-fill-volume

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: test-fill-volume
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-deployment
  namespace: test-fill-volume
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-fill
  template:
    metadata:
      labels:
        app: test-fill
    spec:
      containers:
        - name: test-container
          image: busybox
          command: ["/bin/sh", "-c"]
          args:
            - |
              while true; do sleep 30; done;
          volumeMounts:
            - mountPath: /data
              name: test-storage
      volumes:
        - name: test-storage
          persistentVolumeClaim:
            claimName: test-pvc
```

Key conventions:
- Always create a **dedicated namespace** so teardown is clean
- The namespace name should be descriptive (e.g., `test-fill-volume`)
- Include both healthy and unhealthy resources when possible
- Use simple, lightweight images like `busybox` or `nginx:stable`
- The filename is typically `manifest.yaml` (note: some older bundles
  misspell it as `mainfest.yaml`)

---

## workspaceInfo.yaml -- Key Fields

### `namespaceLODs` and `namespaces`

For Kubernetes bundles, **always** scope discovery to the test namespace.
Use `defaultLOD: none` and set the test namespace to `detailed`:

```yaml
cloudConfig:
  kubernetes:
    kubeconfigFile: /shared/kubeconfig
    namespaceLODs:
      test-fill-volume: detailed
    namespaces:
      - test-fill-volume
```

This prevents discovery from scanning the entire cluster and produces
output only for the test namespace.

### `custom` section

The `custom` section provides template variables used in generation rules:

```yaml
custom:
  kubeconfig_secret_name: "kubeconfig"
  kubernetes_distribution_binary: kubectl
```

Additional custom variables depend on the CodeBundle's runbook parameters
(e.g., `excluded_namespaces`, `cpu_usage_threshold`).

### Kubeconfig mounting

There are two patterns in the codebase:

1. **`RW_FROM_FILE` pattern** -- kubeconfig path from JSON env var:
   ```bash
   kubeconfig=$(echo $RW_FROM_FILE | jq -r .kubeconfig)
   docker run ... -v $kubeconfig:/shared/kubeconfig ...
   ```

2. **Direct mount** -- kubeconfig copied to `.test/` directory:
   ```bash
   docker run ... -v "$(pwd)":/shared ...
   ```
   With `kubeconfigFile: /shared/kubeconfig.secret` in workspaceInfo.

---

## Pattern B: Terraform Taskfile

For CodeBundles that need complex infrastructure (e.g., Istio, CRDs),
add Terraform lifecycle tasks. The key differences from Pattern A:

```yaml
  build-infra:
    desc: "Build test infrastructure"
    cmds:
      - task: build-terraform-infra

  build-terraform-infra:
    desc: "Run terraform apply"
    cmds:
      - |
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
```

And update `clean` to use `check-and-cleanup-terraform`:

```yaml
  clean:
    desc: "Run cleanup tasks"
    cmds:
      - task: check-and-cleanup-terraform
      - task: delete-slxs
      - task: clean-rwl-discovery
```

---

## Optional: Upload/Delete SLXs

Include these tasks for end-to-end validation against the RunWhen Platform.
Requires env vars: `RW_WORKSPACE`, `RW_API` (URL), `RW_PAT` (token).

```yaml
  check-rwp-config:
    desc: Check if env vars are set for RunWhen Platform
    cmds:
      - |
        missing_vars=()
        [ -z "$RW_WORKSPACE" ] && missing_vars+=("RW_WORKSPACE")
        [ -z "$RW_API_URL" ] && missing_vars+=("RW_API_URL")
        [ -z "$RW_PAT" ] && missing_vars+=("RW_PAT")
        if [ ${#missing_vars[@]} -ne 0 ]; then
          echo "The following required environment variables are missing: ${missing_vars[*]}"
          exit 1
        fi
    silent: true

  upload-slxs:
    desc: "Upload SLX files to the appropriate URL"
    env:
      RW_WORKSPACE: "{{.RW_WORKSPACE}}"
      RW_API_URL: "{{.RW_API}}"
      RW_PAT: "{{.RW_PAT}}"
    cmds:
      - task: check-rwp-config
      - |
        BASE_DIR="output/workspaces/${RW_WORKSPACE}/slxs"
        if [ ! -d "$BASE_DIR" ]; then
          echo "Directory $BASE_DIR does not exist. Upload aborted."
          exit 1
        fi
        for dir in "$BASE_DIR"/*; do
          if [ -d "$dir" ]; then
            SLX_NAME=$(basename "$dir")
            PAYLOAD=$(jq -n --arg commitMsg "Creating new SLX $SLX_NAME" '{ commitMsg: $commitMsg, files: {} }')
            for file in slx.yaml runbook.yaml sli.yaml; do
              if [ -f "$dir/$file" ]; then
                CONTENT=$(cat "$dir/$file")
                PAYLOAD=$(echo "$PAYLOAD" | jq --arg fileContent "$CONTENT" --arg fileName "$file" '.files[$fileName] = $fileContent')
              fi
            done
            URL="https://${RW_API_URL}/api/v3/workspaces/${RW_WORKSPACE}/branches/main/slxs/${SLX_NAME}"
            echo "Uploading SLX: $SLX_NAME to $URL"
            response_code=$(curl -X POST "$URL" \
              -H "Authorization: Bearer $RW_PAT" \
              -H "Content-Type: application/json" \
              -d "$PAYLOAD" -w "%{http_code}" -o /dev/null -s)
            if [[ "$response_code" == "200" || "$response_code" == "201" ]]; then
              echo "Successfully uploaded SLX: $SLX_NAME"
            else
              echo "Failed to upload SLX: $SLX_NAME. Response code: $response_code"
            fi
          fi
        done
    silent: true

  delete-slxs:
    desc: "Delete SLX objects from the appropriate URL"
    env:
      RW_WORKSPACE: '{{.RW_WORKSPACE | default "my-workspace"}}'
      RW_API_URL: "{{.RW_API}}"
      RW_PAT: "{{.RW_PAT}}"
    cmds:
      - task: check-rwp-config
      - |
        BASE_DIR="output/workspaces/${RW_WORKSPACE}/slxs"
        if [ ! -d "$BASE_DIR" ]; then
          echo "Directory $BASE_DIR does not exist. Deletion aborted."
          exit 1
        fi
        for dir in "$BASE_DIR"/*; do
          if [ -d "$dir" ]; then
            SLX_NAME=$(basename "$dir")
            URL="https://${RW_API_URL}/api/v3/workspaces/${RW_WORKSPACE}/branches/main/slxs/${SLX_NAME}"
            echo "Deleting SLX: $SLX_NAME from $URL"
            response_code=$(curl -X DELETE "$URL" \
              -H "Authorization: Bearer $RW_PAT" \
              -H "Content-Type: application/json" -w "%{http_code}" -o /dev/null -s)
            if [[ "$response_code" == "200" || "$response_code" == "204" ]]; then
              echo "Successfully deleted SLX: $SLX_NAME"
            else
              echo "Failed to delete SLX: $SLX_NAME. Response code: $response_code"
            fi
          fi
        done
    silent: true
```

---

## Common Mistakes

1. **Missing `check-unpushed-commits`** -- Must be the first step in the
   `default` task. RunWhen Local clones from the remote, so local-only
   changes are invisible to discovery.

2. **Not scoping `namespaceLODs`** -- Use `defaultLOD: none` and set
   only the test namespace to `detailed`. Scanning the whole cluster is
   slow and produces unrelated output.

3. **Forgetting `kubeconfig_secret_name` in `custom`** -- Many generation
   rule templates reference `${kubeconfig_secret_name}`. Omitting it
   causes empty values in generated SLX configs.

4. **Missing `validate-generation-rules` task** -- Use the JSON schema
   from `runwhen-local` to catch structural errors before discovery.

5. **Committing secrets** -- Add `*.secret`, `kubeconfig`, `terraform.tfstate*`,
   `.terraform/`, and `output/` to `.gitignore`.

6. **Using wrong manifest filename** -- Ensure `generate-rwl-config`
   reads the correct filename when extracting the namespace with `yq`.

7. **Not providing `codeBundles` scope** -- Always use
   `codeBundles: ["$codebundle"]` to scope discovery to this CodeBundle only.
