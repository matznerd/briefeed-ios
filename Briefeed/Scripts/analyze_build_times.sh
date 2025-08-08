#!/bin/bash
#
# Analyze build times and find slow-compiling files

echo "📊 Analyzing Build Times..."
echo "=========================="

# Clean build folder
echo "🧹 Cleaning build folder..."
xcodebuild clean -project Briefeed.xcodeproj -scheme Briefeed -quiet

# Build with timing summary
echo "🔨 Building with timing analysis..."
xcodebuild build \
    -project Briefeed.xcodeproj \
    -scheme Briefeed \
    -configuration Debug \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    -showBuildTimingSummary \
    OTHER_SWIFT_FLAGS="-Xfrontend -debug-time-function-bodies" \
    2>&1 | tee build_log.txt

# Parse results
echo ""
echo "⏱️ Slowest Compiling Functions:"
echo "================================"
grep -E "^\d+\.\d+ms" build_log.txt | sort -rn | head -20

echo ""
echo "📦 Build Time Summary:"
echo "====================="
grep "Build Succeeded" build_log.txt

# If xclogparser is installed, use it for detailed analysis
if command -v xclogparser &> /dev/null; then
    echo ""
    echo "📈 Detailed Analysis with XCLogParser:"
    echo "======================================"
    
    # Find the latest .xcactivitylog
    BUILD_LOG=$(find ~/Library/Developer/Xcode/DerivedData -name "*.xcactivitylog" -mmin -5 | head -1)
    
    if [ -n "$BUILD_LOG" ]; then
        xclogparser parse --file "$BUILD_LOG" --reporter html --output build_report.html
        echo "✅ Detailed report saved to build_report.html"
        echo "   Open with: open build_report.html"
    else
        echo "⚠️  Could not find recent build log"
    fi
fi

# Cleanup
rm -f build_log.txt

echo ""
echo "💡 Tips to Improve Build Times:"
echo "=============================="
echo "1. Use type inference where appropriate"
echo "2. Break up large expressions"
echo "3. Avoid complex type calculations"
echo "4. Use explicit types for complex closures"
echo "5. Split large files into smaller ones"