#!/usr/bin/env bash
# Shared helpers for agent-sandbox scripts. Not meant to be executed directly.
# Source from a sibling script:
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   . "${SCRIPT_DIR}/_lib.sh"

SANDBOX_USER="${SANDBOX_USER:-agent-sandbox}"
SANDBOX_GROUP="${SANDBOX_GROUP:-agent-sandbox}"
SANDBOX_HOME="${SANDBOX_HOME:-/Users/${SANDBOX_USER}}"
SANDBOX_WORKSPACE="${SANDBOX_WORKSPACE:-${SANDBOX_HOME}/workspace}"
STATE_FILE="${STATE_FILE:-${SANDBOX_HOME}/.shared-projects}"
SHARED_CODE_ROOT="${SHARED_CODE_ROOT:-/Users/Shared/code}"
HOST_USER="${HOST_USER:-$(whoami)}"
HOST_HOME_DIR="${HOME%/}"
SANDBOX_ACL="${SANDBOX_USER} allow read,write,delete,add_file,add_subdirectory,file_inherit,directory_inherit"
HOST_ACL="${HOST_USER} allow read,write,delete,add_file,add_subdirectory,file_inherit,directory_inherit"

# Reject names that would break the tab-delimited state file, escape the
# shared-code root, or otherwise confuse path handling.
validate_name() {
  local name="$1"
  if [[ -z "$name" || "$name" == "." || "$name" == ".." || "$name" == *"/"* ]]; then
    return 1
  fi
  if printf '%s' "$name" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    return 1
  fi
  return 0
}

# Run git under a specific user account so --global writes to that user's
# ~/.gitconfig. Exits non-zero if git is not on PATH.
git_as_user() {
  local user="$1"
  local home="$2"
  shift 2
  local git_bin
  if ! git_bin=$(command -v git 2>/dev/null); then
    return 127
  fi
  if [ "$user" = "$HOST_USER" ]; then
    "$git_bin" "$@"
  else
    sudo -H -u "$user" env HOME="$home" "$git_bin" "$@"
  fi
}

# Add an exact-match safe.directory entry to a user's global gitconfig.
# Idempotent: silently skips if the entry already exists.
safe_dir_add() {
  local user="$1"
  local home="$2"
  local path="$3"
  command -v git >/dev/null 2>&1 || return 0
  if git_as_user "$user" "$home" config --global --get-all safe.directory 2>/dev/null \
       | grep -Fxq "$path"; then
    return 0
  fi
  git_as_user "$user" "$home" config --global --add safe.directory "$path" || true
}

# Remove an exact-match safe.directory entry from a user's global gitconfig.
# Uses --fixed-value (Git 2.30+) to avoid regex escaping pitfalls in paths.
safe_dir_remove() {
  local user="$1"
  local home="$2"
  local path="$3"
  command -v git >/dev/null 2>&1 || return 0
  git_as_user "$user" "$home" config --global --fixed-value --unset-all safe.directory "$path" 2>/dev/null || true
}

safe_dir_add_both() {
  local path="$1"
  safe_dir_add "$HOST_USER" "$HOST_HOME_DIR" "$path"
  safe_dir_add "$SANDBOX_USER" "$SANDBOX_HOME" "$path"
}

safe_dir_remove_both() {
  local path="$1"
  safe_dir_remove "$HOST_USER" "$HOST_HOME_DIR" "$path"
  safe_dir_remove "$SANDBOX_USER" "$SANDBOX_HOME" "$path"
}

# Replace (or add) a single ACL entry on a path. Mirrors setup.sh::set_acl.
set_acl() {
  local path="$1"
  local acl="$2"
  sudo chmod -a "$acl" "$path" 2>/dev/null || true
  sudo chmod +a "$acl" "$path"
}
