#!/bin/zsh
# Bygger Nästa tåg och laddar upp till TestFlight, men bara om alla tester är gröna.
# Höj CURRENT_PROJECT_VERSION i projektet först. Se MUST_STAY.md.
set -euo pipefail
cd "${0:A:h}"

echo "Testar …"
if ! (cd NastaTagCore && swift test 2>&1 | tail -3; exit ${pipestatus[1]}); then
    echo "Testerna är röda. Rätta appen, inte testerna, och försök igen." >&2
    exit 1
fi

build=$(grep -m1 "CURRENT_PROJECT_VERSION = " NastaTag.xcodeproj/project.pbxproj | grep -o "[0-9]*")
echo "Bygger 1.0 ($build) …"
rm -rf build/NastaTag.xcarchive
xcodebuild -scheme NastaTag -configuration Release -destination 'generic/platform=iOS' \
    -archivePath build/NastaTag.xcarchive -allowProvisioningUpdates archive -quiet

echo "Laddar upp …"
xcodebuild -exportArchive -archivePath build/NastaTag.xcarchive -exportOptionsPlist ExportOptions.plist \
    -exportPath build/export -allowProvisioningUpdates 2>&1 | grep -E "error|EXPORT|Upload succeeded"
