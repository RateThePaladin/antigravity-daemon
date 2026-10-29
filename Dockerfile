FROM ubuntu:24.04

# Install basic dependencies, gosu (for PUID/PGID), & developer toolchain
RUN apt-get update && apt-get install -y \
    curl wget bash git openssh-client ca-certificates gosu sudo \
    python3 python3-pip python3-venv \
    golang-go gh \
    build-essential jq unzip tree && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Configure Go environment to persist modules and binaries in /config/go
ENV GOPATH=/config/go
ENV PATH="/config/go/bin:${PATH}"

# Install Antigravity CLI
# Cache is invalidated whenever .antigravity-version changes or AGY_VERSION build arg is provided
ARG AGY_VERSION
COPY .antigravity-version /tmp/.antigravity-version
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash && \
    mkdir -p /usr/local/bin && \
    mv /root/.local/bin/agy /usr/local/bin/agy && \
    rm -f /tmp/.antigravity-version

# Setup dynamic entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Set default working directory for interactive sessions
WORKDIR /workspace

ENTRYPOINT ["/docker-entrypoint.sh"]
