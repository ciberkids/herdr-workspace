# herdr-workspace: the herdr server (terminal workspace manager for AI coding agents)
# with Claude Code, on a modern userland.
#
# Base: Docker's official Claude Code sandbox image (Ubuntu 26.04, glibc 2.43, user
# `agent` uid 1000, Claude Code native install, git/gh/node/go/uv). A modern glibc
# is the point: herdr plugins ship prebuilt binaries that need glibc >= 2.38.
#
# Layout rule: everything that should change when the image is rebuilt lives in /usr
# (apt packages). /home/agent is a persistent volume, seeded from this image ONCE,
# so tools installed there (claude, herdr, rustup, plugins) update themselves.
FROM docker.io/docker/sandbox-templates:claude-code

LABEL org.opencontainers.image.source="https://github.com/ciberkids/herdr-workspace" \
      org.opencontainers.image.description="herdr server + Claude Code on Docker's Claude Code sandbox image (Ubuntu 26.04)"

USER root

# System packages: Neovim (herdr-nvim needs >= 0.10), a C toolchain and headers for
# plugins that build Rust crates with C parts (ring, libsqlite3-sys, zstd-sys, libgit2).
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        neovim build-essential pkg-config libssl-dev zlib1g-dev \
        less file procps psmisc openssh-client locales tzdata; \
    rm -rf /var/lib/apt/lists/*

# Google Chrome from Google's SIGNED apt repo (Ubuntu's chromium is a snap, which
# cannot run in a container). Used by herdr-web-browser via chrome_path, and it pulls
# in the GUI libraries any headless Chrome needs. The build fails unless the key file
# contains Google's published Linux package-signing key.
ARG GOOGLE_SIGNING_KEY_FPR=EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796
RUN set -eux; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub -o /tmp/google.pub; \
    gpg --show-keys --with-colons /tmp/google.pub | awk -F: '/^fpr/{print $10}' | grep -qx "$GOOGLE_SIGNING_KEY_FPR"; \
    gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg /tmp/google.pub; \
    rm /tmp/google.pub; \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
        > /etc/apt/sources.list.d/google-chrome.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends google-chrome-stable; \
    rm -rf /var/lib/apt/lists/*

USER agent
ENV HOME=/home/agent \
    PATH=/home/agent/.local/bin:/home/agent/.cargo/bin:/usr/local/share/npm-global/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    SHELL=/bin/bash \
    LANG=C.UTF-8
WORKDIR /home/agent

# Rust via rustup, verified against its published SHA-256, into the home volume:
# plugins pin their own toolchains (herdr-agent-usage wants 1.95.0) and rustup must be
# able to install them at plugin-install time.
RUN set -eux; \
    base=https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu; \
    curl -fsSL "$base/rustup-init" -o /tmp/rustup-init; \
    echo "$(curl -fsSL "$base/rustup-init.sha256" | awk '{print $1}')  /tmp/rustup-init" | sha256sum -c -; \
    chmod +x /tmp/rustup-init; \
    /tmp/rustup-init -y --no-modify-path --profile minimal --default-toolchain stable; \
    rm /tmp/rustup-init; \
    cargo --version

# herdr itself: its installer checks the binary's SHA-256 from herdr.dev/latest.json.
# Lands in ~/.local/bin (home volume) so `herdr update` keeps working.
RUN set -eux; \
    curl -fsSL https://herdr.dev/install.sh -o /tmp/herdr-install.sh; \
    sh /tmp/herdr-install.sh; \
    rm /tmp/herdr-install.sh; \
    herdr --version

# The container's job is the herdr server (foreground). Clients attach with
# `podman exec -it <container> herdr`. tini stays the entrypoint (from the base image).
CMD ["herdr", "server"]
