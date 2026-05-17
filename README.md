# Agent Sandbox Workspace

This workspace runs under a sandboxed macOS user (`agent-sandbox`) to isolate
agent tools from the host user's files and credentials.

The model is the classic shared machine sysadmin model: the host user acts like the admin who owns
private files and installs system-wide tools, while `agent-sandbox` is a
non-admin user with its own writable home directory. Shared project work happens
in `/Users/Shared/code`, where both users are granted access.

Current support is **macOS**. The setup script intentionally uses macOS-specific
account, ACL, and keychain behavior. Defaults include Apple Silicon Homebrew
paths under `/opt/homebrew`; Linux support is a future portability task.

## Quick start

From the host user's shell:

```bash
./setup.sh
./activate.sh
```

`setup.sh` creates the sandbox user and host-home boundary. `activate.sh` opens
an interactive shell as `agent-sandbox`; type `exit` to return to the host user.

## How it works

- **Sandbox user:** `agent-sandbox` — a separate hidden macOS user with no
  password (login disabled). Access is via `sudo -u agent-sandbox` from the
  host user.
- **Dedicated group:** `agent-sandbox` — avoids placing the sandbox in
  `staff`, so group-readable host files are not exposed just because they use
  macOS defaults.
- **Home directory:** `/Users/agent-sandbox` is owned by and writable by the
  sandbox user. This keeps standard user-local installers working while the
  host user's home remains blocked.
- **Preconfigured writable locations:** Setup creates common tool directories:
  - `~/workspace` — project files go here
  - `~/.local` — uv, pip user installs
  - `~/.npm`, `~/.npm-global` — npm packages
  - `~/.cache` — uv/pip/npm caches
  - `~/.config` — tool configs
  - `~/.zsh` — shell history
  - `~/.ssh` — SSH config and keys you intentionally add to the sandbox
  - `~/Library/Keychains` — login keychain storage for tools that use Keychain
- **Host user's files:** Blocked via macOS ACL. The sandbox user cannot read,
  list, or traverse `/Users/<host-user>`.
- **No sudo:** The sandbox user has no sudo access. Only the host user can
  escalate.
- **Activation:** `activate.sh` allocates an interactive PTY with `script` and
  `sudo -u`; it does not require SSH or an enabled `sshd`.
- **Agent guide:** `setup.sh` copies this repository's `AGENT_META.md` to
  `/Users/agent-sandbox/workspace/AGENTS.md` so agents see the sandbox operating
  policy when they start in the workspace.
- **System tools:** `/opt/homebrew/bin` and `/opt/homebrew/sbin` are on PATH by
  default so the sandbox can run host-installed binaries. The `brew` command is
  shadowed with a message because system-wide package installs must happen from
  the host user.

## Project sharing

Put projects you want to work on with the sandboxed agent under
`/Users/Shared/code`. `setup.sh` creates this shared project root and grants
inherited ACL access to both the host user and `agent-sandbox`. Projects stay in
that shared location; `share.sh` grants ACL access to the real directory and
creates a symlink to it in `/Users/agent-sandbox/workspace`.

From the host user's shell:

```bash
cd /path/to/agent-sandbox
./share.sh /Users/Shared/code/my-project
./unshare.sh my-project           # revoke access
./shared.sh                       # list shared projects
./claim.sh /Users/Shared/code/my-project   # take ownership back to host
./rename.sh my-project new-name            # rename a shared project
```

Shared projects appear as symlinks in `~/workspace/` and are read-write on the
original files. `share.sh` records shared paths in
`/Users/agent-sandbox/.shared-projects`, refuses paths under the host home
directory and system paths such as `/etc` and `/var`, and grants inherited ACLs
to both the sandbox user and the host user so files created by either account
stay editable by both. It also registers each shared path as a
`git safe.directory` entry in both users' global gitconfigs so Git does not
report "dubious ownership" regardless of which user created a given file.

## Git workflow split

The sandbox agent is constrained to **local** Git operations: `status`, `add`,
`commit`, `branch`, `merge`, `diff`, `log`, `stash`, and similar commands that
do not require network credentials. Remote operations (`fetch`, `pull`,
`push`, `clone` of credentialed repos, `git remote add`/`set-url`) are the
host user's responsibility. This keeps the sandbox's blast radius local: the
agent cannot publish anything to a forge on your behalf even if a remote is
configured.

When the agent finishes a unit of work, it will surface a request describing
which branch to push or pull. From the host user's shell:

```bash
cd /Users/Shared/code/my-project
git remote add origin git@github.com:you/my-project.git   # if needed
git push -u origin main
```

If the sandbox created the project from scratch, the files will be owned by
`agent-sandbox`. The host user can still read and operate on the repo because
of the inherited ACL and the `safe.directory` entry. If you would rather
have host ownership before publishing (e.g., so newly created files inherit
your defaults), run `./claim.sh` first:

```bash
./claim.sh /Users/Shared/code/my-project
```

`claim.sh` flips ownership to `${HOST_USER}:staff`, reapplies the sandbox and
host ACLs recursively, and confirms the `safe.directory` entry for both users
so the sandbox can keep making local commits afterward.

## Renaming a shared project

```bash
./rename.sh old-name new-name
```

