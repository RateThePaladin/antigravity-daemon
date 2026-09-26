#!/bin/bash
set -e

echo "Running Antigravity Daemon Test Suite"
echo "-----------------------------------"

IMAGE_NAME="antigravity-daemon:test"
# We use custom test IDs to ensure it isn't just defaulting to the current user by chance
TEST_PUID=1099
TEST_PGID=1099
TEST_DIR=$(mktemp -d)
CONFIG_DIR="$TEST_DIR/config"
WORKSPACE_DIR="$TEST_DIR/workspace"

mkdir -p "$CONFIG_DIR" "$WORKSPACE_DIR"

echo "[1/4] Building Docker image..."
docker build --no-cache -t $IMAGE_NAME . >/dev/null

echo "[2/4] Starting container with PUID=$TEST_PUID and PGID=$TEST_PGID..."
# Run detached with TTY enabled
CONTAINER_ID=$(docker run -dit \
    -e PUID=$TEST_PUID \
    -e PGID=$TEST_PGID \
    -e TERM=xterm -e COLUMNS=80 -e LINES=24 \
    -v "$CONFIG_DIR:/config" \
    -v "$WORKSPACE_DIR:/workspace" \
    $IMAGE_NAME)

# Give it a couple of seconds to initialize and create files
sleep 3

echo "[3/4] Verifying correct ownership and paths..."

# 1. Check if settings.json was created in the mapped /config folder
SETTINGS_PATH="$CONFIG_DIR/.gemini/antigravity-cli/settings.json"
if [ ! -f "$SETTINGS_PATH" ]; then
    echo "❌ ERROR: settings.json was not created in the /config directory."
    docker logs $CONTAINER_ID
    docker stop $CONTAINER_ID >/dev/null
    exit 1
fi

# 2. Check if the files are owned by the specified PUID/PGID inside the container
# We must check inside the container because Docker Desktop on macOS masks ownership on bind mounts.
FILE_OWNERSHIP=$(docker exec $CONTAINER_ID stat -c "%u:%g" "/config/.gemini/antigravity-cli/settings.json")

if [ "$FILE_OWNERSHIP" != "${TEST_PUID}:${TEST_PGID}" ]; then
    echo "❌ ERROR: File ownership is $FILE_OWNERSHIP, expected ${TEST_PUID}:${TEST_PGID}."
    echo "This means PUID/PGID privilege dropping is failing."
    docker stop $CONTAINER_ID >/dev/null
    exit 1
fi

# 3. Check if the daemon is still running
CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' $CONTAINER_ID)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "❌ ERROR: Container is not running (Status: $CONTAINER_STATUS)"
    docker logs $CONTAINER_ID
    docker stop $CONTAINER_ID >/dev/null 2>&1 || true
    docker rm -f $CONTAINER_ID >/dev/null 2>&1 || true
    rm -rf "$TEST_DIR"
    exit 1
fi

echo "[4/4] Cleaning up..."
docker stop $CONTAINER_ID >/dev/null 2>&1 || true
docker rm -f $CONTAINER_ID >/dev/null 2>&1 || true
rm -rf "$TEST_DIR"

echo "✅ All tests passed! The daemon is successfully respecting PUID/PGID and /config mounts."
