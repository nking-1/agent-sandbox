#!/usr/bin/env bash
set -euo pipefail

SANDBOX_USER="agent-sandbox"
SANDBOX_GROUP="agent-sandbox"
SANDBOX_HOME="/Users/${SANDBOX_USER}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_AGENTS_FILE="${SANDBOX_HOME}/workspace/AGENTS.md"
REPO_AGENTS_FILE="${SCRIPT_DIR}/AGENT_META.md"
PREFERRED_GROUP_ID=550
WRITABLE_DIRS=(
  workspace
  .npm
  .npm-global
  .local
  .cache
  .config
  .zsh
  .ssh
  Library/Keychains
)

if [ "$(uname -s)" != "Darwin" ]; then
  echo "✗ setup.sh currently supports macOS only. Linux support is future work." >&2
  exit 1
fi

find_free_group_id() {
  local gid="$PREFERRED_GROUP_ID"

  while dscl . -list /Groups PrimaryGroupID | awk -v gid="$gid" '$2 == gid { found = 1 } END { exit !found }'; do
    gid=$((gid + 1))
    if [ "$gid" -ge 600 ]; then
      echo "✗ No available group ID found in 550-599" >&2
      exit 1
    fi
  done

  echo "$gid"
}

run_as_sandbox() {
  sudo -H -u "$SANDBOX_USER" env HOME="$SANDBOX_HOME" "$@"
}

if dscl . -read "/Groups/${SANDBOX_GROUP}" &>/dev/null; then
  SANDBOX_GID=$(dscl . -read "/Groups/${SANDBOX_GROUP}" PrimaryGroupID | awk '{print $2}')
  echo "✓ Group '$SANDBOX_GROUP' already exists (GID: ${SANDBOX_GID})"
else
  SANDBOX_GID=$(find_free_group_id)
  echo "Creating group '$SANDBOX_GROUP' (GID: ${SANDBOX_GID})..."
  sudo dseditgroup -o create -i "$SANDBOX_GID" "$SANDBOX_GROUP"
  echo "✓ Group '$SANDBOX_GROUP' created"
fi

if id "$SANDBOX_USER" &>/dev/null; then
  echo "✓ User '$SANDBOX_USER' already exists"
  sudo dscl . -create "/Users/${SANDBOX_USER}" PrimaryGroupID "$SANDBOX_GID"
  sudo dscl . -create "/Users/${SANDBOX_USER}" IsHidden 1
else
  echo "Creating macOS user '$SANDBOX_USER'..."

  # Find an available service-user UniqueID without considering high system IDs.
  LAST_ID=$(dscl . -list /Users UniqueID | awk '$2 >= 500 && $2 < 1000 {print $2}' | sort -n | tail -1)
  NEW_ID=$((${LAST_ID:-549} + 1))
  if [ "$NEW_ID" -ge 1000 ]; then
    echo "✗ No available user ID found in 550-999" >&2
    exit 1
  fi

  sudo dscl . -create "/Users/${SANDBOX_USER}"
  sudo dscl . -create "/Users/${SANDBOX_USER}" UserShell /bin/zsh
  sudo dscl . -create "/Users/${SANDBOX_USER}" RealName "Agent Sandbox"
  sudo dscl . -create "/Users/${SANDBOX_USER}" UniqueID "$NEW_ID"
  sudo dscl . -create "/Users/${SANDBOX_USER}" PrimaryGroupID "$SANDBOX_GID"
  sudo dscl . -create "/Users/${SANDBOX_USER}" NFSHomeDirectory "$SANDBOX_HOME"
  sudo dscl . -create "/Users/${SANDBOX_USER}" IsHidden 1

  # Disable password-based login entirely — we use sudo -u, not su
  # This avoids local password policy issues.
  sudo dscl . -create "/Users/${SANDBOX_USER}" AuthenticationAuthority ";DisabledUser;"

  # Create and own the home directory
  sudo mkdir -p "$SANDBOX_HOME"
  sudo chown "$SANDBOX_USER":"$SANDBOX_GROUP" "$SANDBOX_HOME"

  # Verify
  if id "$SANDBOX_USER" &>/dev/null; then
    echo "✓ User '$SANDBOX_USER' created (UID: $NEW_ID)"
  else
    echo "✗ Failed to create user '$SANDBOX_USER'"
    exit 1
  fi
fi

# Ensure workspace directory exists
sudo mkdir -p "${SANDBOX_HOME}/workspace"
sudo chown "$SANDBOX_USER":"$SANDBOX_GROUP" "${SANDBOX_HOME}/workspace"
echo "✓ Workspace ready at ${SANDBOX_HOME}/workspace"

if [ -f "$REPO_AGENTS_FILE" ]; then
  sudo install -o "$SANDBOX_USER" -g "$SANDBOX_GROUP" -m 0644 "$REPO_AGENTS_FILE" "$WORKSPACE_AGENTS_FILE"
  echo "✓ Agent guide installed at ${WORKSPACE_AGENTS_FILE}"
