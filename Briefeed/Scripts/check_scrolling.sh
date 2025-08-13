#!/bin/bash

# Check Scrolling Implementation Script
# This script verifies that scrolling and lazy loading are properly implemented

echo "🔍 Checking scrolling implementation..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

# Check for ScrollView with LazyVStack
echo "Checking for ScrollView with LazyVStack..."
if grep -r "ScrollView" --include="*.swift" . > /dev/null 2>&1 && grep -r "LazyVStack" --include="*.swift" . > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} ScrollView with LazyVStack found"
else
    echo -e "${RED}✗${NC} ScrollView with LazyVStack not found"
    ((ERRORS++))
fi

# Check for onAppear implementation for lazy loading
echo "Checking for onAppear implementation..."
if grep -r "\.onAppear" --include="*.swift" . | grep -q "loadMoreIfNeeded" || grep -r "index >= filteredArticles.count - 3" --include="*.swift" . > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} onAppear with loadMoreIfNeeded found"
else
    echo -e "${RED}✗${NC} onAppear with loadMoreIfNeeded not found"
    ((ERRORS++))
fi

# Check for enumerated ForEach (more reliable than regular ForEach)
echo "Checking for enumerated ForEach..."
if grep -r "ForEach(Array.*enumerated()" --include="*.swift" . > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Enumerated ForEach found (better for tracking)"
else
    echo -e "${YELLOW}⚠${NC} Consider using enumerated ForEach for better index tracking"
    ((WARNINGS++))
fi

# Check for unique ID assignment
echo "Checking for unique ID assignment..."
if grep -r "\.id(.*\.id)" --include="*.swift" . > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Unique ID assignment found"
else
    echo -e "${YELLOW}⚠${NC} Consider adding .id() for better view identity"
    ((WARNINGS++))
fi

# Check for loading indicator
echo "Checking for loading indicator..."
if grep -r "isLoadingMore" --include="*.swift" . | grep -q "ProgressView" || grep -r "Loading more articles" --include="*.swift" . > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Loading indicator found"
else
    echo -e "${YELLOW}⚠${NC} Consider adding a loading indicator"
    ((WARNINGS++))
fi

# Check for pagination logic
echo "Checking for pagination logic..."
if grep -r "hasMorePages\|afterToken\|pagination" --include="*.swift" . > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Pagination logic found"
else
    echo -e "${RED}✗${NC} Pagination logic not found"
    ((ERRORS++))
fi

# Check for per-feed pagination tokens
echo "Checking for per-feed pagination..."
if grep -r "feedPaginationTokens" --include="*.swift" . > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Per-feed pagination tokens found"
else
    echo -e "${RED}✗${NC} Per-feed pagination tokens not found"
    ((ERRORS++))
fi

# Check for pagination tests
echo "Checking for pagination tests..."
if [ -f "BriefeedTests/PaginationTests.swift" ] || [ -f "BriefeedTests/ScrollingTests.swift" ]; then
    echo -e "${GREEN}✓${NC} Pagination tests found"
else
    echo -e "${YELLOW}⚠${NC} No pagination tests found"
    ((WARNINGS++))
fi

# Summary
echo ""
echo "==============================="
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ Scrolling implementation check passed!${NC}"
else
    echo -e "${RED}✗ Found $ERRORS errors in scrolling implementation${NC}"
fi

if [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠ Found $WARNINGS warnings that could be improved${NC}"
fi

exit $ERRORS