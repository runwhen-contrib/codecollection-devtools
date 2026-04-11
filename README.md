<div align="center">

![CodeCollection DevTools banner](assets/banner.svg)

# CodeCollection DevTools

**codecollection-devtools** is the standard development environment for authoring and testing [RunWhen](https://runwhen.com) codebundles. One image, any codecollection — pull the pre-built container, set an env var, and start developing.

[![Build and Push](https://github.com/runwhen-contrib/codecollection-devtools/actions/workflows/build-push.yaml/badge.svg)](https://github.com/runwhen-contrib/codecollection-devtools/actions/workflows/build-push.yaml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

[GitHub](https://github.com/runwhen-contrib/codecollection-devtools) · [GHCR](https://github.com/orgs/runwhen-contrib/packages/container/package/codecollection-devtools) · [Author Docs](https://docs.runwhen.com/public/v/runwhen-authors/)

</div>

---

## Key features

- **One image for all codecollections** — set `CODECOLLECTION_REPO` to bootstrap any codecollection repo automatically.
- **PR review ready** — set `PR_NUMBER` and the environment checks out the PR branch for you.
- **Multi-arch** — pre-built for both `linux/amd64` (Codespaces, CI) and `linux/arm64` (Apple Silicon).
- **Batteries included** — Robot Framework, `ro` test runner, kubectl, Helm, AWS CLI, Azure CLI, gcloud, Terraform, gh CLI, and more.
- **Works everywhere** — GitHub Codespaces, VS Code devcontainers (local), or plain `docker run`.

## Requirements

- **Docker** or a compatible runtime (Podman, OrbStack, etc.) — for local devcontainer use
- **GitHub Codespaces** — no local runtime needed; runs in the cloud
- A codecollection repo to work on (defaults to `rw-cli-codecollection`)

## Getting started

### Option 1: GitHub Codespaces (recommended for PR review)

Configure environment variables as **Codespace secrets**, then create the Codespace.

**Step 1 — Set Codespace secrets** (once per user, or per-repo):

Go to **github.com → Settings → Codespaces → Secrets** (or repo **Settings → Secrets and variables → Codespaces**) and add:

| Secret | Example | Required |
|--------|---------|----------|
| `CODECOLLECTION_REPO` | `runwhen-contrib/rw-cli-codecollection` | yes |
| `CODECOLLECTION_BRANCH` | `main` | no (defaults to `main`) |
| `PR_NUMBER` | `123` | no (checks out the PR branch) |

Or set them via the **`gh` CLI**:

```bash
gh secret set CODECOLLECTION_REPO --user --body "runwhen-contrib/rw-cli-codecollection"
gh secret set PR_NUMBER --user --body "123"
```

**Step 2 — Create the Codespace:**

1. Go to **github.com/runwhen-contrib/codecollection-devtools** → **Code** → **Codespaces** → **New with options**
2. Pick your branch, region, and machine type
3. Click **Create codespace**

The `on-create.sh` bootstrap script reads those secrets as environment variables, clones the repo, installs dependencies, and checks out the PR automatically.

### Option 2: VS Code devcontainer (local)

Clone this repo and open it in VS Code with the Dev Containers extension:

```bash
git clone https://github.com/runwhen-contrib/codecollection-devtools.git
cd codecollection-devtools
```

Set environment variables before opening the devcontainer:

```bash
export CODECOLLECTION_REPO="runwhen-contrib/rw-cli-codecollection"
export CODECOLLECTION_BRANCH="main"
# export PR_NUMBER="123"    # optional
```

Then open in VS Code → **Reopen in Container** (or `Cmd+Shift+P` → "Dev Containers: Reopen in Container").

The devcontainer pulls the pre-built image from GHCR — no local Docker build required.

#### Cursor with GitHub Codespaces

Use **Cursor** with a **Codespace** via **`gh codespace ssh`** and **Remote - SSH**. See **[Cursor + Codespaces + devcontainer](docs/cursor-remote-devcontainer.md)**.

### Option 3: Docker run (headless)

```bash
docker run --rm -it \
  -e CODECOLLECTION_REPO="runwhen-contrib/rw-cli-codecollection" \
  -v "$HOME/.kube:/home/runwhen/auth/.kube:ro" \
  ghcr.io/runwhen-contrib/codecollection-devtools:latest \
  bash -c 'bash /home/runwhen/.devcontainer/on-create.sh && exec bash'
```

---

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CODECOLLECTION_REPO` | `runwhen-contrib/rw-cli-codecollection` | GitHub `org/repo` shorthand or full git URL of the codecollection to work on. |
| `CODECOLLECTION_BRANCH` | `main` | Branch to check out after cloning. |
| `PR_NUMBER` | *(none)* | If set, checks out the PR branch via `gh pr checkout`. Requires `GITHUB_TOKEN`. |
| `GITHUB_TOKEN` | *(injected by Codespaces)* | GitHub token for `gh` CLI auth. Codespaces provides this automatically. |
| `RW_MODE` | `dev` | Set to `dev` for local development behavior (handled by `rw-core-keywords`). |

---

## Running codebundles

Once the environment is bootstrapped, navigate to any codebundle and use the `ro` wrapper:

```bash
cd codecollection/codebundles/k8s-namespace-healthcheck
ro runbook.robot
```

`ro` wraps the `robot` command with:
- **Isolated working directories** — each run gets its own temp dir with copied cloud CLI configs (`.azure`, `.gcloud`, `.kube`)
- **Log output** — HTML reports written to `/robot_logs`, served at [localhost:3000](http://localhost:3000)
- **Selective test execution** — `ro --test "Check Health" runbook.robot`

```bash
ro                              # run all .robot files in current dir
ro runbook.robot                # run a specific file
ro --test "Check Health"        # run a specific test case
ro ../other-codebundle/         # run tests in a different directory
```

### Credentials

Mount or copy credentials into the `auth/` directory:

```
/home/runwhen/
├── auth/
│   ├── .kube/config        # kubectl
│   ├── .azure/             # Azure CLI
│   └── .gcloud/            # Google Cloud SDK
├── codecollection/
│   ├── codebundles/        # your codebundles
│   └── libraries/          # shared keyword libraries
└── ro                      # test runner
```

`ro` copies these configs into an isolated temp directory per run, so parallel executions don't interfere with each other.

---

## What's in the image

| Category | Tools |
|----------|-------|
| **Core** | Python 3.x, Robot Framework, `ro`, `rw-core-keywords`, `rw-cli-keywords` |
| **Kubernetes** | kubectl, Helm, istioctl, kubelogin |
| **Cloud CLIs** | AWS CLI v2, Azure CLI, Google Cloud SDK (gcloud, gsutil, bq) |
| **Infrastructure** | Terraform, go-task |
| **Dev tools** | git, gh (GitHub CLI), sudo, jq |

### Python packages

Base packages installed in the image (from `requirements.txt`):

- `rw-cli-keywords` (includes `rw-core-keywords` — handles `RW_MODE=dev` for local development)
- `jmespath`, `python-dateutil`, `thefuzz`, `jinja2`

Each codecollection's `requirements.txt` is installed at bootstrap time by `on-create.sh`.

---

## File structure

```
codecollection-devtools/
├── .devcontainer/
│   ├── devcontainer.json       # devcontainer config (pulls pre-built image)
│   └── on-create.sh            # bootstrap: clone repo, install deps, checkout PR
├── .github/
│   └── workflows/
│       ├── build-push.yaml     # CI: multi-arch build → GHCR + GCP Artifact Registry
│       └── pypi.yaml           # publish rw-devtools to PyPI (deprecated)
├── Dockerfile                  # image definition (built by CI, not locally)
├── ro                          # Robot Framework test runner wrapper
├── requirements.txt            # base Python dependencies
├── dev_facade/                 # DEPRECATED — use rw-core-keywords instead
└── README.md
```

---

## Architecture

### Build pipeline

All image builds happen in **GitHub Actions** — never locally:

1. **Pull requests** → build test only (no push)
2. **Push to main** (when `VERSION`, `Dockerfile`, `requirements.txt`, `.devcontainer/**`, or workflow files change) → multi-arch build (`linux/amd64` + `linux/arm64`) → push to GHCR and GCP Artifact Registry

### Image registries

| Registry | Image |
|----------|-------|
| **GHCR** | `ghcr.io/runwhen-contrib/codecollection-devtools:latest` |
| **GCP Artifact Registry** | `us-docker.pkg.dev/runwhen-nonprod-shared/public-images/codecollection-devtools:latest` |

### Bootstrap flow

```
devcontainer opens
  → pulls pre-built image from GHCR
  → runs on-create.sh:
      1. clones CODECOLLECTION_REPO into /home/runwhen/codecollection/
      2. checks out PR_NUMBER branch (if set)
      3. pip installs codecollection's requirements.txt
      4. verifies tools (ro, robot, kubectl, gh, python)
  → starts log HTTP server on port 3000
  → ready to develop
```

---

## For codecollection authors

Each codecollection repo does **not** need its own devcontainer config. Instead, point users at this repo:

```markdown
## Development

Use [codecollection-devtools](https://github.com/runwhen-contrib/codecollection-devtools)
to spin up a dev environment:

CODECOLLECTION_REPO=runwhen-contrib/your-codecollection

See the [devtools README](https://github.com/runwhen-contrib/codecollection-devtools#getting-started) for full instructions.
```

### Supported codecollections

Any codecollection that follows the standard layout works:

```
your-codecollection/
├── codebundles/
│   └── your-bundle/
│       ├── runbook.robot
│       └── sli.robot
├── libraries/
│   └── YourKeywords/
├── requirements.txt
└── README.md
```

---

## Contributing

We'd love to collaborate. Head to the [RunWhen author docs](https://docs.runwhen.com/public/v/runwhen-authors/codecollection-development/getting-started/running-your-first-codebundle) to get started with codebundle development.

---

## License

Apache-2.0