fi

# Create standard dotfile dirs the sandbox user can write to
# (needed for npm, pip/uv, node, etc.)
for dir in "${WRITABLE_DIRS[@]}"; do
  sudo mkdir -p "${SANDBOX_HOME}/${dir}"
  sudo chown -R "$SANDBOX_USER":"$SANDBOX_GROUP" "${SANDBOX_HOME}/${dir}"
done
sudo touch "${SANDBOX_HOME}/.shared-projects"
sudo chown "$SANDBOX_USER":"$SANDBOX_GROUP" "$SANDBOX_HOME" "${SANDBOX_HOME}/.shared-projects"
sudo chmod 644 "${SANDBOX_HOME}/.shared-projects"
echo "✓ Dotfile directories created"

# Create a login keychain for tools that store credentials in the user keychain.
KEYCHAIN="${SANDBOX_HOME}/Library/Keychains/login.keychain-db"
KEYCHAIN_LEGACY="${SANDBOX_HOME}/Library/Keychains/login.keychain"
if [ -f "$KEYCHAIN" ] && run_as_sandbox security unlock-keychain -p "" "$KEYCHAIN" >/dev/null 2>&1; then
  run_as_sandbox security default-keychain -s "$KEYCHAIN"
  echo "✓ Keychain already exists"
else
  sudo rm -f "$KEYCHAIN" "$KEYCHAIN_LEGACY"
  run_as_sandbox security create-keychain -p "" "$KEYCHAIN"
  run_as_sandbox security default-keychain -s "$KEYCHAIN"
  echo "✓ Keychain created"
fi

# Set up a default .zshrc for fresh installs. Do not overwrite it on reruns:
# installers like nvm may append their own initialization.
if [ ! -f "${SANDBOX_HOME}/.zshrc" ]; then
  sudo tee "${SANDBOX_HOME}/.zshrc" > /dev/null << 'ZSHRC'
# Sandbox user shell config
export HOME="/Users/agent-sandbox"
export TERM=xterm-256color
bindkey -e
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

brew() {
  echo "Homebrew is read-only in the sandbox. Install Homebrew packages from the host user."
  return 1
}

export UV_CACHE_DIR="${HOME}/.cache/uv"
export PIP_USER=1
export PYTHONUSERBASE="${HOME}/.local"
unset NPM_CONFIG_PREFIX

export HISTFILE="${HOME}/.zsh/history"

cd ~/workspace 2>/dev/null || true
ZSHRC
  echo "✓ Shell config created"
else
  echo "✓ Shell config already exists (left unchanged)"
fi
sudo chown "$SANDBOX_USER":"$SANDBOX_GROUP" "${SANDBOX_HOME}/.zshrc"
sudo mkdir -p "${SANDBOX_HOME}/.npm-global"
sudo chown "$SANDBOX_USER":"$SANDBOX_GROUP" "${SANDBOX_HOME}/.npm-global"

# Keep the sandbox home writable so standard user-local installers work.
sudo chmod 755 "$SANDBOX_HOME"
echo "✓ Home directory writable by sandbox user"

# Block access to the host user's home directory
CURRENT_USER=$(whoami)
CURRENT_HOME="/Users/${CURRENT_USER}"

# Create a custom ACL denying the sandbox user access to your home
# (belt-and-suspenders on top of Unix permissions)
DENY_ACL="${SANDBOX_USER} deny list,search,readattr,readextattr,readsecurity"
if ls -lde "$CURRENT_HOME" | grep -Fq "$DENY_ACL"; then
  echo "✓ Sandbox user already blocked from ${CURRENT_HOME}"
else
  sudo chmod +a "$DENY_ACL" "$CURRENT_HOME"
  echo "✓ Blocked sandbox user from ${CURRENT_HOME}"
fi

# Allow current user to sudo into sandbox user without a password
# NOTE: the sandbox user itself gets NO sudo access
SUDOERS_FILE="/etc/sudoers.d/agent-sandbox"
SUDOERS_LINE="${CURRENT_USER} ALL=(${SANDBOX_USER}) NOPASSWD: ALL"

if [ -f "$SUDOERS_FILE" ] && grep -qF "$SUDOERS_LINE" "$SUDOERS_FILE" 2>/dev/null; then
  echo "✓ Sudoers rule already configured"
else
  echo "Configuring passwordless su to '$SANDBOX_USER'..."
  echo "$SUDOERS_LINE" | sudo tee "$SUDOERS_FILE" > /dev/null
  sudo chmod 0440 "$SUDOERS_FILE"
  echo "✓ Sudoers rule added"
fi

echo ""
echo "Setup complete! Use ./activate.sh to drop into the sandbox shell."
