#!/bin/bash
# ======================================================================================
# on-create.sh — Bootstrap a codecollection into the devtools environment
#
# Runs once when the devcontainer is created (onCreateCommand).
# Clones the target codecollection repo, installs its Python deps, and
# optionally checks out a PR branch for review.
#
# Environment variables (set via devcontainer.json or Codespaces secrets):
#
#   CODECOLLECTION_REPO     Git URL or GitHub shorthand (org/repo) of the
#                           codecollection to work on.
#                           Default: runwhen-contrib/rw-cli-codecollection
#
#   CODECOLLECTION_BRANCH   Branch to check out after clone.
#                           Default: main
#
#   PR_NUMBER               If set, fetch and check out the PR branch instead
#                           of CODECOLLECTION_BRANCH. Requires gh CLI auth.
#
#   GITHUB_TOKEN            Passed through for gh CLI auth (Codespaces injects
#                           this automatically).
# ======================================================================================
set -euo pipefail

RUNWHEN_HOME="/home/runwhen"
CODECOLLECTION_DIR="${RUNWHEN_HOME}/codecollection"
DEFAULT_REPO="runwhen-contrib/rw-cli-codecollection"

REPO="${CODECOLLECTION_REPO:-$DEFAULT_REPO}"
BRANCH="${CODECOLLECTION_BRANCH:-main}"

# Normalise shorthand "org/repo" → full HTTPS URL
if [[ "$REPO" != http* && "$REPO" != git@* ]]; then
    REPO="https://github.com/${REPO}.git"
fi

echo "=== CodeCollection DevTools Bootstrap ==="
echo "  Repo:   ${REPO}"
echo "  Branch: ${BRANCH}"
echo "  PR:     ${PR_NUMBER:-none}"
echo "=========================================="

# ------------------------------------------------------------------
# 1. Clone the codecollection
# ------------------------------------------------------------------
if [ -d "${CODECOLLECTION_DIR}/.git" ]; then
    echo "Codecollection already cloned at ${CODECOLLECTION_DIR}, pulling latest..."
    git -C "${CODECOLLECTION_DIR}" fetch --all --prune
else
    # Remove placeholder dir if the image created one
    rm -rf "${CODECOLLECTION_DIR}"
    echo "Cloning ${REPO} → ${CODECOLLECTION_DIR} ..."
    git clone --branch "${BRANCH}" "${REPO}" "${CODECOLLECTION_DIR}"
fi

# ------------------------------------------------------------------
# 2. Optionally check out a PR
# ------------------------------------------------------------------
if [ -n "${PR_NUMBER:-}" ]; then
    echo "Checking out PR #${PR_NUMBER}..."
    cd "${CODECOLLECTION_DIR}"
    if command -v gh &>/dev/null; then
        gh pr checkout "${PR_NUMBER}"
    else
        echo "gh CLI not found — falling back to git fetch"
        git fetch origin "pull/${PR_NUMBER}/head:pr-${PR_NUMBER}"
        git checkout "pr-${PR_NUMBER}"
    fi
    echo "On branch: $(git branch --show-current)"
fi

# ------------------------------------------------------------------
# 3. Install codecollection Python dependencies
# ------------------------------------------------------------------
if [ -f "${CODECOLLECTION_DIR}/requirements.txt" ]; then
    echo "Installing codecollection requirements..."
    pip install --user --no-cache-dir -r "${CODECOLLECTION_DIR}/requirements.txt"
fi

# ------------------------------------------------------------------
# 4. Install CodeBundle authoring skills as Cursor rules
# ------------------------------------------------------------------
DEVTOOLS_DIR="${RUNWHEN_HOME}/devtools"
SKILLS_SRC="${DEVTOOLS_DIR}/skills"
RULES_DIR="${CODECOLLECTION_DIR}/.cursor/rules"

if [ -d "${SKILLS_SRC}" ]; then
    mkdir -p "${RULES_DIR}"
    for skill in "${SKILLS_SRC}"/*.md; do
        [ -f "$skill" ] || continue
        base=$(basename "$skill" .md)
        cp "$skill" "${RULES_DIR}/${base}.mdc"
        echo "  Installed skill: ${base}"
    done
    if [ ! -f "${RULES_DIR}/.gitignore" ]; then
        printf '# Injected by codecollection-devtools -- do not commit\n*.mdc\n' > "${RULES_DIR}/.gitignore"
    fi
    echo "Skills installed to ${RULES_DIR}"
else
    echo "Skills directory not found at ${SKILLS_SRC}, skipping."
fi

# ------------------------------------------------------------------
# 5. Ensure auth directory exists for credential mounts
# ------------------------------------------------------------------
mkdir -p "${RUNWHEN_HOME}/auth"

# ------------------------------------------------------------------
# 6. Verify key tools are available
# ------------------------------------------------------------------
echo ""
echo "--- Environment ready ---"
echo "  ro:       $(command -v ro       && echo 'ok' || echo 'MISSING')"
echo "  robot:    $(command -v robot    && echo 'ok' || echo 'MISSING')"
echo "  kubectl:  $(command -v kubectl  && echo 'ok' || echo 'MISSING')"
echo "  gh:       $(command -v gh       && echo 'ok' || echo 'MISSING')"
echo "  python:   $(python --version 2>&1)"
echo ""
echo "Codecollection bootstrapped at ${CODECOLLECTION_DIR}"
echo "Run 'cd codecollection/codebundles/<name> && ro' to test a codebundle."
