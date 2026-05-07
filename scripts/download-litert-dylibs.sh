#!/bin/bash
# download-litert-dylibs.sh
# Downloads the prebuilt LiteRT-LM iOS dylibs from GitHub.
#
# Usage: ./scripts/download-litert-dylibs.sh
#
# This script must be run from the project root (panic-guard/).

set -euo pipefail

REPO="google-ai-edge/LiteRT-LM"
BRANCH="main"
DEST_DIR="prebuilt/ios_arm64"

echo "=== Downloading LiteRT-LM iOS dylibs ==="
echo "Repo: https://github.com/$REPO"
echo "Destination: $DEST_DIR/"
echo ""

# Create destination directory
mkdir -p "$DEST_DIR"

# Files to download from prebuilt/ios_arm64/
FILES=(
    "libLiteRt.dylib"
    "libLiteRtMetalAccelerator.dylib"
    "libLiteRtTopKMetalSampler.dylib"
    "libGemmaModelConstraintProvider.dylib"
)

# Detect if curl or wget is available
if command -v curl &>/dev/null; then
    DOWNLOAD="curl -fsSL"
elif command -v wget &>/dev/null; then
    DOWNLOAD="wget -q -O -"
else
    echo "ERROR: Neither curl nor wget found. Please install one of them."
    exit 1
fi

for file in "${FILES[@]}"; do
    URL="https://github.com/$REPO/raw/$BRANCH/prebuilt/ios_arm64/$file"
    echo "Downloading $file..."
    $DOWNLOAD "$URL" -o "$DEST_DIR/$file"
    echo "  → $DEST_DIR/$file"
done

echo ""
echo "=== Download complete ==="
ls -lh "$DEST_DIR/"
echo ""
echo "Next steps:"
echo "  1. Download a Gemma 4 .litertlm model (see scripts/download-gemma-model.sh)"
echo "  2. Regenerate Xcode project: xcodegen generate && pod install"
echo "  3. Build: xcodebuild -workspace PanicGuard.xcworkspace ..."
