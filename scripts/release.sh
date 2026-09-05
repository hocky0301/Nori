#!/bin/zsh
# release.sh [version] — Release build, ad-hoc signed, zipped into dist/.
# Usage: scripts/release.sh 0.1.0
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:-$(grep MARKETING_VERSION project.yml | head -1 | sed 's/.*"\(.*\)".*/\1/')}
DD=${NORI_DD:-$(pwd)/DerivedData}
[ -d Nori.xcodeproj ] || xcodegen generate
xcodebuild -project Nori.xcodeproj -scheme Nori -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DD" \
  MARKETING_VERSION="$VERSION" CODE_SIGN_IDENTITY="-" \
  build 2>&1 | grep -E 'error:|\*\* BUILD' || true
APP="$DD/Build/Products/Release/Nori.app"
[ -d "$APP" ] || { echo "build failed: $APP missing"; exit 1; }
# A stable ad-hoc signature keeps TCC's Accessibility grant across reinstalls of the same build.
codesign --force --deep --sign - --timestamp=none "$APP"
mkdir -p dist
rm -f "dist/Nori-$VERSION.zip"
ditto -c -k --keepParent "$APP" "dist/Nori-$VERSION.zip"
echo "dist/Nori-$VERSION.zip ($(du -h "dist/Nori-$VERSION.zip" | cut -f1))"
