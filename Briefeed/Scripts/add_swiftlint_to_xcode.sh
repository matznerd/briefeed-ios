#!/bin/bash
#
# Script to add SwiftLint build phase to Xcode project
# This should be run once after cloning the project

echo "📦 Adding SwiftLint Build Phase to Xcode project..."

# This script would normally modify the .pbxproj file
# For now, here are the manual instructions:

cat << EOF
⚙️  Manual Setup Instructions for Xcode:

1. Open Briefeed.xcodeproj in Xcode
2. Select the Briefeed target
3. Go to Build Phases tab
4. Click '+' → 'New Run Script Phase'
5. Name it: "SwiftLint"
6. Drag it to run before 'Compile Sources'
7. Add this script:

if [[ "\$(uname -m)" == arm64 ]]; then
    export PATH="/opt/homebrew/bin:\$PATH"
fi

if which swiftlint > /dev/null; then
    swiftlint
else
    echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
fi

8. Uncheck "Based on dependency analysis" for consistent linting

✅ SwiftLint will now run on every build!
EOF