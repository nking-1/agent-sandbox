#!/usr/bin/env bash
set -euo pipefail

SANDBOX_USER="agent-sandbox"
SANDBOX_WORKSPACE="/Users/${SANDBOX_USER}/workspace"
STATE_FILE="/Users/${SANDBOX_USER}/.shared-projects"
ACL_ENTRY="${SANDBOX_USER} allow read,write,delete,add_file,add_subdirectory,file_inherit,directory_inherit"
HOST_USER="$(whoami)"
HOST_ACL_ENTRY="${HOST_USER} allow read,write,delete,add_file,add_subdirectory,file_inherit,directory_inherit"

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
  echo "Usage: ./share.sh <path-to-project> [name]"
  echo ""
  echo "Shares a project folder into the sandbox workspace."
  echo "The sandbox user gets full read/write access to the original files."
  echo ""
  echo "Examples:"
  echo "  ./share.sh /Users/Shared/code/algo-viz"
  echo "  ./share.sh /Users/Shared/code/algo-viz my-project   # custom name in sandbox"
  echo ""
  echo "Currently shared:"
  list_shared || true
  exit 0
fi

if [ ! -d "$1" ]; then
  echo "✗ '$1' is not a directory"
  exit 1
fi

SOURCE=$(cd "$1" && pwd -P)
NAME="${2:-$(basename "$SOURCE")}"
LINK="${SANDBOX_WORKSPACE}/${NAME}"

if [[ -z "$NAME" || "$NAME" == "." || "$NAME" == ".." || "$NAME" == *"/"* ]]; then
  echo "✗ Invalid share name '${NAME}'"
  exit 1
fi

HOST_HOME="${HOME%/}"
case "$SOURCE" in
  "$HOST_HOME"|"$HOST_HOME"/*)
    echo "✗ Refusing to share '${SOURCE}' because it is under '${HOST_HOME}'."
    echo "  The sandbox deny ACL blocks traversal through the host home directory."
    echo "  Move or copy the project under /Users/Shared/code, then share that path."
    exit 1
    ;;
  /etc|/etc/*|/private/etc|/private/etc/*|/var|/var/*|/private/var|/private/var/*)
    echo "✗ Refusing to share sensitive path '${SOURCE}'"
    exit 1
    ;;
esac

if [ -e "$LINK" ] || [ -L "$LINK" ]; then
  echo "✗ '${NAME}' already exists in sandbox workspace"
  exit 1
fi

if [ -f "$STATE_FILE" ] && awk -F '\t' -v name="$NAME" -v source="$SOURCE" '$1 == name || $2 == source { found = 1 } END { exit !found }' "$STATE_FILE"; then
  echo "✗ Already shared (state file contains this name or source). Run ./unshare.sh first."
  exit 1
fi

if ls -lde "$SOURCE" | grep -Fq "$ACL_ENTRY"; then
  echo "✗ Already shared (ACL exists on source). Run ./unshare.sh first."
  exit 1
fi

# Grant both users access so files created by either side stay editable.
sudo chmod -R +a "$ACL_ENTRY" "$SOURCE"
if ! ls -lde "$SOURCE" | grep -Fq "$HOST_ACL_ENTRY"; then
  sudo chmod -R +a "$HOST_ACL_ENTRY" "$SOURCE"
fi

# Create the symlink (owned by sandbox user)
sudo mkdir -p "$SANDBOX_WORKSPACE"
sudo -u "$SANDBOX_USER" ln -s "$SOURCE" "$LINK"
printf '%s\t%s\n' "$NAME" "$SOURCE" | sudo tee -a "$STATE_FILE" > /dev/null

echo "✓ Shared '${SOURCE}' -> ${LINK}"
echo "  The sandbox user can now read/write files in this project."
