#!/bin/bash
# Pre-deploy validation for Robo iOS app.
# Run before uploading to TestFlight to catch common issues.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
FAIL=0

echo "=== Robo Pre-Deploy Validation ==="
echo ""

# 1. Check encryption compliance key in project.yml
if grep -q "ITSAppUsesNonExemptEncryption: false" ios/project.yml; then
    echo -e "${GREEN}PASS${NC} Encryption compliance key present in project.yml"
else
    echo -e "${RED}FAIL${NC} Missing ITSAppUsesNonExemptEncryption in project.yml"
    FAIL=1
fi

# 2. Check all required Info.plist privacy keys are present
REQUIRED_PLIST_KEYS=(
    "NSCameraUsageDescription"
    "NSPhotoLibraryUsageDescription"
    "NSMotionUsageDescription"
    "NSHealthShareUsageDescription"
    "NSHealthUpdateUsageDescription"
    "NSBluetoothAlwaysUsageDescription"
    "NSLocationWhenInUseUsageDescription"
    "NSLocationAlwaysAndWhenInUseUsageDescription"
)
PLIST_FILE="ios/Robo/Info.plist"
PLIST_FAIL=0
for KEY in "${REQUIRED_PLIST_KEYS[@]}"; do
    if grep -q "$KEY" "$PLIST_FILE"; then
        :
    else
        echo -e "${RED}FAIL${NC} Missing $KEY in Info.plist (App Store will reject)"
        PLIST_FAIL=1
        FAIL=1
    fi
done
if [ $PLIST_FAIL -eq 0 ]; then
    echo -e "${GREEN}PASS${NC} All required Info.plist privacy keys present"
fi

# 3. Check iOS SDK version (April 2026 requirement)
SDK_VERSION=$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo "0")
SDK_MAJOR=$(echo "$SDK_VERSION" | cut -d. -f1)
if [ "$SDK_MAJOR" -ge 26 ]; then
    echo -e "${GREEN}PASS${NC} iOS SDK version: $SDK_VERSION (meets iOS 26+ requirement)"
else
    echo -e "${RED}FAIL${NC} iOS SDK $SDK_VERSION below required iOS 26. Update Xcode."
    FAIL=1
fi

# 3. Check version was bumped (compare with main branch)
CURRENT_VERSION=$(grep "CURRENT_PROJECT_VERSION:" ios/project.yml | head -1 | awk '{print $2}')
MAIN_VERSION=$(git show main:ios/project.yml 2>/dev/null | grep "CURRENT_PROJECT_VERSION:" | head -1 | awk '{print $2}')
if [ -n "$MAIN_VERSION" ] && [ "$CURRENT_VERSION" = "$MAIN_VERSION" ]; then
    echo -e "${RED}FAIL${NC} CURRENT_PROJECT_VERSION ($CURRENT_VERSION) not bumped from main"
    FAIL=1
else
    echo -e "${GREEN}PASS${NC} Build version: $CURRENT_VERSION (main: ${MAIN_VERSION:-N/A})"
fi

# 4. Check explicit modelContext.save() exists in save locations
LIDAR_SAVE=$(grep -c "modelContext.save()" ios/Robo/Views/LiDARScanView.swift 2>/dev/null || true)
BARCODE_SAVE=$(grep -c "modelContext.save()" ios/Robo/Views/BarcodeScannerView.swift 2>/dev/null || true)
if [ "$LIDAR_SAVE" -gt 0 ] && [ "$BARCODE_SAVE" -gt 0 ]; then
    echo -e "${GREEN}PASS${NC} Explicit modelContext.save() in LiDAR and Barcode views"
else
    echo -e "${RED}FAIL${NC} Missing explicit modelContext.save() — data will not persist!"
    FAIL=1
fi

# 5. Check VersionedSchema exists
if grep -rq "VersionedSchema" ios/Robo/Models/RoboSchema.swift 2>/dev/null; then
    echo -e "${GREEN}PASS${NC} VersionedSchema defined in RoboSchema.swift"
else
    echo -e "${RED}FAIL${NC} Missing VersionedSchema — data migrations will fail silently"
    FAIL=1
fi

# 6. Check no bare @Model files outside schema (duplicate definitions)
BARE_MODELS=$(grep -rl "^@Model" ios/Robo/Models/ 2>/dev/null | grep -v RoboSchema.swift || true)
if [ -z "$BARE_MODELS" ]; then
    echo -e "${GREEN}PASS${NC} No bare @Model files outside RoboSchema.swift"
else
    echo -e "${RED}FAIL${NC} Found bare @Model outside schema: $BARE_MODELS"
    FAIL=1
fi

# 7. Store deletion must be preceded by backup (copyItem)
HAS_DELETE=$(grep -c "removeItem\|deleteStore\|destroyPersistentStore" ios/Robo/RoboApp.swift 2>/dev/null || echo "0")
HAS_BACKUP=$(grep -c "copyItem" ios/Robo/RoboApp.swift 2>/dev/null || echo "0")
if [ "$HAS_DELETE" -gt 0 ] && [ "$HAS_BACKUP" -eq 0 ]; then
    echo -e "${RED}FAIL${NC} Store deletion in RoboApp.swift without backup (copyItem required)"
    FAIL=1
elif [ "$HAS_DELETE" -gt 0 ]; then
    echo -e "${GREEN}PASS${NC} Store deletion guarded by backup ($HAS_BACKUP copyItem, $HAS_DELETE removeItem)"
else
    echo -e "${GREEN}PASS${NC} No store deletion in RoboApp.swift"
fi

# 8. Every fatalError must be the resilient last-resort kind (marked "unrecoverable")
TOTAL_FATAL=$(grep -c "fatalError" ios/Robo/RoboApp.swift 2>/dev/null || echo "0")
SAFE_FATAL=$(grep -c "unrecoverable" ios/Robo/RoboApp.swift 2>/dev/null || echo "0")
if [ "$TOTAL_FATAL" -gt "$SAFE_FATAL" ]; then
    echo -e "${RED}FAIL${NC} Found $TOTAL_FATAL fatalError but only $SAFE_FATAL marked 'unrecoverable'"
    grep -n "fatalError" ios/Robo/RoboApp.swift 2>/dev/null || true
    FAIL=1
elif [ "$TOTAL_FATAL" -gt 0 ]; then
    echo -e "${GREEN}PASS${NC} All $TOTAL_FATAL fatalError call(s) are resilient last-resort"
else
    echo -e "${GREEN}PASS${NC} No fatalError in RoboApp.swift"
fi

# 9. Build check
echo ""
echo "Building..."
cd ios
xcodegen generate > /dev/null 2>&1
if xcodebuild -scheme Robo -configuration Debug -destination 'generic/platform=iOS' -allowProvisioningUpdates DEVELOPMENT_TEAM=R3Z5CY34Q5 2>&1 | grep -q "BUILD SUCCEEDED"; then
    echo -e "${GREEN}PASS${NC} Build succeeded"
else
    echo -e "${RED}FAIL${NC} Build failed"
    FAIL=1
fi

echo ""
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}All checks passed! Ready for TestFlight.${NC}"
else
    echo -e "${RED}Some checks failed. Fix before deploying.${NC}"
    exit 1
fi
