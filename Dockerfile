FROM ubuntu:24.04

# Install basic dependencies, gosu (for PUID/PGID), & Antigravity CLI
RUN apt-get update && apt-get install -y curl bash git openssh-client ca-certificates gosu && \
    curl -fsSL https://antigravity.google/cli/install.sh | bash && \
    mkdir -p /usr/local/bin && \
    mv /root/.local/bin/agy /usr/local/bin/agy || true

# Install Doppler CLI
RUN curl -Ls --tlsv1.2 --proto "=https" --retry 3 https://cli.doppler.com/install.sh | sh

# Setup dynamic entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
