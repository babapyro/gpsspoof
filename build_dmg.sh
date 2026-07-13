#!/bin/bash
set -e

# Point to full Xcode instance for xcodebuild if it exists locally
if [ -d "/Users/cagan/Downloads/Xcode-beta.app" ]; then
    export DEVELOPER_DIR="/Users/cagan/Downloads/Xcode-beta.app/Contents/Developer"
fi

echo "=== 1. Cleaning build folders ==="
rm -rf ./buildClean
rm -rf ./dmg_temp
rm -f ./LocSpoof.dmg

echo "=== 2. Compiling Xcode SwiftUI App in Release mode ==="
xcodebuild -project LocSpoof.xcodeproj -scheme LocSpoof -configuration Release -derivedDataPath ./buildClean build

echo "=== 3. Packaging into DMG ==="
mkdir -p ./dmg_temp
# Copy build output to temp directory
cp -R ./buildClean/Build/Products/Release/LocSpoof.app ./dmg_temp/
# Create applications symlink
ln -s /Applications ./dmg_temp/Applications

# Run hdiutil to create DMG
hdiutil create -volname "LocSpoof" -srcfolder ./dmg_temp -ov -format UDZO ./LocSpoof.dmg

echo "=== 4. Cleaning up ==="
rm -rf ./buildClean
rm -rf ./dmg_temp

echo "=== SUCCESS! Compiled binary saved as LocSpoof.dmg ==="
