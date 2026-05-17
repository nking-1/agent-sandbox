# Agent Sandbox Guide

You are running inside the `agent-sandbox` macOS user profile. Treat this like a
shared lab machine account: it is intentionally separate from the admin user's
private home directory, credentials, and personal tool state.

Your working directory starts at `/Users/agent-sandbox/workspace`. Shared
projects appear here, usually as links to directories under `/Users/Shared/code`.
You may freely inspect, edit, install project dependencies, run tests, build
artifacts, and make local commits within shared projects unless a project-specific
instruction says otherwise.

Project files should live under `/Users/Shared/code`, not directly in bare
`/Users/Shared`. The bare shared directory is a macOS public drop area and may
prevent you from renaming or deleting files owned by another user, even when you
can read them.

Some operations may be intentionally unavailable:

- You do not have sudo or admin privileges.
- You may not be able to read the admin user's home directory.
- You may not have access to the admin user's SSH keys, Git credentials,
  keychains, or private config files.
- **Remote Git operations are the admin's responsibility.** Use local Git
  freely (`status`, `add`, `commit`, `branch`, `checkout`, `merge`, `diff`,
  `log`, `stash`, local `tag`). Do not run `fetch`, `pull`, `push`, `clone`
  of credentialed repos, `git remote add`/`set-url`, or anything else that
  needs network credentials. When you need a remote operation, finish your
  local commits on a branch and surface a clear request to the admin
  (which repo, which branch, what to push or pull). This keeps the blast
  radius of the sandbox limited to local history.
- System-wide package installation may be blocked; install user-local tools in
  your own home directory when possible.

Your top priority is to run uninterrupted and avoid bothering the admin. Prefer
self-service fixes inside your own profile: use user-local package managers,
project-local dependencies, caches under your home directory, and local commits.

Surface a request only when you are truly blocked and cannot safely continue, or
when the block appears unintentional. Be clear about what failed, what path or
permission was involved, and what admin action would unblock you.

Report any security hole you find, especially if you can access the admin user's
private files, credentials, keychains, SSH keys, or other data that should be
outside the sandbox boundary.
