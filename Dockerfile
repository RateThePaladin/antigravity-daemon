FROM ubuntu:24.04

# Install basic dependencies, gosu (for PUID/PGID), & developer toolchain
RUN apt-get update && apt-get install -y \
    curl wget bash git openssh-client ca-certificates gosu sudo \
    python3 python3-pip python3-venv \
    nodejs npm build-essential jq unzip tree && \
    curl -fsSL https://antigravity.google/cli/install.sh | bash && \
    mkdir -p /usr/local/bin && \
    mv /root/.local/bin/agy /usr/local/bin/agy || true

# Install Doppler CLI
RUN curl -Ls --tlsv1.2 --proto "=https" --retry 3 https://cli.doppler.com/install.sh | sh

# Setup dynamic entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Set default working directory for interactive sessions
WORKDIR /workspace

ENTRYPOINT ["/docker-entrypoint.sh"]
