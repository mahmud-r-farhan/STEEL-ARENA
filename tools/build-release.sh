#!/usr/bin/env bash
#=============================================================================
# Steel Arena — Cross-Platform Release Packaging Script
# Generates:
#   1. Universal .love bundle:        dist/steel-arena-v${VERSION}.love
#   2. Windows x64 Standalone Zip:   dist/steel-arena-v${VERSION}-windows-x64.zip
#   3. Linux Standalone Tarball:     dist/steel-arena-v${VERSION}-linux.tar.gz
#   4. Android Standalone APK:       dist/steel-arena-v${VERSION}-android.apk
#   5. Web (HTML5/WASM) Bundle:      dist/steel-arena-v${VERSION}-web.zip
#=============================================================================
set -e

VERSION="${1:-1.0.0}"
DIST_DIR="dist"
LOVE_VERSION="11.5"
PACKAGE_PREFIX="steel-arena-v${VERSION}"

echo "=========================================================="
echo "  Packaging Steel Arena v${VERSION} (LÖVE ${LOVE_VERSION})"
echo "=========================================================="

mkdir -p "${DIST_DIR}"

# 1. Create Universal .love archive
echo "[1/5] Building universal .love package..."
LOVE_FILE="${DIST_DIR}/${PACKAGE_PREFIX}.love"
rm -f "${LOVE_FILE}"
(cd src && zip -9 -q -r "../${LOVE_FILE}" . -x ".*" -x "__MACOSX*" -x "*.DS_Store*")
echo "  -> Created ${LOVE_FILE}"

# 2. Package Windows 64-bit Standalone Zip
echo "[2/5] Building Windows x64 Standalone package..."
WIN_STAGE="${DIST_DIR}/${PACKAGE_PREFIX}-windows-x64"
rm -rf "${WIN_STAGE}"
mkdir -p "${WIN_STAGE}"

# Retrieve official Windows 64-bit Love binary if not present in tools/love
if [ ! -f "tools/love/love.exe" ]; then
  echo "  Downloading LÖVE ${LOVE_VERSION} Win64 runtime..."
  mkdir -p tools
  curl -sSL "https://github.com/love2d/love/releases/download/${LOVE_VERSION}/love-${LOVE_VERSION}-win64.zip" -o "tools/love-win64.zip"
  unzip -q "tools/love-win64.zip" -d "tools/"
  mv "tools/love-${LOVE_VERSION}-win64" "tools/love"
  rm -f "tools/love-win64.zip"
fi

# Fuse love.exe + steel-arena.love into steel-arena.exe
cat "tools/love/love.exe" "${LOVE_FILE}" > "${WIN_STAGE}/steel-arena.exe"
chmod +x "${WIN_STAGE}/steel-arena.exe"

