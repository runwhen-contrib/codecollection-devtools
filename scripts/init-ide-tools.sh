#!/bin/bash
# ==============================================================================
# init-ide-tools.sh — Initialize IDE / AI agent config directories at runtime
# ==============================================================================
#
# Reads the RW_IDE_TOOLS env var (comma-separated tool names) and creates a
# ~/.{toolname} directory for each entry with correct permissions.
#
# No rebuild needed — users add tools by setting ONE env var:
#
#   RW_IDE_TOOLS="claude,opencode,zed,cursor,windsurf"
#
# Each tool directory is created under $HOME (the runwhen user's home).
# Existing directories are left untouched.
#
# Default tools (when RW_IDE_TOOLS is unset): claude, opencode, zed
# ==============================================================================

set -euo pipefail

IDE_HOME="${HOME:-/home/runwhen}"
TOOLS="${RW_IDE_TOOLS:-claude,opencode,zed}"

echo "→ Initializing IDE tool config directories: ${TOOLS}"

IFS=',' read -ra TOOL_LIST <<< "${TOOLS}"
for tool in "${TOOL_LIST[@]}"; do
    # Trim whitespace
    tool=$(echo "${tool}" | xargs)
    [ -z "${tool}" ] && continue

    tool_dir="${IDE_HOME}/.${tool}"

    if [ -d "${tool_dir}" ]; then
        echo "  · ${tool_dir} (already exists)"
    else
        mkdir -p "${tool_dir}"
        chmod 775 "${tool_dir}"
        echo "  ✓ ${tool_dir}"
    fi
done

echo "→ IDE tool initialization complete."