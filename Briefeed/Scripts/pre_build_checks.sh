#!/bin/bash

# Pre-Build Checks Script
# Run this before building to ensure critical functionality is intact

echo "🚀 Running pre-build checks..."

# Run scrolling check
./Scripts/check_scrolling.sh
SCROLL_CHECK=$?

# Run other checks here...

# Summary
if [ $SCROLL_CHECK -eq 0 ]; then
    echo "✅ All pre-build checks passed!"
    exit 0
else
    echo "❌ Pre-build checks failed. Please fix the issues before building."
    exit 1
fi