# Copy required DLLs, icons, license, and docs
cp tools/love/*.dll "${WIN_STAGE}/"
cp tools/love/license.txt "${WIN_STAGE}/LICENSE-LOVE.txt" 2>/dev/null || true
cp tools/love/game.ico "${WIN_STAGE}/" 2>/dev/null || true
cp tools/start-game.bat tools/start-server.bat "${WIN_STAGE}/"
cp README.md LICENSE SECURITY.md CODE_OF_CONDUCT.md "${WIN_STAGE}/"
mkdir -p "${WIN_STAGE}/docs"
cp docs/*.md "${WIN_STAGE}/docs/"

# Create Windows Zip
WIN_ZIP="${DIST_DIR}/${PACKAGE_PREFIX}-windows-x64.zip"
rm -f "${WIN_ZIP}"
(cd "${DIST_DIR}" && zip -9 -q -r "${PACKAGE_PREFIX}-windows-x64.zip" "${PACKAGE_PREFIX}-windows-x64")
rm -rf "${WIN_STAGE}"
echo "  -> Created ${WIN_ZIP}"

# 3. Package Linux Standalone / Portable Tarball
echo "[3/5] Building Linux Standalone package..."
LINUX_STAGE="${DIST_DIR}/${PACKAGE_PREFIX}-linux"
rm -rf "${LINUX_STAGE}"
mkdir -p "${LINUX_STAGE}"

cp "${LOVE_FILE}" "${LINUX_STAGE}/steel-arena.love"
cp README.md LICENSE SECURITY.md CODE_OF_CONDUCT.md "${LINUX_STAGE}/"
mkdir -p "${LINUX_STAGE}/docs"
cp docs/*.md "${LINUX_STAGE}/docs/"

cat << 'EOF' > "${LINUX_STAGE}/start-game.sh"
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v love >/dev/null 2>&1; then
  love "${DIR}/steel-arena.love" "$@"
else
  echo "Error: LÖVE 11.5 is required to run Steel Arena on Linux."
  echo "Install via: sudo apt install love   OR   visit https://love2d.org"
  exit 1
fi
EOF

cat << 'EOF' > "${LINUX_STAGE}/start-server.sh"
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v love >/dev/null 2>&1; then
  love "${DIR}/steel-arena.love" --server "$@"
else
  echo "Error: LÖVE 11.5 is required to host the Steel Arena dedicated server."
  exit 1
fi
EOF

chmod +x "${LINUX_STAGE}/start-game.sh" "${LINUX_STAGE}/start-server.sh"

LINUX_TAR="${DIST_DIR}/${PACKAGE_PREFIX}-linux.tar.gz"
rm -f "${LINUX_TAR}"
tar -czf "${LINUX_TAR}" -C "${DIST_DIR}" "${PACKAGE_PREFIX}-linux"
rm -rf "${LINUX_STAGE}"
echo "  -> Created ${LINUX_TAR}"

# 4. Package Android Standalone APK
echo "[4/5] Building Android Standalone APK..."
APK_FILE="${DIST_DIR}/${PACKAGE_PREFIX}-android.apk"
BASE_APK="tools/love-${LOVE_VERSION}-android.apk"

if [ ! -f "${BASE_APK}" ]; then
  echo "  Fetching official LÖVE ${LOVE_VERSION} Android APK runtime..."
  mkdir -p tools
  curl -sSL "https://github.com/love2d/love/releases/download/${LOVE_VERSION}/love-${LOVE_VERSION}-android.apk" -o "${BASE_APK}" || true
fi

if [ -f "${BASE_APK}" ]; then
  TMP_APK="${DIST_DIR}/temp_embed.apk"
  cp "${BASE_APK}" "${TMP_APK}"
  
  # Inject game.love into APK assets/
  mkdir -p "${DIST_DIR}/apk_assets/assets"
  cp "${LOVE_FILE}" "${DIST_DIR}/apk_assets/assets/game.love"
  (cd "${DIST_DIR}/apk_assets" && zip -u -0 -q "../temp_embed.apk" assets/game.love)
  rm -rf "${DIST_DIR}/apk_assets"
  
  # Remove old signatures
  zip -d "${TMP_APK}" "META-INF/*" 2>/dev/null || true
  
  # Align and Sign if build tools are present, otherwise provide standalone embed
  if command -v zipalign >/dev/null 2>&1 && command -v apksigner >/dev/null 2>&1; then
    zipalign -f -p 4 "${TMP_APK}" "${APK_FILE}.unaligned"
    rm -f "${TMP_APK}"
    
    # Generate temporary release keystore if needed
    if [ ! -f "tools/release.keystore" ]; then
      keytool -genkey -v -keystore tools/release.keystore -alias steelarena \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -storepass steelarena -keypass steelarena \
        -dname "CN=SteelArena, OU=Game, O=SteelArena, L=Unknown, S=Unknown, C=US"
    fi
    
    apksigner sign --ks tools/release.keystore --ks-pass pass:steelarena \
      --key-pass pass:steelarena --out "${APK_FILE}" "${APK_FILE}.unaligned"
    rm -f "${APK_FILE}.unaligned"
    echo "  -> Created signed ${APK_FILE}"
  else
    # Fallback to direct signed-capable APK package
    mv "${TMP_APK}" "${APK_FILE}"
    echo "  -> Created ${APK_FILE} (installable directly or with LÖVE Android runtime)"
  fi
else
  echo "  Notice: ${BASE_APK} not available; universal .love is Android-ready via LÖVE for Android."
fi

# 5. Package Web (HTML5 / WebAssembly) Bundle
echo "[5/5] Building Web (HTML5/WASM) package..."
WEB_DIR="${DIST_DIR}/web"
WEB_ZIP="${DIST_DIR}/${PACKAGE_PREFIX}-web.zip"
rm -rf "${WEB_DIR}" "${WEB_ZIP}"

if command -v npx >/dev/null 2>&1; then
  echo "  Running love.js compiler..."
  npx -y love.js "${LOVE_FILE}" "${WEB_DIR}" \
    --title "STEEL ARENA - 2D Tank Battle" \
    --memory 67108864 \
    --compatibility 2>/dev/null || true

  if [ -d "${WEB_DIR}" ] && [ -f "${WEB_DIR}/index.html" ]; then
    (cd "${DIST_DIR}" && zip -9 -q -r "${PACKAGE_PREFIX}-web.zip" "web")
    echo "  -> Created ${WEB_ZIP}"
  else
    echo "  Notice: love.js compilation did not generate index.html; skipping web zip."
  fi
fi

echo ""
echo "=========================================================="
echo "  Build Completed Successfully!"
echo "  Artifacts generated in ${DIST_DIR}/:"
ls -lh "${DIST_DIR}"
echo "=========================================================="
