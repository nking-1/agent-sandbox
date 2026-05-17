#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/_lib.sh"

FORCE=false
if [ $# -gt 0 ] && [ "$1" = "--force" ]; then
  FORCE=true
  shift
fi

if [ $# -eq 0 ]; then
  cat <<'USAGE'
Usage: ./claim.sh [--force] <path-to-project>

Transfers ownership of a shared project to the host user while preserving
ACL access for both the sandbox and host users. Use this when you want to
manage Git remotes, push, or otherwise act as the host user on files the
sandbox agent created.

After claiming:
  - Files are owned by the host user (group: staff).
  - The sandbox user retains read/write via ACL and can still make local
    commits and branches.
  - git safe.directory is set for both users so neither hits "dubious
    ownership" errors.

The project must be under /Users/Shared/code. Pass --force to claim a path
that is not currently tracked in the shared-projects state file.
USAGE
  exit 0
fi

if [ ! -d "$1" ]; then
  echo "✗ '$1' is not a directory"
  exit 1
fi

SOURCE=$(cd "$1" && pwd -P)

case "$SOURCE" in
  "$SHARED_CODE_ROOT")
    echo "✗ Refusing to claim '${SOURCE}': that is the shared root, not a project"
    exit 1
    ;;
  "$SHARED_CODE_ROOT"/*) ;;
  *)
    echo "✗ Refusing to claim '${SOURCE}': must be under ${SHARED_CODE_ROOT}"
    exit 1
    ;;
esac

TRACKED=false
if [ -f "$STATE_FILE" ] && awk -F '\t' -v source="$SOURCE" '$2 == source { found = 1 } END { exit !found }' "$STATE_FILE"; then
  TRACKED=true
fi

if [ "$TRACKED" = false ] && [ "$FORCE" = false ]; then
  echo "✗ '${SOURCE}' is not tracked in ${STATE_FILE}."
  echo "  Run ./share.sh first, or pass --force to claim anyway."
  exit 1
fi

echo "Claiming ${SOURCE} for ${HOST_USER}..."

sudo chown -R "${HOST_USER}:staff" "$SOURCE"
echo "✓ Ownership set to ${HOST_USER}:staff"

# Re-apply ACLs across the whole tree. macOS chown preserves existing ACLs,
# but we also want to repair any descendants that missed inheritance (e.g.,
# files moved in from elsewhere, or trees claimed before share.sh ran).
echo "Reapplying ACLs (may take a moment on large trees)..."
sudo chmod -R -a "$SANDBOX_ACL" "$SOURCE" 2>/dev/null || true
sudo chmod -R +a "$SANDBOX_ACL" "$SOURCE"
sudo chmod -R -a "$HOST_ACL" "$SOURCE" 2>/dev/null || true
sudo chmod -R +a "$HOST_ACL" "$SOURCE"
echo "✓ Sandbox and host ACLs reapplied recursively"

safe_dir_add_both "$SOURCE"
echo "✓ git safe.directory set for host and sandbox users"

echo ""
echo "Done. The host user can now run remote Git operations (add remote,"
echo "push, etc.) and the sandbox agent can still make local commits."
