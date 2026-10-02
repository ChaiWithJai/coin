#!/bin/zsh
# Archive Coin and upload it to TestFlight (internal testing only).
# Needs: Apple ID with a paid Developer Program team signed in to Xcode > Settings > Accounts,
# and an App Store Connect app record for bundle ID com.coinboxing.prototype.
# Usage: ./testflight.sh TEAM_ID
set -euo pipefail
TEAM=${1:?usage: ./testflight.sh TEAM_ID}
cd "$(dirname "$0")"
BUILD=$(date +%Y%m%d%H%M)
OUT=../../../work/testflight/$BUILD
mkdir -p "$OUT"
xcodegen generate --spec project.yml
pod install
xcodebuild -workspace Coin.xcworkspace -scheme Coin -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$OUT/Coin.xcarchive" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" CURRENT_PROJECT_VERSION="$BUILD" archive
xcodebuild -exportArchive -archivePath "$OUT/Coin.xcarchive" -exportOptionsPlist ExportOptions.plist \
  -exportPath "$OUT/export" -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM"
echo "Uploaded build $BUILD. It appears in App Store Connect > TestFlight after processing."
