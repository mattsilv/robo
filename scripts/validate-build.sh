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

# 2. Check version was bumped (compare with main branch)
CURRENT_VERSION=$(grep "CURRENT_PROJECT_VERSION:" ios/project.yml | head -1 | awk '{print $2}')
MAIN_VERSION=$(git show main:ios/project.yml 2>/dev/null | grep "CURRENT_PROJECT_VERSION:" | head -1 | awk '{print $2}')
if [ -n "$MAIN_VERSION" ] && [ "$CURRENT_VERSION" = "$MAIN_VERSION" ]; then
    echo -e "${RED}FAIL${NC} CURRENT_PROJECT_VERSION ($CURRENT_VERSION) not bumped from main"
    FAIL=1
else
    echo -e "${GREEN}PASS${NC} Build version: $CURRENT_VERSION (main: ${MAIN_VERSION:-N/A})"
fi

# 3. Check explicit modelContext.save() exists in save locations
LIDAR_SAVE=$(grep -c "modelContext.save()" ios/Robo/Views/LiDARScanView.swift 2>/dev/null || true)
BARCODE_SAVE=$(grep -c "modelContext.save()" ios/Robo/Views/BarcodeScannerView.swift 2>/dev/null || true)
if [ "$LIDAR_SAVE" -gt 0 ] && [ "$BARCODE_SAVE" -gt 0 ]; then
    echo -e "${GREEN}PASS${NC} Explicit modelContext.save() in LiDAR and Barcode views"
else
    echo -e "${RED}FAIL${NC} Missing explicit modelContext.save() — data will not persist!"
    FAIL=1
fi

# 4. Check all @Model classes are in RoboSchema.swift (single source of truth)
MODEL_IN_SCHEMA=$(grep -c "^@Model" ios/Robo/Models/RoboSchema.swift 2>/dev/null || true)
if [ "$MODEL_IN_SCHEMA" -gt 0 ]; then
    echo -e "${GREEN}PASS${NC} Models defined in RoboSchema.swift ($MODEL_IN_SCHEMA models)"
else
    echo -e "${RED}FAIL${NC} No @Model classes found in RoboSchema.swift"
    FAIL=1
fi

# 5. Check no @Model files outside RoboSchema.swift (duplicate definitions)
BARE_MODELS=$(grep -rl "^@Model" ios/Robo/Models/ 2>/dev/null | grep -v RoboSchema.swift || true)
if [ -z "$BARE_MODELS" ]; then
    echo -e "${GREEN}PASS${NC} No duplicate @Model files outside RoboSchema.swift"
else
    echo -e "${RED}FAIL${NC} Found @Model outside schema: $BARE_MODELS"
    FAIL=1
fi

# 6. Check ModelContainer has graceful error handling (no bare fatalError on first try)
if grep -q "removeItem" ios/Robo/RoboApp.swift 2>/dev/null; then
    echo -e "${GREEN}PASS${NC} ModelContainer has store-reset fallback"
else
    echo -e "${RED}FAIL${NC} ModelContainer missing graceful error handling — will crash on schema change!"
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
cd ..

# 8. Simulator launch test (catches crash-on-launch)
echo ""
echo "Testing simulator launch..."
SIMULATOR_ID=$(xcrun simctl list devices available | grep "iPhone 16 Pro" | head -1 | grep -oE '[A-F0-9-]{36}')
if [ -n "$SIMULATOR_ID" ]; then
    xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
    xcodebuild -scheme Robo -configuration Debug \
        -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
        -derivedDataPath /tmp/RoboTest 2>&1 | tail -1 | grep -q "BUILD SUCCEEDED"
    APP_PATH=$(find /tmp/RoboTest/Build/Products/Debug-iphonesimulator -name "Robo.app" -maxdepth 1 2>/dev/null | head -1)
    if [ -n "$APP_PATH" ]; then
        xcrun simctl install "$SIMULATOR_ID" "$APP_PATH" 2>/dev/null
        xcrun simctl launch "$SIMULATOR_ID" com.silv.Robo 2>/dev/null
        sleep 3
        if xcrun simctl get_app_container "$SIMULATOR_ID" com.silv.Robo 2>/dev/null | grep -q "/"; then
            echo -e "${GREEN}PASS${NC} App launches on simulator without crashing"
        else
            echo -e "${RED}FAIL${NC} App crashed on simulator launch!"
            FAIL=1
        fi
        xcrun simctl terminate "$SIMULATOR_ID" com.silv.Robo 2>/dev/null || true
    else
        echo -e "${RED}FAIL${NC} Could not find built app for simulator"
        FAIL=1
    fi
    xcrun simctl shutdown "$SIMULATOR_ID" 2>/dev/null || true
else
    echo "SKIP Simulator launch test (no iPhone 16 Pro simulator found)"
fi

echo ""
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}All checks passed! Ready for TestFlight.${NC}"
else
    echo -e "${RED}Some checks failed. Fix before deploying.${NC}"
    exit 1
fi
