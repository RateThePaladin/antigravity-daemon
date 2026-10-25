#!/bin/bash
set -e

echo "Running Antigravity Daemon Test Suite"
echo "-----------------------------------"

IMAGE_NAME="antigravity-daemon:test"
# We use custom test IDs to ensure it isn't just defaulting to the current user by chance
TEST_PUID=1099
TEST_PGID=1099
CONFIG_VOL="agy_test_config_$(date +%s)_$RANDOM"
WORKSPACE_VOL="agy_test_workspace_$(date +%s)_$RANDOM"

docker volume create "$CONFIG_VOL" >/dev/null
docker volume create "$WORKSPACE_VOL" >/dev/null

echo "[1/4] Building Docker image..."
docker build -t $IMAGE_NAME . >/dev/null

echo "[2/4] Starting container with PUID=$TEST_PUID and PGID=$TEST_PGID..."
# Run detached with TTY enabled
CONTAINER_ID=$(docker run -dit \
    -e PUID=$TEST_PUID \
    -e PGID=$TEST_PGID \
    -e TERM=xterm -e COLUMNS=80 -e LINES=24 \
    -v "$CONFIG_VOL:/config" \
    -v "$WORKSPACE_VOL:/workspace" \
    $IMAGE_NAME)

# Give it a couple of seconds to initialize and create files
sleep 3

echo "[3/4] Verifying correct ownership and paths..."

# 1. Check if settings.json was created in the mapped /config folder
SETTINGS_CHECK=$(docker exec $CONTAINER_ID test -f "/config/.gemini/antigravity-cli/settings.json" && echo "exists" || echo "missing")
if [ "$SETTINGS_CHECK" != "exists" ]; then
    echo "❌ ERROR: settings.json was not created in the /config directory."
    docker logs $CONTAINER_ID
    docker stop $CONTAINER_ID >/dev/null 2>&1 || true
    docker rm -f $CONTAINER_ID >/dev/null 2>&1 || true
    docker volume rm -f "$CONFIG_VOL" "$WORKSPACE_VOL" >/dev/null 2>&1 || true
    exit 1
fi

# 2. Check if the files are owned by the specified PUID/PGID inside the container
FILE_OWNERSHIP=$(docker exec $CONTAINER_ID stat -c "%u:%g" "/config/.gemini/antigravity-cli/settings.json")

if [ "$FILE_OWNERSHIP" != "${TEST_PUID}:${TEST_PGID}" ]; then
    echo "❌ ERROR: File ownership is $FILE_OWNERSHIP, expected ${TEST_PUID}:${TEST_PGID}."
    echo "This means PUID/PGID privilege dropping is failing."
    docker stop $CONTAINER_ID >/dev/null 2>&1 || true
    docker rm -f $CONTAINER_ID >/dev/null 2>&1 || true
    docker volume rm -f "$CONFIG_VOL" "$WORKSPACE_VOL" >/dev/null 2>&1 || true
    exit 1
fi

# 3. Check if the daemon is still running
CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' $CONTAINER_ID)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "❌ ERROR: Container is not running (Status: $CONTAINER_STATUS)"
    docker logs $CONTAINER_ID
    docker stop $CONTAINER_ID >/dev/null 2>&1 || true
    docker rm -f $CONTAINER_ID >/dev/null 2>&1 || true
    docker volume rm -f "$CONFIG_VOL" "$WORKSPACE_VOL" >/dev/null 2>&1 || true
    exit 1
fi

# 4. Check that developer tools (Go, Python, Node) are functional under the unprivileged user
echo "Verifying developer tools..."
docker exec $CONTAINER_ID gosu ${TEST_PUID}:${TEST_PGID} go version
docker exec $CONTAINER_ID gosu ${TEST_PUID}:${TEST_PGID} python3 --version
docker exec $CONTAINER_ID gosu ${TEST_PUID}:${TEST_PGID} node --version
docker exec $CONTAINER_ID gosu ${TEST_PUID}:${TEST_PGID} bash -c "printf 'package main\nimport \"fmt\"\nfunc main() { fmt.Println(\"Go execution verified\") }\n' > /workspace/test.go && go run /workspace/test.go && rm /workspace/test.go"

echo "[4/4] Cleaning up..."
docker stop $CONTAINER_ID >/dev/null 2>&1 || true
docker rm -f $CONTAINER_ID >/dev/null 2>&1 || true
docker volume rm -f "$CONFIG_VOL" "$WORKSPACE_VOL" >/dev/null 2>&1 || true

echo "✅ All tests passed! The daemon is successfully respecting PUID/PGID, /config mounts, and includes the Go toolchain."
