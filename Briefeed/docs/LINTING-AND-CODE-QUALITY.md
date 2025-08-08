# Linting and Code Quality Guide

## Overview

This project uses SwiftLint to maintain code quality and catch common issues that can cause UI freezes, memory leaks, and performance problems.

## Setup

### 1. Install SwiftLint

```bash
brew install swiftlint
```

### 2. Xcode Integration

Run the setup script:
```bash
./Scripts/add_swiftlint_to_xcode.sh
```

Or manually add a Build Phase in Xcode (see script for instructions).

### 3. Pre-commit Hook

The pre-commit hook is already configured in `.git/hooks/pre-commit`. It will automatically run SwiftLint on staged files before each commit.

## Running SwiftLint

### Check all files
```bash
swiftlint lint
```

### Auto-fix correctable issues
```bash
swiftlint autocorrect
```

### Check specific file
```bash
swiftlint lint --path Briefeed/ContentView.swift
```

## Key Rules for UI Performance

### 1. Avoid Print in SwiftUI Body
❌ **Bad:**
```swift
var body: some View {
    let _ = print("Debug") // Causes re-renders!
    return Text("Hello")
}
```

✅ **Good:**
```swift
var body: some View {
    Text("Hello")
        .onAppear { print("Debug") }
}
```

### 2. Timer Cleanup
❌ **Bad:**
```swift
class ViewModel: ObservableObject {
    var timer = Timer.scheduledTimer(...)
    // No cleanup!
}
```

✅ **Good:**
```swift
class ViewModel: ObservableObject {
    var timer: Timer?
    
    deinit {
        timer?.invalidate()
    }
}
```

### 3. Combine Subscription Management
❌ **Bad:**
```swift
audio.$isPlaying.sink { ... }
// Subscription not stored!
```

✅ **Good:**
```swift
private var cancellables = Set<AnyCancellable>()

audio.$isPlaying
    .sink { ... }
    .store(in: &cancellables)
```

### 4. @Published with Private Setters
❌ **Bad:**
```swift
@Published var isPlaying = false // Can be modified externally
```

✅ **Good:**
```swift
@Published private(set) var isPlaying = false
```

### 5. Avoid Continuous UI Updates
❌ **Bad:**
```swift
Timer.scheduledTimer(withTimeInterval: 0.1, ...) // Too frequent!
```

✅ **Good:**
```swift
Timer.scheduledTimer(withTimeInterval: 0.5, ...) // Better for UI
```

## Custom Rules

Our `.swiftlint.yml` includes custom rules to catch:

- Print statements in SwiftUI body (causes re-renders)
- @State in ObservableObject (should use @Published)
- Missing timer cleanup (memory leaks)
- Missing Combine cleanup (memory leaks)
- Force unwrapping (crash risks)
- UI updates without @MainActor
- Continuous UI updates (< 0.3s timers)

## Common Issues and Fixes

### Issue: UI Freezes
**Cause:** Print statements in body, continuous updates, or infinite loops
**Fix:** Remove prints, throttle updates, check for recursive calls

### Issue: Memory Leaks
**Cause:** Timers not invalidated, Combine subscriptions not stored
**Fix:** Clean up in deinit, store subscriptions in cancellables

### Issue: Crashes
**Cause:** Force unwrapping optionals
**Fix:** Use optional binding or nil-coalescing

## CI/CD Integration

Add to your CI pipeline:
```yaml
- name: SwiftLint
  run: |
    swiftlint lint --reporter github-actions-logging
```

## Suppressing Warnings

If you need to suppress a warning for a specific line:
```swift
// swiftlint:disable:next force_unwrapping
let value = optional!
```

Or for a whole file:
```swift
// swiftlint:disable force_unwrapping
```

## Best Practices

1. **Run SwiftLint before committing** - The pre-commit hook does this automatically
2. **Fix warnings immediately** - Don't let them accumulate
3. **Use autocorrect** - For simple fixes like whitespace
4. **Review custom rules** - They catch app-specific issues
5. **Keep configuration updated** - Add rules as you find new patterns

## Troubleshooting

### SwiftLint not found
```bash
brew install swiftlint
```

### Too many warnings
Start with critical issues:
```bash
swiftlint lint | grep error
```

### Pre-commit hook not running
```bash
chmod +x .git/hooks/pre-commit
```

## Resources

- [SwiftLint Rules](https://realm.github.io/SwiftLint/rule-directory.html)
- [SwiftUI Performance](https://www.hackingwithswift.com/quick-start/swiftui/how-to-improve-swiftui-performance)
- [Combine Memory Management](https://www.donnywals.com/understanding-combines-cancellable-and-anycancellable/)