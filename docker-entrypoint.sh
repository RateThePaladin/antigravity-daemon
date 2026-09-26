#!/bin/bash
# Setup PUID/PGID
PUID=${PUID:-99}
PGID=${PGID:-100}

if ! getent group ${PGID} >/dev/null; then
  groupadd -g ${PGID} agygroup 2>/dev/null || true
fi
if ! getent passwd ${PUID} >/dev/null; then
  useradd -u ${PUID} -g ${PGID} -d /config -M -s /bin/bash agyuser 2>/dev/null || true
fi

# Determine the actual username for the PUID to pass to gosu
AGY_USER=$(getent passwd ${PUID} | cut -d: -f1)
if [ -z "$AGY_USER" ]; then
  AGY_USER="${PUID}:${PGID}"
fi

# Set ownership of mounted directories
mkdir -p /config /workspace
chown -R ${PUID}:${PGID} /config /workspace

# Set HOME so agy knows where to look for configs
export HOME=/config

# Generate the CLI settings from Docker environment variables
mkdir -p /config/.gemini/antigravity-cli
cat <<EOF > /config/.gemini/antigravity-cli/settings.json
{
  "model": "${AGY_MODEL:-gemini-3.1-pro}"
}
EOF
chown -R ${PUID}:${PGID} /config/.gemini

# If a Doppler token is provided, wrap the agent execution to inject secrets
EXEC_CMD="/usr/local/bin/agy"
if [ -n "$DOPPLER_TOKEN" ]; then
  if doppler secrets >/dev/null 2>&1; then
    echo "Doppler token detected and validated. Injecting secrets..."
    EXEC_CMD="doppler run -- /usr/local/bin/agy"
  else
    echo "WARNING: Provided Doppler token is invalid! Proceeding without secret injection."
  fi
fi

# Fix TTY permissions for the unprivileged user
echo "TTY before chown: $(tty)" > /config/debug.log
ls -l $(tty) >> /config/debug.log 2>&1
if [ -t 0 ]; then
  chown ${PUID}:${PGID} $(tty) 2>>/config/debug.log || true
fi
ls -l $(tty) >> /config/debug.log 2>&1
echo "Finished TTY setup, executing gosu..." >> /config/debug.log

# Run the CLI in the foreground with remote control enabled, dropping privileges via gosu
if [ "${AGY_SKIP_PERMISSIONS:-false}" = "true" ]; then
  exec gosu $AGY_USER $EXEC_CMD --remote-control --dangerously-skip-permissions
else
  exec gosu $AGY_USER $EXEC_CMD --remote-control
fi
