# herdr-workspace

A container image that runs the [herdr](https://herdr.dev) server (a terminal
workspace manager for AI coding agents) together with
[Claude Code](https://code.claude.com), on a modern userland.

Image: `ghcr.io/ciberkids/herdr-workspace:latest` (linux/amd64), rebuilt on every push
and weekly.

## Why

herdr plugins ship prebuilt binaries and build steps that assume a recent glibc,
Rust and Neovim. Long-term-support server distributions (for example EL9 with glibc
2.34) cannot run them. This image gives herdr and its plugins a current userland
without touching the host.

## What is inside

- Base: Docker's official Claude Code sandbox image,
  [`docker/sandbox-templates:claude-code`](https://hub.docker.com/r/docker/sandbox-templates)
  (Ubuntu 26.04, glibc 2.43, user `agent` uid 1000, Claude Code, git, gh, node, go, uv).
- Neovim, a C toolchain and headers for plugins that compile Rust crates with C parts.
- Google Chrome stable from Google's signed apt repository. The build fails if the
  repository key is not Google's published Linux signing key.
- Rust via rustup (installer checked against its published SHA-256).
- herdr (installer checks the binary's SHA-256).

The container's command is `herdr server`, under `tini`.

## Update model

- **`/usr`** (apt packages: Neovim, Chrome, toolchain) changes with each image rebuild.
- **`/home/agent`** is meant to be a persistent volume. It is seeded from the image the
  first time the volume is created, then it is yours: Claude Code, herdr, rustup and
  herdr plugins update themselves there (`herdr update`, Claude's auto-updater).

## Running it (rootless podman)

```sh
podman run -d --name herdr-workspace --hostname herdr \
  --userns=keep-id:uid=1000,gid=1000 \
  -v herdr-workspace-home:/home/agent \
  -v "$HOME/projects:$HOME/projects:z" \
  -v "$HOME/herdr-ssh:/home/agent/.ssh:ro,Z" \
  --memory=4g \
  ghcr.io/ciberkids/herdr-workspace:latest

podman exec -it herdr-workspace herdr     # attach the herdr TUI
podman exec -it herdr-workspace claude    # or run Claude Code directly
```

- `keep-id` maps the container's `agent` user to your own uid, so files agents create
  in your projects stay yours.
- Mount only the SSH keys the agents need for git (for example GitHub/GitLab deploy or
  user keys plus a matching `config` and `known_hosts`), never a key that can log in to
  your own machines.
- No ports are published: attach with `podman exec`. Anything the plugins listen on
  (for example Chrome's DevTools port) stays inside the container's network namespace.

## Notes for herdr-web-browser

Point it at the image's Chrome instead of letting it download Chrome for Testing:

```toml
# ~/.config/herdr/plugins/config/herdr-web-browser/config.toml
chrome_path = "/usr/bin/google-chrome"
```

Its startup also downloads Chrome for Testing unless one is present. A symlink at
`~/.local/state/herdr/plugins/herdr-web-browser/chrome-for-testing/chrome-linux64/chrome`
pointing to `/usr/bin/google-chrome` stops that.
