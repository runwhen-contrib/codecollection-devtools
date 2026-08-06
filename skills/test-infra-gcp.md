---
description: How to build .test infrastructure for GCP CodeBundles (Taskfile, workspaceInfo, terraform, RunWhen Local discovery)
globs: "**/.test/**,**/codebundles/gcp-*/**"
alwaysApply: false
---

# Test Infrastructure -- GCP CodeBundles

This guide covers the `.test/` directory for GCP CodeBundles. The
Taskfile's purpose is to test **discovery and template rendering** --
not to run scenario tests.

For shared patterns (tf.secret, .gitignore, Terraform files, tagging),
see `test-infra-cloud.md`.

---

## Purpose

The `.test/Taskfile.yaml` for a GCP CodeBundle has one job:

1. Generate a valid `workspaceInfo.yaml` from the codebundle's
   generation rules.
2. Run RunWhen Local discovery against that config.
3. Validate the `.runwhen/generation-rules/*.yaml` schema.

Do **not** add scenario-test tasks (`test-*-scenario`, etc.) --
health-check behavior is validated by the codebundle's robot files,
not by Taskfile stubs.

---

## Required Taskfile Structure

```yaml
version: "3"

silent: true

vars:
  codebundle: "<codebundle-name>"

tasks:
  default:
    desc: "Run discovery and template validation"
    cmds:
      - task: check-unpushed-commits
      - task: generate-rwl-config
      - task: run-rwl-discovery
      - task: validate-generation-rules

  clean:
    desc: "Run cleanup tasks"
    cmds:
      - task: delete-slxs
      - task: clean-rwl-discovery

  check-unpushed-commits:
    desc: "Check for uncommitted/unpushed changes before testing"
    vars:
      BASE_DIR: "../"
    cmds:
      - |
        UNCOMMITTED_FILES=$(git diff --name-only HEAD | grep -E "^${BASE_DIR}(\.runwhen|[^/]+)" | grep -v "/\.test/" || true)
        if [ -n "$UNCOMMITTED_FILES" ]; then
          echo "✗ Uncommitted changes found:"
          echo "$UNCOMMITTED_FILES"
          echo "Remember to commit & push changes before executing the run-rwl-discovery task."
          exit 1
        else
          echo "√ No uncommitted changes in specified directories."
        fi
      - |
        git fetch origin
        UNPUSHED_FILES=$(git diff --name-only origin/$(git rev-parse --abbrev-ref HEAD) HEAD | grep -E "^${BASE_DIR}(\.runwhen|[^/]+)" | grep -v "/\.test/" || true)
        if [ -n "$UNPUSHED_FILES" ]; then
          echo "✗ Unpushed commits found:"
          echo "$UNPUSHED_FILES"
          echo "Remember to push changes before executing the run-rwl-discovery task."
          exit 1
        else
          echo "√ No unpushed commits in specified directories."
        fi

  generate-rwl-config:
    desc: "Generate RunWhen Local configuration (workspaceInfo.yaml)"
    env:
      GCP_PROJECT_ID: "{{.GCP_PROJECT_ID}}"
      RW_WORKSPACE: '{{.RW_WORKSPACE | default "my-workspace"}}'
    cmds:
      - |
        repo_url=$(git config --get remote.origin.url)
        branch_name=$(git rev-parse --abbrev-ref HEAD)
        codebundle=$(basename "$(dirname "$PWD")")

        cat <<EOF > workspaceInfo.yaml
        workspaceName: "$RW_WORKSPACE"
        workspaceOwnerEmail: authors@runwhen.com
        defaultLocation: location-01-us-west1
        defaultLOD: detailed
        writeWorkspaceFilesToDisk: true
        cloudConfig:
          gcp:
            applicationCredentialsFile: /shared/gcp.json.secret
            projects:
            - $GCP_PROJECT_ID
            projectLevelOfDetails:
              $GCP_PROJECT_ID: detailed
        codeCollections:
        - repoURL: "$repo_url"
          branch: "$branch_name"
          codeBundles: ["$codebundle"]
        EOF

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

        sudo rm -rf output || { echo "Failed to remove output directory"; exit 1; }
        mkdir output && chmod 777 output || { echo "Failed to set permissions"; exit 1; }

        docker run --name $CONTAINER_NAME -p 8081:8081 -v "$(pwd)":/shared -d ghcr.io/runwhen-contrib/runwhen-local:latest || {
          echo "Failed to start container"; exit 1;
        }

        docker exec -w /workspace-builder $CONTAINER_NAME ./run.sh $1 --verbose || {
          echo "Error executing script in container"; exit 1;
        }

        echo "Review generated config files under output/workspaces/"

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
        curl -s -o "$temp_dir/generation-rule-schema.json" https://raw.githubusercontent.com/runwhen-contrib/runwhen-local/refs/heads/main/src/generation-rule-schema.json

        for yaml_file in ../.runwhen/generation-rules/*.yaml; do
          echo "Validating $yaml_file"
          json_file="$temp_dir/$(basename "${yaml_file%.*}.json")"
          yq -o=json "$yaml_file" > "$json_file"
          ajv validate -s "$temp_dir/generation-rule-schema.json" -d "$json_file" --spec=draft2020 --strict=false \
          && echo "$yaml_file is valid." || echo "$yaml_file is invalid."
        done

        rm -rf "$temp_dir"

  check-rwp-config:
    desc: "Check if env vars are set for RunWhen Platform"
    cmds:
      - |
        missing_vars=()
        if [ -z "$RW_WORKSPACE" ]; then missing_vars+=("RW_WORKSPACE"); fi
        if [ -z "$RW_API_URL" ]; then missing_vars+=("RW_API_URL"); fi
        if [ -z "$RW_PAT" ]; then missing_vars+=("RW_PAT"); fi
        if [ ${#missing_vars[@]} -ne 0 ]; then
          echo "The following required environment variables are missing: ${missing_vars[*]}"
          exit 1
        fi

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
            response=$(curl -v -X POST "$URL" \
              -H "Authorization: Bearer $RW_PAT" \
              -H "Content-Type: application/json" \
              -d "$PAYLOAD" -w "%{http_code}" -o /dev/null -s 2>&1)

            if [[ "$response" =~ 200|201 ]]; then
              echo "Successfully uploaded SLX: $SLX_NAME to $URL"
            else
              echo "Failed to upload SLX: $SLX_NAME to $URL. Response:"
              echo "$response"
            fi
          fi
        done

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
            response=$(curl -v -X DELETE "$URL" \
              -H "Authorization: Bearer $RW_PAT" \
              -H "Content-Type: application/json" -w "%{http_code}" -o /dev/null -s 2>&1)

            if [[ "$response" =~ 200|204 ]]; then
              echo "Successfully deleted SLX: $SLX_NAME from $URL"
            else
              echo "Failed to delete SLX: $SLX_NAME from $URL. Response:"
              echo "$response"
            fi
          fi
        done

  clean-rwl-discovery:
    desc: "Clean up RunWhen Local discovery output"
    cmds:
      - |
        sudo rm -rf output
        rm -f workspaceInfo.yaml
```

