#!/bin/bash

# TDD Test Runner Script
# Runs our TDD tests to verify architecture fixes

echo "🧪 Running TDD Architecture Tests..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Find an available simulator
SIMULATOR_ID=$(xcrun simctl list devices available | grep "iPhone" | head -1 | sed -E 's/.*\(([^)]+)\).*/\1/')

if [ -z "$SIMULATOR_ID" ]; then
    echo "❌ No available iPhone simulator found"
    exit 1
fi

echo "📱 Using simulator: $SIMULATOR_ID"

# Build test target first
echo "🔨 Building test target..."
xcodebuild build-for-testing \
    -scheme Briefeed \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    -quiet 2>&1 | grep -E "error:|warning:" || true

# Run specific test classes
echo ""
echo "🏗️ Testing Service Architecture..."
xcodebuild test-without-building \
    -scheme Briefeed \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    -only-testing:BriefeedTests/ServiceArchitectureTests \
    2>&1 | grep -E "Test Case.*passed|Test Case.*failed|error:" | while read line; do
    if [[ $line == *"passed"* ]]; then
        echo -e "${GREEN}✅ $line${NC}"
    elif [[ $line == *"failed"* ]]; then
        echo -e "${RED}❌ $line${NC}"
    else
        echo -e "${YELLOW}⚠️  $line${NC}"
    fi
done

echo ""
echo "🎯 Summary:"
echo "Run this script after each architecture fix to verify tests pass"