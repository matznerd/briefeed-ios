#!/bin/bash
#
# Check for critical issues that cause UI freezes and performance problems

echo "🔍 Checking for Critical Issues..."
echo "================================="

# Check for print in SwiftUI body
echo ""
echo "1️⃣ Checking for print statements in SwiftUI body..."
if grep -r "var body.*View.*{.*print(" --include="*.swift" Briefeed/ 2>/dev/null | head -5; then
    echo "❌ Found print statements in SwiftUI body (causes re-renders!)"
else
    echo "✅ No print statements in SwiftUI body"
fi

# Check for timers without cleanup
echo ""
echo "2️⃣ Checking for timers without cleanup..."
TIMER_COUNT=$(swiftlint lint --quiet 2>/dev/null | grep "Timer cleanup required" | wc -l)
if [ $TIMER_COUNT -gt 0 ]; then
    echo "❌ Found $TIMER_COUNT timers without cleanup (memory leaks!)"
    swiftlint lint --quiet 2>/dev/null | grep "Timer cleanup required" | head -5
else
    echo "✅ All timers have proper cleanup"
fi

# Check for Combine subscriptions without cleanup
echo ""
echo "3️⃣ Checking for Combine subscriptions without cleanup..."
COMBINE_COUNT=$(swiftlint lint --quiet 2>/dev/null | grep "Combine subscription cleanup" | wc -l)
if [ $COMBINE_COUNT -gt 0 ]; then
    echo "❌ Found $COMBINE_COUNT Combine subscriptions without cleanup"
    swiftlint lint --quiet 2>/dev/null | grep "Combine subscription cleanup" | head -5
else
    echo "✅ All Combine subscriptions are properly managed"
fi

# Check for force unwrapping
echo ""
echo "4️⃣ Checking for force unwrapping..."
FORCE_COUNT=$(swiftlint lint --quiet 2>/dev/null | grep "Avoid force unwrap" | wc -l)
if [ $FORCE_COUNT -gt 0 ]; then
    echo "⚠️  Found $FORCE_COUNT force unwraps (crash risk!)"
    swiftlint lint --quiet 2>/dev/null | grep "Avoid force unwrap" | head -5
else
    echo "✅ No dangerous force unwrapping"
fi

# Check for rapid timers
echo ""
echo "5️⃣ Checking for rapid UI update timers..."
if grep -r "Timer.*TimeInterval.*0\.[0-2]" --include="*.swift" Briefeed/ 2>/dev/null | head -5; then
    echo "❌ Found rapid timers (< 0.3s) that can cause UI performance issues"
else
    echo "✅ No rapid UI update timers found"
fi

# Check for @State in ObservableObject
echo ""
echo "6️⃣ Checking for @State in ObservableObject..."
if grep -r "class.*ObservableObject.*@State" --include="*.swift" Briefeed/ 2>/dev/null | head -5; then
    echo "❌ Found @State in ObservableObject (should use @Published)"
else
    echo "✅ No misused @State in ObservableObject"
fi

echo ""
echo "================================="
echo "📊 Summary Report"
echo "================================="

# Run full SwiftLint and get counts
TOTAL_WARNINGS=$(swiftlint lint --quiet 2>/dev/null | grep warning | wc -l)
TOTAL_ERRORS=$(swiftlint lint --quiet 2>/dev/null | grep error | wc -l)

echo "Total Warnings: $TOTAL_WARNINGS"
echo "Total Errors: $TOTAL_ERRORS"

if [ $TOTAL_ERRORS -gt 0 ]; then
    echo ""
    echo "❌ Critical issues found! Fix errors before proceeding."
    echo "Run 'swiftlint lint' for full details"
    exit 1
elif [ $TOTAL_WARNINGS -gt 20 ]; then
    echo ""
    echo "⚠️  Many warnings found. Consider cleaning them up."
    echo "Run 'swiftlint autocorrect' to fix some automatically"
else
    echo ""
    echo "✅ Code quality looks good!"
fi