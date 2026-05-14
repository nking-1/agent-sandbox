#!/usr/bin/env bash
set -euo pipefail

SANDBOX_USER="agent-sandbox"
SANDBOX_GROUP="agent-sandbox"
SANDBOX_HOME="/Users/${SANDBOX_USER}"
SUDOERS_FILE="/etc/sudoers.d/agent-sandbox"
CURRENT_HOME="/Users/$(whoami)"
DENY_ACL="${SANDBOX_USER} deny list,search,readattr,readextattr,readsecurity"

echo "This will remove:"
echo "  user:       ${SANDBOX_USER}"
echo "  group:      ${SANDBOX_GROUP}"
echo "  home:       ${SANDBOX_HOME}"
echo "  sudoers:    ${SUDOERS_FILE}"
echo "  host ACL:   ${DENY_ACL} on ${CURRENT_HOME}"
echo ""
read -r -p "Type 'delete agent-sandbox' to continue: " CONFIRM

if [ "$CONFIRM" != "delete agent-sandbox" ]; then
  echo "Aborted."
  exit 1
fi

if dscl . -read "/Users/${SANDBOX_USER}" &>/dev/null; then
  sudo dscl . -delete "/Users/${SANDBOX_USER}"
  echo "✓ Deleted user '${SANDBOX_USER}'"
else
  echo "✓ User '${SANDBOX_USER}' already absent"
fi

if dscl . -read "/Groups/${SANDBOX_GROUP}" &>/dev/null; then
  sudo dseditgroup -o delete "$SANDBOX_GROUP"
  echo "✓ Deleted group '${SANDBOX_GROUP}'"
else
  echo "✓ Group '${SANDBOX_GROUP}' already absent"
fi

if [ -d "$SANDBOX_HOME" ]; then
  sudo rm -rf "$SANDBOX_HOME"
  echo "✓ Removed ${SANDBOX_HOME}"
else
  echo "✓ ${SANDBOX_HOME} already absent"
fi

if [ -f "$SUDOERS_FILE" ]; then
  sudo rm "$SUDOERS_FILE"
  echo "✓ Removed ${SUDOERS_FILE}"
else
  echo "✓ ${SUDOERS_FILE} already absent"
fi

if ls -lde "$CURRENT_HOME" | grep -Fq "$DENY_ACL"; then
  sudo chmod -a "$DENY_ACL" "$CURRENT_HOME"
  echo "✓ Removed host-home deny ACL"
else
  echo "✓ Host-home deny ACL already absent"
fi

echo "Teardown complete."
