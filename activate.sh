#!/usr/bin/env bash
set -euo pipefail

SANDBOX_USER="agent-sandbox"
SANDBOX_HOME="/Users/${SANDBOX_USER}"

if ! id "$SANDBOX_USER" &>/dev/null; then
  echo "✗ Sandbox user '$SANDBOX_USER' not found. Run ./setup.sh first."
  exit 1
fi

echo "Dropping into ${SANDBOX_USER} shell..."
echo "  Home:      ${SANDBOX_HOME}"
echo "  Workspace: ${SANDBOX_HOME}/workspace"
echo "  Type 'exit' to return to your normal user."
echo ""

# Allocate a fresh PTY without requiring sshd or a localhost SSH key.
if command -v script >/dev/null; then
  exec script -q /dev/null sudo -u "$SANDBOX_USER" -i
fi

exec sudo -u "$SANDBOX_USER" -i
