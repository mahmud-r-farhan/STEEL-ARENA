#!/usr/bin/env bash
# Fetch the LÖVE 11.5 runtime into tools/love (gitignored).
# Usage: bash tools/fetch-love.sh
set -e
cd "$(dirname "$0")"
LOVE_VER=11.5
mkdir -p love
if [ -f love/love.exe ]; then
  echo "love already present at tools/love/love.exe"
  exit 0
fi
echo "Downloading LÖVE ${LOVE_VER} win64..."
curl -L -o love.zip "https://github.com/love2d/love/releases/download/${LOVE_VER}/love-${LOVE_VER}-win64.zip"
unzip -q -o love.zip
mv "love-${LOVE_VER}-win64" love_tmp
cp love_tmp/* love/ 2>/dev/null || true
rm -rf love_tmp love.zip
echo "Done. Run the game with: tools/love/love.exe src"
