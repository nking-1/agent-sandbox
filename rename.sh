#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/_lib.sh"

if [ $# -lt 2 ]; then
  cat <<'USAGE'
Usage: ./rename.sh <old-share-name> <new-share-name>

Renames a shared project: updates the directory under /Users/Shared/code
(when the share name and directory basename match), the sandbox workspace
symlink, the shared-projects state file, and the git safe.directory
entries for both users.

After the rename, the script reports any references to the OLD absolute
path still present inside the project so you can update them manually
(e.g., .mcp.json, README.md, config files).

Close any sandbox shells in this project before running so their cwd and
open file descriptors do not pin the old path.

If the project was shared under a custom alias whose name differs from the
directory basename (./share.sh <path> <alias>), this script renames the
alias and symlink only and leaves the source directory in place.
USAGE
  exit 0
fi

OLD_NAME="$1"
NEW_NAME="$2"

for name in "$OLD_NAME" "$NEW_NAME"; do
  if ! validate_name "$name"; then
    echo "✗ Invalid name: '${name}'"
    exit 1
  fi
done

if [ "$OLD_NAME" = "$NEW_NAME" ]; then
  echo "✗ Old and new names are identical"
  exit 1
fi

OLD_SOURCE=""
if [ -f "$STATE_FILE" ]; then
  OLD_SOURCE=$(awk -F '\t' -v name="$OLD_NAME" '$1 == name { print $2; exit }' "$STATE_FILE")
fi

if [ -z "$OLD_SOURCE" ]; then
  echo "✗ '${OLD_NAME}' is not currently shared. Run ./shared.sh to list."
  exit 1
fi

if [ ! -d "$OLD_SOURCE" ]; then
  echo "✗ Source directory '${OLD_SOURCE}' does not exist"
  exit 1
fi

OLD_BASENAME=$(basename "$OLD_SOURCE")
PARENT_DIR=$(dirname "$OLD_SOURCE")

# If the share alias matches the directory basename, rename the directory.
# Otherwise rename only the share alias (keep the directory in place).
if [ "$OLD_BASENAME" = "$OLD_NAME" ]; then
  NEW_SOURCE="${PARENT_DIR}/${NEW_NAME}"
else
  NEW_SOURCE="$OLD_SOURCE"
  echo "Note: share alias differs from directory basename (${OLD_BASENAME})."
  echo "      Renaming alias and symlink only; directory location unchanged."
fi

OLD_LINK="${SANDBOX_WORKSPACE}/${OLD_NAME}"
NEW_LINK="${SANDBOX_WORKSPACE}/${NEW_NAME}"

if [ -e "$NEW_LINK" ] || [ -L "$NEW_LINK" ]; then
  echo "✗ Workspace entry '${NEW_LINK}' already exists"
  exit 1
fi

if [ "$NEW_SOURCE" != "$OLD_SOURCE" ]; then
  case "$OLD_SOURCE" in
    "$SHARED_CODE_ROOT"/*) ;;
    *)
      echo "✗ Refusing to rename '${OLD_SOURCE}': not under ${SHARED_CODE_ROOT}"
      exit 1
      ;;
  esac
  if [ -e "$NEW_SOURCE" ]; then
    echo "✗ Destination '${NEW_SOURCE}' already exists"
    exit 1
  fi
  sudo mv "$OLD_SOURCE" "$NEW_SOURCE"
  echo "✓ Renamed ${OLD_SOURCE} -> ${NEW_SOURCE}"
fi

if [ -L "$OLD_LINK" ]; then
  sudo rm "$OLD_LINK"
fi
sudo -u "$SANDBOX_USER" ln -s "$NEW_SOURCE" "$NEW_LINK"
echo "✓ Workspace symlink: ${NEW_LINK} -> ${NEW_SOURCE}"

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
if [ -f "$STATE_FILE" ]; then
  awk -F '\t' -v old="$OLD_NAME" -v new="$NEW_NAME" -v newsrc="$NEW_SOURCE" \
      'BEGIN { OFS = FS } { if ($1 == old) print new, newsrc; else print }' \
      "$STATE_FILE" > "$TMP"
fi
sudo install -o "$SANDBOX_USER" -g "$SANDBOX_GROUP" -m 0644 "$TMP" "$STATE_FILE"
echo "✓ Updated ${STATE_FILE}"

if [ "$NEW_SOURCE" != "$OLD_SOURCE" ]; then
  safe_dir_remove_both "$OLD_SOURCE"
  safe_dir_add_both "$NEW_SOURCE"
  echo "✓ Updated git safe.directory in host and sandbox gitconfigs"
fi

if [ "$NEW_SOURCE" != "$OLD_SOURCE" ] && [ -d "$NEW_SOURCE" ]; then
  echo ""
  echo "Searching ${NEW_SOURCE} for references to the old path..."
  REFS_FOUND=false
  if command -v rg >/dev/null 2>&1; then
    if rg -l --hidden --glob '!.git' -F "$OLD_SOURCE" "$NEW_SOURCE" 2>/dev/null; then
      REFS_FOUND=true
    fi
  else
    if grep -rlF --exclude-dir=.git "$OLD_SOURCE" "$NEW_SOURCE" 2>/dev/null; then
      REFS_FOUND=true
    fi
  fi
  if [ "$REFS_FOUND" = false ]; then
    echo "  (no references to '${OLD_SOURCE}' found)"
  else
    echo ""
    echo "Update the files listed above to refer to '${NEW_SOURCE}'."
  fi
fi
