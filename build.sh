#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEME="YellowDot"
ARCHIVE_PATH="$PROJECT_DIR/build/YellowDot.xcarchive"
EXPORT_PATH="$PROJECT_DIR/build/export"

echo "Building YellowDot..."

xcodebuild archive \
    -project "$PROJECT_DIR/YellowDot.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    | xcpretty 2>/dev/null || true

# Extract .app directly from archive
APP_IN_ARCHIVE=$(find "$ARCHIVE_PATH/Products" -name "*.app" | head -1)

if [ -z "$APP_IN_ARCHIVE" ]; then
    echo "ERROR: No .app found in archive"
    exit 1
fi

mkdir -p "$EXPORT_PATH"
cp -R "$APP_IN_ARCHIVE" "$EXPORT_PATH/"

APP_PATH="$EXPORT_PATH/YellowDot.app"
echo ""
echo "Build complete: $APP_PATH"
echo "Drag to /Applications to install."
open "$EXPORT_PATH"
