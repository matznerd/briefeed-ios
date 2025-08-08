# Complete Development Tools Guide

## 🛠️ Tool Suite Overview

We've set up a comprehensive suite of tools to prevent issues and maintain code quality:

### 1. **Static Analysis**
- **SwiftLint** - Catches style issues and potential bugs
- **SwiftFormat** - Ensures consistent code formatting
- **Periphery** - Finds unused code

### 2. **Performance Monitoring**
- **XCTest Performance Tests** - Automated performance regression testing
- **Instruments Templates** - CPU, Memory, and UI profiling
- **Build Time Analysis** - Find slow-compiling code

### 3. **Debug Tools**
- **DiagnosticsView** - In-app performance monitoring
- **Debug Scheme** - Enhanced runtime checks
- **Memory Leak Detection** - Automatic leak detection

### 4. **CI/CD Integration**
- **Danger** - Automated PR reviews
- **Pre-commit Hooks** - Catch issues before commit
- **GitHub Actions** - Continuous integration

## 🚀 Quick Start

### Initial Setup
```bash
# Install all tools
./Scripts/setup_development_tools.sh

# Configure SwiftFormat
swiftformat --config .swiftformat .

# Find unused code
periphery scan

# Analyze build times
./Scripts/analyze_build_times.sh
```

## 📊 Performance Testing

### Run Performance Tests
```bash
xcodebuild test \
  -scheme Briefeed \
  -only-testing:BriefeedTests/PerformanceTests \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

### What's Tested
- View rendering performance
- Queue operations speed
- Memory leak detection
- Combine subscription performance
- State update frequency
- Timer cleanup
- Core Data fetch performance

## 🔍 Debug Diagnostics

### Access Diagnostics View
1. Run app in Debug configuration
2. Shake device (or Cmd+Ctrl+Z in simulator)
3. View real-time performance metrics

### Monitored Metrics
- Memory usage
- CPU usage
- Render count
- Update frequency
- Active timers
- Combine subscriptions
- Queue state

## 🎯 Xcode Scheme Configuration

### Debug Scheme Features
- **Address Sanitizer** - Detects memory corruption
- **Thread Sanitizer** - Finds race conditions
- **Undefined Behavior Sanitizer** - Catches undefined behavior
- **Malloc Stack Logging** - Tracks memory allocations
- **SwiftUI Profile Updates** - Monitors view updates

### Environment Variables Set
```xml
DYLD_PRINT_STATISTICS = 1         # Launch time stats
MallocStackLogging = 1             # Memory debugging
LIBDISPATCH_STRICT = 1             # Concurrency checks
```

## 🔧 SwiftFormat Rules

### Key Formatting Rules
- 4-space indentation
- Trailing commas in multi-line
- Sorted imports
- Remove unnecessary self
- Consistent spacing
- Line width: 150 characters

### Usage
```bash
# Format all files
swiftformat .

# Format specific file
swiftformat path/to/file.swift

# Dry run (see what would change)
swiftformat . --dryrun
```

## 🗑️ Unused Code Detection

### Periphery Configuration
```bash
# Scan for unused code
periphery scan

# Clean build first for accurate results
periphery scan --clean-build

# Generate HTML report
periphery scan --format html > unused_code.html
```

### What It Finds
- Unused classes
- Unused structs
- Unused functions
- Unused properties
- Unused protocols

## ⏱️ Build Time Analysis

### Find Slow Files
```bash
# Run build time analysis
./Scripts/analyze_build_times.sh

# View detailed HTML report
open build_report.html
```

### Common Culprits
- Complex type inference
- Large expressions
- Heavy use of generics
- Circular dependencies

## 🚨 Danger Integration

### Automated PR Checks
- Large PR warnings (>500 lines)
- SwiftLint violations
- Print statement detection
- Force unwrap warnings
- Test coverage reminders

### Setup for CI
```yaml
# .github/workflows/danger.yml
- name: Danger
  run: |
    bundle exec danger
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## 📈 Metrics to Track

### Performance Metrics
| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| App Launch | <1s | >2s | >3s |
| Memory Usage | <100MB | >200MB | >300MB |
| View Render | <16ms | >33ms | >100ms |
| Queue Operations | <10ms | >50ms | >100ms |

### Code Quality Metrics
| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| SwiftLint Warnings | 0 | >20 | >50 |
| Force Unwraps | 0 | >10 | >50 |
| Unused Code | <5% | >10% | >20% |
| Test Coverage | >80% | <60% | <40% |

## 🎯 Best Practices

### Before Every Commit
1. Run SwiftLint: `swiftlint lint`
2. Format code: `swiftformat .`
3. Check for unused code: `periphery scan --skip-build`
4. Run tests: `cmd+U` in Xcode

### Weekly Maintenance
1. Full unused code scan: `periphery scan --clean-build`
2. Build time analysis: `./Scripts/analyze_build_times.sh`
3. Performance test suite: Run all XCTest performance tests
4. Update dependencies

### Before Release
1. Run Instruments profiling
2. Check memory leaks
3. Verify performance metrics
4. Clean up warnings

## 🐛 Troubleshooting

### SwiftLint Issues
```bash
# Too many warnings
swiftlint autocorrect

# Disable specific rule for line
// swiftlint:disable:next rule_name
```

### Build Time Issues
```bash
# Find slowest files
xcodebuild -showBuildTimingSummary

# Enable build timing in Xcode
defaults write com.apple.dt.Xcode ShowBuildOperationDuration YES
```

### Memory Issues
```bash
# Enable Malloc debugging
export MallocStackLogging=1
export MallocScribble=1

# Run with leaks tool
leaks --atExit -- ./path/to/app
```

## 📚 Resources

- [SwiftLint Rules](https://realm.github.io/SwiftLint/rule-directory.html)
- [SwiftFormat Options](https://github.com/nicklockwood/SwiftFormat/blob/master/Rules.md)
- [Periphery Documentation](https://github.com/peripheryapp/periphery)
- [Instruments User Guide](https://help.apple.com/instruments/mac/current/)
- [XCTest Performance](https://developer.apple.com/documentation/xctest/performance_tests)

## 🎉 Benefits

With all these tools in place, you'll catch:
- **UI Freezes** - Before users experience them
- **Memory Leaks** - During development
- **Performance Issues** - Through automated testing
- **Code Smells** - At commit time
- **Unused Code** - Before it accumulates
- **Build Time Issues** - As they appear

This comprehensive tooling ensures high code quality and prevents the issues that were causing your UI freezes!