`rename.sh` renames the directory under `/Users/Shared/code` (when the share
name and directory basename match), updates the workspace symlink and the
shared-projects state file, and rewrites the `safe.directory` entries for
both users. After the rename it greps the project for references to the old
absolute path and lists any files that still mention it so you can update
config files like `.mcp.json` manually. Close any sandbox shells in the
project before renaming so their cwd does not pin the old path.

If you need to repair or manually create the shared project root, use the same
policy as `setup.sh`:

```bash
sudo mkdir -p /Users/Shared/code
sudo chown "$USER":agent-sandbox /Users/Shared/code
sudo chmod 775 /Users/Shared/code
sudo chmod +a "agent-sandbox allow read,write,delete,add_file,add_subdirectory,file_inherit,directory_inherit" /Users/Shared/code
sudo chmod +a "$USER allow read,write,delete,add_file,add_subdirectory,file_inherit,directory_inherit" /Users/Shared/code
```

This avoids the traversal problem created by the deny ACL on
`/Users/<host-user>`. Projects under `/Users/<host-user>` are intentionally
rejected by `share.sh` because the sandbox user cannot traverse the parent
directories to reach the symlink target.

Avoid using bare `/Users/Shared` as a staging directory for project files. macOS
normally makes `/Users/Shared` a sticky-bit public directory, so the sandbox user
may be able to copy a host-owned file but not rename or remove the original. Copy
files directly into the relevant project directory under `/Users/Shared/code` so
the inherited ACLs apply.

To migrate an existing project from `~/code`:

```bash
mv ~/code/my-project /Users/Shared/code/
ln -s /Users/Shared/code/my-project ~/code/my-project
./share.sh /Users/Shared/code/my-project
```

From the host user's shell, verify that the sandbox user cannot read the host
home directory:

```bash
HOST_HOME="$HOME"
sudo -u agent-sandbox ls "$HOST_HOME"       # should fail
sudo -u agent-sandbox ls "$HOST_HOME/code"  # should fail
```

Inside the activated sandbox shell, the sandbox user's own home should be
available:

```bash
whoami           # agent-sandbox
echo "$HOME"     # /Users/agent-sandbox
ls "$HOME"       # should succeed
```

## Tooling

`setup.sh` prepares the sandbox account, shell defaults, writable tool
directories, and login keychain. It does not install language runtimes, package
managers, agent CLIs, or project-specific tools.

## Installing tools

Tool installation follows the same admin/user split:

- **Host/admin user:** install system-wide tools and runtimes, such as `git`,
  `node`, `python`, `uv`, `rg`, or `jq`, using whatever installer or package
  manager you prefer. The default sandbox shell includes `/opt/homebrew/bin` and
  `/opt/homebrew/sbin` on `PATH`, so Apple Silicon Homebrew installs are visible
  automatically.
- **Sandbox user:** install project dependencies and user-local tools that do
  not need admin access. For example, run `npm install` inside a project, use
  `uv`, or use `pip install --user`. These installs and caches stay under the
  sandbox home in locations such as `~/.local`, `~/.npm`, and `~/.cache`.

After installing a new system-wide tool from the host, restart the sandbox shell
with `./activate.sh` if the current shell does not pick it up. If your installer
uses a different binary directory, add that directory to the sandbox `.zshrc`.

`setup.sh` creates the default `/Users/agent-sandbox/.zshrc` only when it is
missing. Rerunning setup preserves existing shell customizations, including
installer-added blocks from tools like `nvm`.

## Installing tools that create dotfiles

The sandbox home is writable, so most tools can create their own dotfiles and
state directories. If a tool still hits a permission error, it is usually trying
to write outside `/Users/agent-sandbox` or into a path with unexpected
ownership.

### 1. Identify the blocked path

Look for errors like:
```
Permission denied: /Users/agent-sandbox/.some-new-dir
```

### 2. Fix ownership if needed

From the host user's shell (not the sandbox):
```bash
sudo mkdir -p /Users/agent-sandbox/.some-new-dir
sudo chown agent-sandbox:agent-sandbox /Users/agent-sandbox/.some-new-dir
```

### 3. Update setup.sh for known tool state

If this directory is expected for a common tool, add it to the `WRITABLE_DIRS`
array in `setup.sh` so fresh setups create it consistently.

### 4. Retry

Re-run the failed command from the sandbox shell.

## Scripts (on the host user's machine)

All in this repository:

| Script | Purpose |
|---|---|
| `setup.sh` | One-time setup: creates sandbox user and host-home boundary |
| `activate.sh` | Drop into the sandbox shell (like entering a container) |
| `share.sh` | Share a project folder into the sandbox workspace |
| `unshare.sh` | Revoke access to a shared project |
| `shared.sh` | List currently shared projects |
| `claim.sh` | Transfer ownership of a shared project to the host user (preserves sandbox ACL) |
| `rename.sh` | Rename a shared project (directory, symlink, state file, safe.directory) |
| `dump_shared.sh` | Backward-compatible alias for `shared.sh` |
| `teardown.sh` | Remove the sandbox user, group, home, sudoers entry, and host ACL |
| `_lib.sh` | Internal helpers sourced by the other scripts (do not run directly) |
