#!/bin/bash
set -euo pipefail

# --- PUID / PGID -------------------------------------------------------------
PUID=${PUID:-99}
PGID=${PGID:-100}

is_true() { [[ "${1:-}" =~ ^([Tt][Rr][Uu][Ee]|1|[Yy][Ee][Ss])$ ]]; }

if ! [[ "$PUID" =~ ^[0-9]+$ && "$PGID" =~ ^[0-9]+$ ]]; then
  echo "ERROR: PUID and PGID must be numeric (got PUID='${PUID}', PGID='${PGID}')." >&2
  exit 1
fi
if [ "$PUID" -eq 0 ] && ! is_true "${AGY_ALLOW_ROOT:-false}"; then
  echo "ERROR: PUID=0 would run the agent as root. Set AGY_ALLOW_ROOT=true if you really want this." >&2
  exit 1
fi

if ! getent group "$PGID" >/dev/null; then
  groupadd -g "$PGID" agygroup 2>/dev/null || true
fi
if ! getent passwd "$PUID" >/dev/null; then
  useradd -u "$PUID" -g "$PGID" -d /config -M -s /bin/bash agyuser 2>/dev/null || true
fi

# Determine the actual username for the PUID to pass to gosu
AGY_USER=$(getent passwd "$PUID" | cut -d: -f1 || true)
if [ -z "$AGY_USER" ]; then
  AGY_USER="${PUID}:${PGID}"
fi

# --- Optional sudo (opt-in) --------------------------------------------------
# Passwordless root lets a prompt-injected agent tamper with the container's
# system files and create root-owned files on your shares, so it is OFF by
# default. Enable with AGY_ALLOW_SUDO=true if you want the agent to be able to
# apt-get install tools on the fly.
SUDOERS_FILE=/etc/sudoers.d/agy-user
rm -f "$SUDOERS_FILE"
# Clean up the per-username file written by older versions of this image
if [[ "$AGY_USER" =~ ^[A-Za-z0-9_-]+$ ]]; then
  rm -f "/etc/sudoers.d/${AGY_USER}"
fi
if is_true "${AGY_ALLOW_SUDO:-false}"; then
  echo "#${PUID} ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_FILE"
  chmod 0440 "$SUDOERS_FILE"
  if ! visudo -cf "$SUDOERS_FILE" >/dev/null; then
    echo "WARNING: generated sudoers entry is invalid; sudo stays disabled." >&2
    rm -f "$SUDOERS_FILE"
  fi
fi

# --- Directories & ownership -------------------------------------------------
mkdir -p /config/go/bin /workspace
chown -R "${PUID}:${PGID}" /config /workspace
# /config holds OAuth tokens: keep it private to the agent user
chmod 700 /config

# Set HOME and Go environment so agy and dev tools know where to look for configs
export HOME=/config
export GOPATH=/config/go
export PATH="/config/go/bin:${PATH}"

# Generate the CLI settings if they don't exist yet
mkdir -p /config/.gemini/antigravity-cli
SETTINGS_FILE="/config/.gemini/antigravity-cli/settings.json"
if [ ! -f "$SETTINGS_FILE" ]; then
  # Use a display name from `agy models`; unavailable models fall back with a warning
  echo '{"model": "Gemini 4 Argon (Medium)"}' > "$SETTINGS_FILE"
fi
chown -R "${PUID}:${PGID}" /config/.gemini

# --- Build CLI arguments -----------------------------------------------------
AGY_ARGS=(--remote-control)
if [ -n "${AGY_INSTANCE_NAME:-}" ]; then
  AGY_ARGS+=(--remote-control-name "$AGY_INSTANCE_NAME")
fi
AGY_ARGS+=(-c)

# --- Startup banner ----------------------------------------------------------
echo "-------------------------------------"
echo "      Antigravity Headless Daemon    "
echo "-------------------------------------"
echo "User UID:  ${PUID}"
echo "User GID:  ${PGID}"
echo "Sudo:      $([ -f "$SUDOERS_FILE" ] && echo enabled || echo disabled)"
echo "-------------------------------------"
echo ""
echo "📌 AUTHENTICATION CHECK:"
echo "If this is your first time starting the container, or if"
echo "the agent is failing to connect to your remote dashboard,"
echo "you must authenticate by opening the Unraid console and running:"
echo "   cd /workspace && gosu ${PUID}:${PGID} env HOME=/config agy"
echo "-------------------------------------"
echo ""

# Give the unprivileged user ownership of the TTY so the CLI can use it
if [ -t 0 ]; then
  chown "${PUID}:${PGID}" "$(tty)" 2>/dev/null || true
fi

# Run the CLI in the foreground, dropping privileges via gosu
cd /workspace || exit 1
exec gosu "$AGY_USER" /usr/local/bin/agy "${AGY_ARGS[@]}"
