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

# 2. Check iOS SDK version (April 2026 requirement)
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

# 7. Build check
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
