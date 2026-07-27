# How to Add SwiftAudioEx Package

## Steps to Add via Xcode

1. **Open Xcode Project**
   - Open `Briefeed.xcodeproj` in Xcode

2. **Add Package Dependency**
   - Select the project in the navigator
   - Select the "Briefeed" project (not target)
   - Go to "Package Dependencies" tab
   - Click the "+" button

3. **Enter Package URL**
   ```
   https://github.com/doublesymmetry/SwiftAudioEx
   ```

4. **Version Selection**
   - Choose "Up to Next Major Version"
   - Starting from: 2.0.0

5. **Add to Target**
   - Ensure "Briefeed" target is selected
   - Click "Add Package"

## Alternative: Command Line (if SPM is configured)

```bash
# If you have a Package.swift file
swift package add https://github.com/doublesymmetry/SwiftAudioEx
```

## Verify Installation

After adding, verify by:
1. Building the project (⌘+B)
2. Check that you can import in Swift files:
   ```swift
   import SwiftAudioEx
   ```

## Required Capabilities

Ensure these are enabled in your app:
- **Background Modes**: Audio, AirPlay, and Picture in Picture
- **Capabilities**: Background fetch (for pre-generation)

## Info.plist Requirements

Add if not present:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>fetch</string>
</array>
```

## Note

SwiftAudioEx requires iOS 11.0+ and depends on:
- AVFoundation
- MediaPlayer
- AVKit

These are system frameworks and don't need explicit addition.