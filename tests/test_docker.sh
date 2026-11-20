#!/bin/bash
set -euo pipefail

echo "Running Antigravity Daemon Test Suite"
echo "-----------------------------------"

IMAGE_NAME="antigravity-daemon:test"
# We use custom test IDs to ensure it isn't just defaulting to the current user by chance
TEST_PUID=1099
TEST_PGID=1099
CONFIG_VOL="agy_test_config_$(date +%s)_$RANDOM"
WORKSPACE_VOL="agy_test_workspace_$(date +%s)_$RANDOM"
CONTAINER_ID=""
SUDO_CONTAINER_ID=""

cleanup() {
    for c in "$CONTAINER_ID" "$SUDO_CONTAINER_ID"; do
        [ -n "$c" ] && docker rm -f "$c" >/dev/null 2>&1 || true
    done
    docker volume rm -f "$CONFIG_VOL" "$WORKSPACE_VOL" >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() {
    echo "❌ ERROR: $*"
    [ -n "$CONTAINER_ID" ] && docker logs "$CONTAINER_ID" 2>&1 | tail -40
    exit 1
}

docker volume create "$CONFIG_VOL" >/dev/null
docker volume create "$WORKSPACE_VOL" >/dev/null

echo "[1/5] Building Docker image..."
docker build -t "$IMAGE_NAME" . >/dev/null

echo "[2/5] Starting container with PUID=$TEST_PUID and PGID=$TEST_PGID..."
# Run detached with TTY enabled
CONTAINER_ID=$(docker run -dit \
    -e PUID=$TEST_PUID \
    -e PGID=$TEST_PGID \
    -e TERM=xterm -e COLUMNS=80 -e LINES=24 \
    -v "$CONFIG_VOL:/config" \
    -v "$WORKSPACE_VOL:/workspace" \
    "$IMAGE_NAME")

# Give it a couple of seconds to initialize and create files
sleep 3

echo "[3/5] Verifying correct ownership and paths..."

# 1. Check if settings.json was created in the mapped /config folder
docker exec "$CONTAINER_ID" test -f "/config/.gemini/antigravity-cli/settings.json" \
    || fail "settings.json was not created in the /config directory."

# 2. Check if the files are owned by the specified PUID/PGID inside the container
FILE_OWNERSHIP=$(docker exec "$CONTAINER_ID" stat -c "%u:%g" "/config/.gemini/antigravity-cli/settings.json")
[ "$FILE_OWNERSHIP" == "${TEST_PUID}:${TEST_PGID}" ] \
    || fail "File ownership is $FILE_OWNERSHIP, expected ${TEST_PUID}:${TEST_PGID}. PUID/PGID privilege dropping is failing."

# 3. /config holds OAuth tokens and must not be world/group readable
CONFIG_MODE=$(docker exec "$CONTAINER_ID" stat -c "%a" /config)
[ "$CONFIG_MODE" == "700" ] || fail "/config mode is $CONFIG_MODE, expected 700."

# 4. Check if the daemon is still running
CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER_ID")
[ "$CONTAINER_STATUS" == "running" ] || fail "Container is not running (Status: $CONTAINER_STATUS)"

# 5. Check that developer tools (Go, Python, Node) are functional under the unprivileged user
echo "Verifying developer tools..."
docker exec "$CONTAINER_ID" gosu "${TEST_PUID}:${TEST_PGID}" go version
docker exec "$CONTAINER_ID" gosu "${TEST_PUID}:${TEST_PGID}" python3 --version
NODE_VERSION=$(docker exec "$CONTAINER_ID" gosu "${TEST_PUID}:${TEST_PGID}" node --version)
echo "$NODE_VERSION"
[[ "$NODE_VERSION" == v24.* ]] || fail "Expected Node.js v24.x, got $NODE_VERSION"
docker exec "$CONTAINER_ID" gosu "${TEST_PUID}:${TEST_PGID}" npm --version
docker exec "$CONTAINER_ID" gosu "${TEST_PUID}:${TEST_PGID}" bash -c "printf 'package main\nimport \"fmt\"\nfunc main() { fmt.Println(\"Go execution verified\") }\n' > /workspace/test.go && go run /workspace/test.go && rm /workspace/test.go"

# 6. Check PowerPoint generation and rendering toolchain under the unprivileged user
echo "Verifying PowerPoint generation & rendering tools..."
docker exec "$CONTAINER_ID" gosu "${TEST_PUID}:${TEST_PGID}" env HOME=/config bash -euo pipefail -c '
  tmpdir=$(mktemp -d /workspace/pptx-test-XXXXXX)
  trap "rm -rf \"$tmpdir\"" EXIT

  # Generate a deck with python-pptx
  python3 - "$tmpdir/py_deck.pptx" <<'\''PY'\''
import sys
from pptx import Presentation
import matplotlib
import PIL
import defusedxml
import pdf2image

prs = Presentation()
slide = prs.slides.add_slide(prs.slide_layouts[0])
slide.shapes.title.text = "Hello from python-pptx"
prs.save(sys.argv[1])
PY

  # Generate a deck with pptxgenjs (via global NODE_PATH)
  node -e '\''
    const PptxGenJS = require("pptxgenjs");
    const pptx = new PptxGenJS();
    const slide = pptx.addSlide();
    slide.addText("Hello from pptxgenjs", { x: 1, y: 1, fontSize: 24 });
    pptx.writeFile({ fileName: process.argv[1] }).catch(err => { console.error(err); process.exit(1); });
  '\'' "$tmpdir/js_deck.pptx"

  # Render both decks to PDF with LibreOffice Impress and rasterize to PNG with Poppler
  libreoffice --headless --convert-to pdf --outdir "$tmpdir" "$tmpdir/py_deck.pptx" "$tmpdir/js_deck.pptx" >/dev/null
  pdftoppm -png -r 150 "$tmpdir/py_deck.pdf" "$tmpdir/py_slide"
  pdftoppm -png -r 150 "$tmpdir/js_deck.pdf" "$tmpdir/js_slide"

  test -s "$tmpdir/py_slide-1.png"
  test -s "$tmpdir/js_slide-1.png"

  # Verify auxiliary tools and metric-compatible fonts (Carlito = Calibri, Liberation = Arial)
  rsvg-convert --version >/dev/null
  pandoc --version >/dev/null
  FONTS=$(fc-list)
  grep -qi "Carlito" <<< "$FONTS"
  grep -qi "Liberation" <<< "$FONTS"
' || fail "PowerPoint generation/rendering toolchain verification failed."
echo "✓ PowerPoint generation (python-pptx, pptxgenjs, pandoc) and rendering (LibreOffice, pdftoppm, fonts) verified"

# 7. Example agent settings ship in the image and are valid JSON
docker exec "$CONTAINER_ID" jq -e '.model and .toolPermission' /usr/share/antigravity-daemon/settings.example.json >/dev/null \
    || fail "settings.example.json is missing or invalid in the image."
echo "✓ example settings.json shipped and valid"

echo "[4/5] Verifying security defaults..."

# Sudo must be disabled unless AGY_ALLOW_SUDO=true
if docker exec "$CONTAINER_ID" gosu "${TEST_PUID}:${TEST_PGID}" sudo -n true >/dev/null 2>&1; then
    fail "Agent user has sudo by default; it should be opt-in via AGY_ALLOW_SUDO=true."
fi
echo "✓ sudo disabled by default"

# PUID=0 must be refused unless AGY_ALLOW_ROOT=true
if docker run --rm -e PUID=0 "$IMAGE_NAME" >/dev/null 2>&1; then
    fail "Container started with PUID=0; it should refuse to run the agent as root."
fi
echo "✓ PUID=0 refused"

# Non-numeric PUID must be refused
if docker run --rm -e PUID='1000;id' "$IMAGE_NAME" >/dev/null 2>&1; then
    fail "Container accepted a non-numeric PUID."
fi
echo "✓ non-numeric PUID refused"

# Opt-in sudo works
SUDO_CONTAINER_ID=$(docker run -dit -e PUID=$TEST_PUID -e PGID=$TEST_PGID -e AGY_ALLOW_SUDO=true "$IMAGE_NAME")
sleep 3
docker exec "$SUDO_CONTAINER_ID" gosu "${TEST_PUID}:${TEST_PGID}" sudo -n true \
    || fail "AGY_ALLOW_SUDO=true did not grant sudo."
echo "✓ AGY_ALLOW_SUDO=true grants sudo"

echo "[5/5] Cleaning up..."
# (handled by the EXIT trap)

echo "✅ All tests passed! PUID/PGID, /config mounts, toolchain and security defaults verified."
