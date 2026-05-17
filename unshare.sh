#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/_lib.sh"

ACL_ENTRY="$SANDBOX_ACL"
HOST_ACL_ENTRY="$HOST_ACL"

list_shared() {
  local found=false

  if [ -s "$STATE_FILE" ]; then
    awk -F '\t' '{print "  " $1 " -> " $2}' "$STATE_FILE"
    return
  fi

  while read -r link; do
    [ -n "$link" ] || continue
    printf '  %s -> %s\n' "$(basename "$link")" "$(readlink "$link")"
    found=true
  done < <(find "$SANDBOX_WORKSPACE" -maxdepth 1 -type l -print 2>/dev/null)

  if [ "$found" = false ]; then
    echo "  (none)"
  fi
}

if [ $# -eq 0 ]; then
  echo "Usage: ./unshare.sh <name>"
  echo ""
  echo "Removes a project from the sandbox workspace and revokes access."
  echo ""
  echo "Currently shared:"
  list_shared || true
  exit 0
fi

NAME="$1"
LINK="${SANDBOX_WORKSPACE}/${NAME}"

if [ -L "$LINK" ]; then
  SOURCE=$(readlink "$LINK")
elif [ -f "$STATE_FILE" ]; then
  SOURCE=$(awk -F '\t' -v name="$NAME" '$1 == name { print $2; found = 1; exit } END { exit !found }' "$STATE_FILE" 2>/dev/null || true)
else
  SOURCE=""
fi

if [ -z "$SOURCE" ]; then
  echo "✗ '${NAME}' is not shared"
  exit 1
fi

# Remove the symlink
if [ -L "$LINK" ]; then
  sudo rm "$LINK"
fi

# Revoke the ACLs added by share.sh.
if ! sudo chmod -R -a "$ACL_ENTRY" "$SOURCE" 2>/dev/null; then
  echo "⚠ Could not remove matching ACL from '${SOURCE}' (it may already be absent)."
fi
sudo chmod -R -a "$HOST_ACL_ENTRY" "$SOURCE" 2>/dev/null || true

if [ -f "$STATE_FILE" ]; then
  TMP_STATE=$(mktemp)
  awk -F '\t' -v name="$NAME" -v source="$SOURCE" 'BEGIN { OFS = FS } !($1 == name || $2 == source)' "$STATE_FILE" > "$TMP_STATE"
  sudo install -o "$SANDBOX_USER" -g "$SANDBOX_GROUP" -m 0644 "$TMP_STATE" "$STATE_FILE"
  rm -f "$TMP_STATE"
fi

safe_dir_remove_both "$SOURCE"

echo "✓ Unshared '${NAME}' (was -> ${SOURCE})"
