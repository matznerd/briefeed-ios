#!/bin/bash

# Script to run Reddit feed tests
# This helps ensure Reddit functionality isn't broken

echo "🧪 Running Reddit Feed Tests..."
echo "================================"

# Set environment variable to enable live API tests if needed
# export TEST_REDDIT_API=1

# Run specific Reddit test classes
xcodebuild test \
    -project Briefeed.xcodeproj \
    -scheme Briefeed \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    -only-testing:BriefeedTests/RedditFeedTests \
    -only-testing:BriefeedTests/FeedRefreshTests \
    -only-testing:BriefeedTests/RedditAPIContractTests \
    | xcpretty

# Check exit code
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "✅ All Reddit tests passed!"
else
    echo "❌ Reddit tests failed!"
    echo ""
    echo "Common issues to check:"
    echo "1. Ensure raw_json=1 parameter is included in Reddit URLs"
    echo "2. Verify User-Agent header is set correctly"
    echo "3. Check that content is not being HTML-escaped"
    echo "4. Ensure video posts and blacklisted domains are filtered"
    exit 1
fi

# Optional: Run a quick manual test
echo ""
echo "🔍 Quick Reddit API Check..."
curl -s -H "User-Agent: test-script" "https://www.reddit.com/r/swift.json?raw_json=1&limit=1" | jq '.data.children[0].data | {title, selftext}' 2>/dev/null || echo "jq not installed, skipping pretty print"