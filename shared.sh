#!/usr/bin/env bash
set -euo pipefail

SANDBOX_USER="agent-sandbox"
SANDBOX_WORKSPACE="/Users/${SANDBOX_USER}/workspace"
STATE_FILE="/Users/${SANDBOX_USER}/.shared-projects"

echo "Shared projects:"
echo ""

found=false
if [ -s "$STATE_FILE" ]; then
  while IFS=$'\t' read -r name source; do
    [ -n "$name" ] || continue
    echo "  ${name} -> ${source}"
    found=true
  done < "$STATE_FILE"
else
  for link in "$SANDBOX_WORKSPACE"/*; do
    if [ -L "$link" ]; then
      name=$(basename "$link")
      target=$(readlink "$link")
      echo "  ${name} -> ${target}"
      found=true
    fi
  done
fi

if [ "$found" = false ]; then
  echo "  (none)"
fi
