# TestFlight Deployment Guide

## Prerequisites

- Apple Developer Account with Team ID: `R3Z5CY34Q5`
- Xcode 15.0+ installed
- Physical iPhone for testing (iOS 17+)
- 1024x1024 app icon image (place at `ios/Robo/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png`)

## Deployment Steps

### 1. Verify Workers Deployment

The Workers API is already deployed and live:

```bash
# Test the API
echo '{"name":"test-device"}' | http POST https://robo-api.silv.workers.dev/api/devices/register
```

Expected response:
```json
{
  "id": "...",
  "name": "test-device",
  "registered_at": "...",
  "last_seen_at": null
}
```

### 2. Create App Icon

Create a 1024x1024 PNG app icon and save it to:
```
ios/Robo/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png
```

### 3. Build Archive

#### Option A: Xcode GUI (Recommended)

1. Open `ios/Robo.xcodeproj` in Xcode
2. Select "Any iOS Device (arm64)" as the destination
3. Go to Product → Archive
4. Wait for archive to complete

#### Option B: Command Line

```bash
cd ios

# Clean build folder
xcodebuild clean -scheme Robo -configuration Release

# Create archive
xcodebuild archive \
  -scheme Robo \
  -configuration Release \
  -archivePath ./build/Robo.xcarchive \
  -destination 'generic/platform=iOS'
```

### 4. Upload to App Store Connect

#### Option A: Xcode Organizer (Recommended)

1. Open Xcode → Window → Organizer
2. Select the Robo archive
3. Click "Distribute App"
4. Choose "App Store Connect"
5. Follow the prompts to upload

#### Option B: Command Line

```bash
cd ios

# Export IPA
xcodebuild -exportArchive \
  -archivePath ./build/Robo.xcarchive \
  -exportPath ./build/export \
  -exportOptionsPlist ExportOptions.plist

# Upload to App Store Connect (requires app-specific password)
xcrun altool --upload-app \
  --type ios \
  --file ./build/export/Robo.ipa \
  --username YOUR_APPLE_ID \
  --password @keychain:AC_PASSWORD
```

### 5. Submit for TestFlight Review

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Navigate to your app
3. Select "TestFlight" tab
4. Wait for processing to complete (~5-15 minutes)
5. Once processed, add test information:
   - What to test
   - Contact information
   - Screenshots (optional for internal testing)
6. Click "Submit for Review"

### 6. Internal Testing

Once approved for TestFlight (usually within a few hours):

1. Add internal testers in App Store Connect
2. Testers will receive email invitation
3. Install TestFlight app from App Store
4. Accept invitation and install Robo

## Troubleshooting

### Code Signing Issues

If you encounter code signing errors:

1. Open Xcode
2. Select project → Signing & Capabilities
3. Verify Team is set to `R3Z5CY34Q5`
4. Enable "Automatically manage signing"
5. Xcode will create necessary provisioning profiles

### Missing App Icon

If upload fails due to missing icon:

```bash
# Verify icon exists
ls -l ios/Robo/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png

# Icon must be:
# - Exactly 1024x1024 pixels
# - PNG format
# - No transparency
```

### Archive Not Showing

If archive doesn't appear in Organizer:

1. Check Xcode build logs for errors
2. Ensure destination is "Any iOS Device (arm64)" not Simulator
3. Verify scheme is set to "Release" configuration

## Testing Checklist

Once installed on TestFlight:

- [ ] App launches successfully
- [ ] TabView navigation works (Inbox, Sensors, Settings)
- [ ] Settings shows device ID and API URL
- [ ] Barcode scanner opens (requires physical device)
- [ ] Scan a real barcode, verify haptic feedback
- [ ] Check D1 database for scanned data:
  ```bash
  wrangler d1 execute robo-db --command "SELECT * FROM sensor_data ORDER BY captured_at DESC LIMIT 10"
  ```
- [ ] Inbox view loads without errors
- [ ] API URL can be changed in Settings

## M1 Gate Checklist

- [ ] Workers API deployed and responding
- [ ] TestFlight build submitted
- [ ] Barcode scan → D1 round-trip works on physical device
- [ ] Round-trip time < 2 seconds

## Next Steps (M2+)

After M1 is complete:

- M2: Inbox card system + Camera + Opus integration
- M3: LiDAR sensor module
- M4: Task system + API docs + polish
- M5: Demo video + final submission
