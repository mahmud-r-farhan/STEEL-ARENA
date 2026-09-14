#!/usr/bin/env bash
# Build release packages for Steel Arena
set -e

VERSION="1.0.0"
DIST_DIR="dist"
PACKAGE_NAME="steel-arena-v${VERSION}"

echo "=== Packaging Steel Arena v${VERSION} ==="

# Clean existing build output
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

# Build .love file
echo "[1/4] Creating .love archive..."
(cd src && zip -9 -q -r "../${DIST_DIR}/${PACKAGE_NAME}.love" . -x ".*")

# Create temporary distribution staging directory
STAGE_DIR="${DIST_DIR}/${PACKAGE_NAME}-dist"
mkdir -p "${STAGE_DIR}"

cp "${DIST_DIR}/${PACKAGE_NAME}.love" "${STAGE_DIR}/steel-arena.love"
cp README.md LICENSE SECURITY.md CODE_OF_CONDUCT.md "${STAGE_DIR}/"
mkdir -p "${STAGE_DIR}/docs"
cp docs/*.md "${STAGE_DIR}/docs/"

# Create single-player & multiplayer helper launch scripts
cat << 'LAUNCH_SOLO' > "${STAGE_DIR}/start-solo.sh"
#!/usr/bin/env bash
love steel-arena.love
LAUNCH_SOLO

cat << 'LAUNCH_SERVER' > "${STAGE_DIR}/start-server.sh"
#!/usr/bin/env bash
love steel-arena.love --server
LAUNCH_SERVER

chmod +x "${STAGE_DIR}/start-solo.sh" "${STAGE_DIR}/start-server.sh"

echo "[2/4] Zipping distribution package..."
(cd "${DIST_DIR}" && zip -9 -q -r "${PACKAGE_NAME}-dist.zip" "${PACKAGE_NAME}-dist")

# Cleanup staging directory
rm -rf "${STAGE_DIR}"

echo "[3/4] Build complete!"
echo "Artifacts generated in ${DIST_DIR}/:"
ls -lh "${DIST_DIR}"

echo "[4/4] Verifying generated .love file structure..."
unzip -l "${DIST_DIR}/${PACKAGE_NAME}.love" | head -n 15
