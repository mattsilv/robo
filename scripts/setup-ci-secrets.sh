#!/bin/bash
# Setup GitHub Actions secrets for TestFlight CI/CD.
# Run this once from the repo root after creating your App Store Connect API key.
set -euo pipefail

echo "=== Robo CI/CD Secret Setup ==="
echo ""
echo "This script will guide you through adding the 6 required GitHub secrets."
echo "Prerequisites:"
echo "  1. gh CLI installed and authenticated (gh auth status)"
echo "  2. Distribution certificate exported as .p12 from Keychain Access"
echo "  3. App Store Connect API key created (Users & Access → Integrations → Keys)"
echo ""

# Check gh CLI
if ! gh auth status &>/dev/null; then
  echo "ERROR: gh CLI not authenticated. Run: gh auth login"
  exit 1
fi

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
if [ -z "$REPO" ]; then
  echo "ERROR: Not in a GitHub repo. Run from the robo/ directory."
  exit 1
fi
echo "Repository: $REPO"
echo ""

# 1. Distribution certificate
echo "--- Step 1: Distribution Certificate ---"
echo "Export from Keychain Access:"
echo '  1. Open Keychain Access'
echo '  2. Find "Apple Distribution: ... (R3Z5CY34Q5)"'
echo '  3. Right-click → Export Items → save as .p12'
echo ""
read -rp "Path to .p12 file: " P12_PATH
P12_PATH="${P12_PATH/#\~/$HOME}"

if [ ! -f "$P12_PATH" ]; then
  echo "ERROR: File not found: $P12_PATH"
  exit 1
fi

read -rsp "P12 password (set during export): " P12_PASSWORD
echo ""

# Encode and set
base64 -i "$P12_PATH" | gh secret set BUILD_CERTIFICATE_BASE64
echo "$P12_PASSWORD" | gh secret set P12_PASSWORD
echo "Set BUILD_CERTIFICATE_BASE64 and P12_PASSWORD"

# 2. App Store Connect API Key
echo ""
echo "--- Step 2: App Store Connect API Key ---"
echo "Create at: https://appstoreconnect.apple.com/access/integrations/api"
echo '  1. Click "+" to create a new key'
echo '  2. Name: "GitHub Actions", Role: "App Manager"'
echo '  3. Note the Key ID and Issuer ID'
echo '  4. Download the .p8 file (only available once!)'
echo ""

read -rp "API Key ID (e.g. ABC123DEF4): " API_KEY_ID
read -rp "Issuer ID (UUID at top of page): " API_ISSUER_ID
read -rp "Path to .p8 file: " P8_PATH
P8_PATH="${P8_PATH/#\~/$HOME}"

if [ ! -f "$P8_PATH" ]; then
  echo "ERROR: File not found: $P8_PATH"
  exit 1
fi

echo "$API_KEY_ID" | gh secret set APPSTORE_CONNECT_API_KEY_ID
echo "$API_ISSUER_ID" | gh secret set APPSTORE_CONNECT_API_ISSUER_ID
gh secret set APPSTORE_CONNECT_API_PRIVATE_KEY < "$P8_PATH"
echo "Set APPSTORE_CONNECT_API_KEY_ID, APPSTORE_CONNECT_API_ISSUER_ID, and APPSTORE_CONNECT_API_PRIVATE_KEY"

# 3. Keychain password
echo ""
echo "--- Step 3: CI Keychain Password ---"
KEYCHAIN_PW=$(openssl rand -base64 24)
echo "$KEYCHAIN_PW" | gh secret set KEYCHAIN_PASSWORD
echo "Set KEYCHAIN_PASSWORD (auto-generated)"

# Summary
echo ""
echo "=== All 6 secrets configured ==="
echo ""
echo "Secrets set on $REPO:"
echo "  - BUILD_CERTIFICATE_BASE64"
echo "  - P12_PASSWORD"
echo "  - APPSTORE_CONNECT_API_KEY_ID"
echo "  - APPSTORE_CONNECT_API_ISSUER_ID"
echo "  - APPSTORE_CONNECT_API_PRIVATE_KEY"
echo "  - KEYCHAIN_PASSWORD"
echo ""
echo "Next: push a change to ios/ on main to trigger the workflow."
echo "Monitor at: https://github.com/$REPO/actions"
