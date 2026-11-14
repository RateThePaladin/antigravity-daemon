FROM ubuntu:24.04

# Fail any RUN step whose piped command (e.g. `curl | bash`) fails
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Node.js major version (installed from NodeSource's signed apt repo)
ARG NODE_MAJOR=24
# Primary fingerprint of NodeSource's repo signing key
ARG NODESOURCE_FINGERPRINT=6F71F525282841EEDAF851B42F59B5F99B1BE0B4

# Install basic dependencies, gosu (for PUID/PGID), & developer toolchain
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget bash git openssh-client ca-certificates gnupg gosu sudo procps \
    python3 python3-pip python3-venv \
    golang-go gh \
    build-essential jq unzip tree && \
    # Node.js: add NodeSource's repo explicitly and verify the signing key,
    # instead of piping their setup script into bash
    install -d -m 0755 /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o /tmp/nodesource.asc && \
    FPR="$(gpg --show-keys --with-colons /tmp/nodesource.asc | awk -F: '/^fpr:/ {print $10; exit}')" && \
    if [ "$FPR" != "$NODESOURCE_FINGERPRINT" ]; then \
      echo "ERROR: NodeSource key fingerprint mismatch (got $FPR)" >&2; exit 1; \
    fi && \
    gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg /tmp/nodesource.asc && \
    rm -f /tmp/nodesource.asc && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# Configure Go environment to persist modules and binaries in /config/go
ENV GOPATH=/config/go
ENV PATH="/config/go/bin:${PATH}"

# Install Antigravity CLI
# Cache is invalidated whenever .antigravity-version changes or AGY_VERSION build arg is provided.
# The upstream installer always fetches the *latest* release (it verifies a sha512 from the
# manifest but cannot pin a version), so when AGY_VERSION is set we fail the build if the
# installed binary does not match. This keeps published `vX.Y.Z` tags honest.
ARG AGY_VERSION
COPY .antigravity-version /tmp/.antigravity-version
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash && \
    mkdir -p /usr/local/bin && \
    mv /root/.local/bin/agy /usr/local/bin/agy && \
    rm -f /tmp/.antigravity-version && \
    if [ -n "${AGY_VERSION}" ]; then \
      INSTALLED="$(/usr/local/bin/agy --version 2>&1 || true)"; \
      if ! grep -qF "${AGY_VERSION}" <<< "${INSTALLED}"; then \
        echo "ERROR: expected Antigravity CLI ${AGY_VERSION}, installer provided: ${INSTALLED}" >&2; \
        exit 1; \
      fi; \
    fi

# Ship the example agent settings so they can be restored from the console
COPY examples/settings.json /usr/share/antigravity-daemon/settings.example.json

# Setup dynamic entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Set default working directory for interactive sessions
WORKDIR /workspace

HEALTHCHECK --interval=60s --timeout=5s --start-period=30s --retries=3 \
  CMD ["pgrep", "-x", "agy"]

ENTRYPOINT ["/docker-entrypoint.sh"]