---

## GCP workspaceInfo.yaml

For GCP project-level discovery (BigQuery, GCS, Pub/Sub, etc.), the
`cloudConfig.gcp` block is minimal -- no `gkeClusters` needed unless
the codebundle also discovers GKE clusters:

```yaml
workspaceName: "my-workspace"
workspaceOwnerEmail: authors@runwhen.com
defaultLocation: location-01-us-west1
defaultLOD: detailed
writeWorkspaceFilesToDisk: true
cloudConfig:
  gcp:
    applicationCredentialsFile: /shared/gcp.json.secret
    projects:
    - my-gcp-project
    projectLevelOfDetails:
      my-gcp-project: detailed
codeCollections:
- repoURL: "https://github.com/runwhen-contrib/rw-cli-codecollection.git"
  branch: "main"
  codeBundles: ["gcp-bigquery-dataset-health"]
```

Key points:

- **`writeWorkspaceFilesToDisk: true`** -- writes the rendered SLX
  YAMLs (slx.yaml, runbook.yaml, sli.yaml) to `output/workspaces/` so
  you can read and review them after discovery. Required for template
  debugging.
- **`applicationCredentialsFile: /shared/gcp.json.secret`** -- the
  RunWhen Local container mounts the `.test/` directory at `/shared`;
  place the service-account key at `.test/gcp.json.secret` (gitignored).
  Omit this field entirely for Workload Identity / ADC.
- **`projects`** -- the GCP project(s) to index. BigQuery/GCS/PubSub
  discovery is project-scoped; the indexer enumerates datasets/buckets
  in each listed project.
- **`projectLevelOfDetails`** -- controls how much detail is captured
  per project (`detailed` for full resource attributes).
- **`codeBundles: ["$codebundle"]`** -- always scope to the current
  bundle; RunWhen Local would otherwise render every bundle in the repo.

---

## terraform/ (optional, only if test resources are needed)

If the codebundle needs real GCP resources to discover (e.g. BigQuery
datasets/tables for the BigQuery bundle), keep a `terraform/` directory
with `main.tf`, `variables.tf`, `tf.secret`, and a
`build-terraform-infra` / `check-and-cleanup-terraform` task pair.
These are **not** part of the default discovery flow -- run them
explicitly when you need to provision the test fixtures.

Tag all test resources:

```hcl
labels = {
  env       = "test"
  lifecycle = "deleteme"
  product   = "runwhen"
}
```

---

## Common Mistakes

1. **Adding scenario-test tasks** -- The Taskfile tests discovery and
   template rendering. Health-check behavior is validated by the
   codebundle's robot files, not by `test-foo-scenario` stubs.

2. **Hardcoding `GCP_PROJECT_ID` or workspace name** -- Pass them via
   `task generate-rwl-config GCP_PROJECT_ID=... RW_WORKSPACE=...` or
   set them in the shell. The env block in the task definition supplies
   defaults only.

3. **Not scoping `codeBundles`** -- `codeBundles: ["$codebundle"]`
   limits rendering to the current bundle. Omitting it renders every
   bundle in the repo, producing unrelated SLXs.

4. **Forgetting `check-unpushed-commits`** -- RunWhen Local pulls from
   the remote branch. Uncommitted/unpushed changes are invisible to
   discovery.

5. **Using `output/` for workspaceInfo.yaml** -- `workspaceInfo.yaml`
   belongs at the `.test/` root (mounted at `/shared` in the container).
   `output/` is for the generated SLX artifacts.

6. **Setting `GOOGLE_APPLICATION_CREDENTIALS` in the container** --
   For Workload Identity, leave `applicationCredentialsFile` empty;
   setting `GOOGLE_APPLICATION_CREDENTIALS` short-circuits the
   metadata-server path.

---

## Reference Implementation

`codebundles/gcp-bigquery-dataset-health/.test/Taskfile.yaml` is the
canonical example for GCP project-level discovery.
