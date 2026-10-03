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

# Grant passwordless sudo to the unprivileged user so the agent can install tools
echo "${AGY_USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${AGY_USER}
chmod 0440 /etc/sudoers.d/${AGY_USER}

# Set ownership of mounted directories
mkdir -p /config /workspace
chown -R ${PUID}:${PGID} /config /workspace

# Set HOME so agy knows where to look for configs
export HOME=/config

# Generate the CLI settings if they don't exist yet
mkdir -p /config/.gemini/antigravity-cli
SETTINGS_FILE="/config/.gemini/antigravity-cli/settings.json"
if [ ! -f "$SETTINGS_FILE" ]; then
  echo '{"model": "Gemini 3.1 Pro (High)"}' > "$SETTINGS_FILE"
fi
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

# Print Unraid standard startup logs
echo "-------------------------------------"
echo "      Antigravity Headless Daemon    "
echo "-------------------------------------"
echo "User UID:  ${PUID}"
echo "User GID:  ${PGID}"
echo "-------------------------------------"
echo ""
echo "📌 AUTHENTICATION CHECK:"
echo "If this is your first time starting the container, or if"
echo "the agent is failing to connect to your remote dashboard,"
echo "you must authenticate by opening the Unraid console and running:"
echo "   cd /workspace && gosu ${PUID}:${PGID} env HOME=/config agy"
echo "-------------------------------------"
echo ""

# Fix TTY permissions for the unprivileged user
if [ -t 0 ]; then
  echo "TTY before chown: $(tty)"
  ls -l $(tty)
  chown ${PUID}:${PGID} $(tty) 2>/dev/null || true
  echo "TTY after chown:"
  ls -l $(tty)
fi

# Run the CLI in the foreground with remote control enabled, dropping privileges via gosu
cd /workspace
if [ -n "$AGY_INSTANCE_NAME" ]; then
  exec gosu $AGY_USER $EXEC_CMD --remote-control --remote-control-name "$AGY_INSTANCE_NAME" -c
else
  exec gosu $AGY_USER $EXEC_CMD --remote-control -c
fi
