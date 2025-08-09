# TDD, Testing & Safety Infrastructure Plan

## Executive Summary

This plan establishes comprehensive testing, linting, and safety infrastructure BEFORE implementing AudioStreaming. By setting up proper tooling and TDD processes first, we ensure quality and catch issues early.

---

## Day -2 to 0: Testing Infrastructure Setup (BEFORE Feature Development)

### Day -2: Code Quality Tools Installation

#### Step 1: Install SwiftLint (1 hour)
```bash
# Add to Package.swift
.package(url: "https://github.com/realm/SwiftLint.git", from: "0.54.0")

# Or via Homebrew for CI
brew install swiftlint
```

Create `.swiftlint.yml`:
```yaml
# Briefeed/.swiftlint.yml
included:
  - Briefeed
  - BriefeedTests
  - BriefeedUITests

excluded:
  - build
  - Pods
  - DerivedData
  - .build

# Rules
opt_in_rules:
  - empty_count
  - empty_string
  - closure_spacing
  - collection_alignment
  - contains_over_filter_count
  - discouraged_object_literal
  - explicit_init
  - fatal_error_message
  - first_where
  - force_unwrapping
  - implicit_return
  - implicitly_unwrapped_optional
  - last_where
  - legacy_random
  - multiline_function_chains
  - multiline_parameters
  - operator_usage_whitespace
  - overridden_super_call
  - prefer_self_type_over_type_of_self
  - redundant_nil_coalescing
  - redundant_type_annotation
  - toggle_bool
  - unneeded_parentheses_in_closure_argument
  - unused_import
  - vertical_whitespace_closing_braces
  - weak_delegate
  - yoda_condition

disabled_rules:
  - todo
  - fixme

# Configurations
line_length:
  warning: 120
  error: 200
  ignores_comments: true

type_body_length:
  warning: 300
  error: 500

file_length:
  warning: 500
  error: 1000

function_body_length:
  warning: 40
  error: 80

cyclomatic_complexity:
  warning: 10
  error: 20

force_unwrapping:
  severity: error

implicitly_unwrapped_optional:
  severity: error

custom_rules:
  no_main_thread_block:
    name: "Main Thread Blocking"
    regex: '\.value\s*\)?\s*$'
    message: "Avoid .value on Task as it blocks"
    severity: error
  
  no_singleton_observable:
    name: "Singleton ObservableObject"
    regex: 'static let shared.*ObservableObject'
    message: "Don't mix Singleton with ObservableObject"
    severity: error
  
  no_published_in_service:
    name: "Published in Service"
    regex: '@Published.*(?:Service|Manager|Controller)'
    message: "Services shouldn't have @Published properties"
    severity: warning
    
  heavy_init_check:
    name: "Heavy Init Work"
    regex: 'init\(\)[\s\S]*?(load|fetch|setup|configure)'
    message: "Consider moving heavy work out of init()"
    severity: warning
```

Add Xcode Build Phase:
```bash
# Build Phases → New Run Script Phase
if which swiftlint >/dev/null; then
  swiftlint
else
  echo "warning: SwiftLint not installed"
fi
```

#### Step 2: Install SwiftFormat (30 min)
```bash
brew install swiftformat

# Create .swiftformat configuration
cat > .swiftformat << EOF
# File options
--exclude build,DerivedData,.build,Pods

# Format options
--indent 4
--indentcase false
--trimwhitespace always
--voidtype tuple
--nospaceoperators ..<,...
--ifdef no-indent
--stripunusedargs closure-only
--maxwidth 120

# Wrapping
--wraparguments before-first
--wrapparameters before-first
--wrapcollections before-first
EOF
```

Add pre-commit hook:
```bash
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
# Format changed Swift files
git diff --staged --name-only | grep ".swift$" | while read file; do
  swiftformat "$file"
  git add "$file"
done

# Run SwiftLint
swiftlint --quiet --strict
EOF

chmod +x .git/hooks/pre-commit
```

#### Step 3: Install Periphery (30 min)
```bash
# For detecting unused code
brew install periphery

# Create configuration
cat > .periphery.yml << EOF
project: Briefeed.xcodeproj
schemes:
  - Briefeed
targets:
  - Briefeed
retain_public: true
retain_objc_accessible: true
retain_objc_annotated: true
verbose: false
EOF
```

#### Step 4: Setup Danger for PR Checks (1 hour)
Create `Dangerfile`:
```ruby
# Dangerfile
# Ensure tests are added/modified with code changes
has_app_changes = !git.modified_files.grep(/Briefeed\//).empty?
has_test_changes = !git.modified_files.grep(/Tests\//).empty?

if has_app_changes && !has_test_changes
  warn("Changes to app code should include test updates")
end

# Check for force unwrapping
git.diff.each do |chunk|
  if chunk.patch.include?("!")
    warn("Force unwrapping detected. Consider using guard or if-let")
  end
end

# SwiftLint
swiftlint.config_file = '.swiftlint.yml'
swiftlint.lint_files inline_mode: true

# Check test coverage
xcov.report(
  scheme: 'Briefeed',
  minimum_coverage_percentage: 70.0
)

# File size check
git.added_files.each do |file|
  next unless file.end_with?('.swift')
  lines = File.readlines(file).count
  if lines > 300
    warn("#{file} has #{lines} lines. Consider breaking it up.")
  end
end

# Commit message check
commit = git.commits.first
unless commit.message.match?(/^(feat|fix|docs|style|refactor|test|chore)(\(.+\))?: .+/)
  fail("Please use conventional commit format: type(scope): message")
end
```

### Day -1: Testing Framework Setup

#### Step 1: Create Testing Utilities (2 hours)
Create `BriefeedTests/TestUtilities/XCTestCase+Extensions.swift`:

```swift
import XCTest
@testable import Briefeed

extension XCTestCase {
    /// Measure initialization time and assert it's under threshold
    func assertInitTime<T>(
        of type: T.Type,
        threshold: TimeInterval = 0.01,
        file: StaticString = #file,
        line: UInt = #line,
        _ initializer: () -> T
    ) {
        let start = CFAbsoluteTimeGetCurrent()
        _ = initializer()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        XCTAssertLessThan(
            elapsed,
            threshold,
            "\(type) init took \(elapsed)s, exceeding \(threshold)s threshold",
            file: file,
            line: line
        )
    }
    
    /// Assert no main thread blocking
    func assertNoMainThreadBlock(
        timeout: TimeInterval = 0.1,
        file: StaticString = #file,
        line: UInt = #line,
        _ block: @escaping () async -> Void
    ) async {
        let expectation = XCTestExpectation(description: "Main thread responsive")
        
        Task.detached {
            await block()
            await MainActor.run {
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: timeout)
    }
    
    /// Memory leak detection
    func assertNoMemoryLeak(
        _ instance: AnyObject,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        addTeardownBlock { [weak instance] in
            XCTAssertNil(
                instance,
                "Instance should be deallocated but is still in memory",
                file: file,
                line: line
            )
        }
    }
}
```

Create `BriefeedTests/TestUtilities/MockFactory.swift`:

```swift
@testable import Briefeed

enum MockFactory {
    static func makeArticle(
        title: String = "Test Article",
        content: String = "Test content",
        author: String = "Test Author"
    ) -> Article {
        // Create mock article
    }
    
    static func makeRSSEpisode(
        title: String = "Test Episode",
        audioUrl: String = "https://example.com/audio.mp3"
    ) -> RSSEpisode {
        // Create mock episode
    }
    
    static func makeAudioURL() -> URL {
        // Return test audio file URL
        Bundle(for: BriefeedTests.self).url(
            forResource: "test-audio",
            withExtension: "mp3"
        )!
    }
}
```

#### Step 2: Create Performance Testing Suite (1 hour)
Create `BriefeedTests/Performance/PerformanceTests.swift`:

```swift
final class PerformanceTests: XCTestCase {
    
    func testServiceInitializationPerformance() {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            _ = AudioStreamingService()
        }
    }
    
    func testViewModelInitializationPerformance() {
        measure {
            _ = AudioPlayerViewModel()
        }
    }
    
    func testMainThreadResponsiveness() async {
        await assertNoMainThreadBlock {
            let service = AudioStreamingService.shared
            try? await service.initialize()
        }
    }
    
    func testMemoryUsageDuringPlayback() {
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        
        measure(metrics: [XCTMemoryMetric()], options: options) {
            // Simulate playback
            let service = AudioStreamingService.shared
            service.play(url: MockFactory.makeAudioURL())
            Thread.sleep(forTimeInterval: 5)
            service.stop()
        }
    }
}
```

#### Step 3: Create UI Testing Infrastructure (2 hours)
Create `BriefeedUITests/UITestBase.swift`:

```swift
class UITestBase: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = ["TESTING": "1"]
        app.launch()
    }
    
    func assertUIResponsive(
        timeout: TimeInterval = 1.0,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let start = CFAbsoluteTimeGetCurrent()
        let testButton = app.buttons.firstMatch
        XCTAssertTrue(
            testButton.waitForExistence(timeout: timeout),
            "UI not responsive within \(timeout)s",
            file: file,
            line: line
        )
        let responseTime = CFAbsoluteTimeGetCurrent() - start
        XCTAssertLessThan(
            responseTime,
            0.1,
            "UI response time \(responseTime)s exceeds 100ms",
            file: file,
            line: line
        )
    }
    
    func measureAppLaunchTime() -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 5)
        return CFAbsoluteTimeGetCurrent() - start
    }
}
```

#### Step 4: Setup Snapshot Testing (1 hour)
```bash
# Add SnapshotTesting package
# In Package.swift:
.package(url: "https://github.com/pointfreeco/swift-snapshot-testing.git", from: "1.15.0")
```

Create `BriefeedTests/Snapshots/SnapshotTests.swift`:

```swift
import SnapshotTesting
import SwiftUI
@testable import Briefeed

final class SnapshotTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // isRecording = true  // Uncomment to record new snapshots
    }
    
    func testMiniAudioPlayerSnapshot() {
        let view = MiniAudioPlayer()
            .environmentObject(AudioPlayerViewModel())
        
        assertSnapshot(matching: view, as: .image(layout: .device(config: .iPhone13)))
    }
    
    func testAudioPlayerStates() {
        let viewModel = AudioPlayerViewModel()
        
        // Playing state
        viewModel.isPlaying = true
        viewModel.currentTitle = "Test Article"
        assertSnapshot(
            matching: MiniAudioPlayer().environmentObject(viewModel),
            as: .image(),
            named: "playing"
        )
        
        // Paused state
        viewModel.isPlaying = false
        assertSnapshot(
            matching: MiniAudioPlayer().environmentObject(viewModel),
            as: .image(),
            named: "paused"
        )
    }
}
```

### Day 0: TDD Process & Safety Checks

#### Step 1: Create TDD Test Templates (1 hour)
Create `BriefeedTests/TDD/AudioStreamingServiceTests.swift`:

```swift
// WRITTEN BEFORE IMPLEMENTATION (TDD)
final class AudioStreamingServiceTests: XCTestCase {
    
    // MARK: - Initialization Tests (Written First)
    
    func testServiceInitializationIsLightweight() {
        assertInitTime(of: AudioStreamingService.self) {
            AudioStreamingService()
        }
    }
    
    func testServiceDoesNotBlockMainThread() async {
        await assertNoMainThreadBlock {
            let service = AudioStreamingService.shared
            try? await service.initialize()
        }
    }
    
    func testServiceIsNotObservableObject() {
        // This should NOT compile if service is ObservableObject
        let service = AudioStreamingService.shared
        XCTAssertFalse(service is ObservableObject)
    }
    
    // MARK: - Playback Tests (Written Before Implementation)
    
    func testPlayWithURL() {
        // Given
        let service = AudioStreamingService.shared
        let testURL = MockFactory.makeAudioURL()
        
        // When
        service.play(url: testURL)
        
        // Then
        XCTAssertEqual(service.currentURL, testURL)
        XCTAssertTrue(service.isPlaying)
    }
    
    func testSpeedControl() {
        // Given
        let service = AudioStreamingService.shared
        let speeds: [Float] = [0.5, 1.0, 1.5, 2.0, 3.0, 4.0]
        
        for speed in speeds {
            // When
            service.setRate(speed)
            
            // Then
            XCTAssertEqual(service.playbackRate, speed, accuracy: 0.01)
        }
    }
    
    func testPauseAndResume() {
        // Given
        let service = AudioStreamingService.shared
        service.play(url: MockFactory.makeAudioURL())
        
        // When
        service.pause()
        
        // Then
        XCTAssertFalse(service.isPlaying)
        
        // When
        service.resume()
        
        // Then
        XCTAssertTrue(service.isPlaying)
    }
    
    // MARK: - Memory Management Tests
    
    func testServiceDoesNotLeak() {
        var service: AudioStreamingService? = AudioStreamingService()
        assertNoMemoryLeak(service!)
        service = nil
    }
}
```

Create `BriefeedTests/TDD/AudioPlayerViewModelTests.swift`:

```swift
// TDD: Tests written BEFORE ViewModel implementation
final class AudioPlayerViewModelTests: XCTestCase {
    
    func testViewModelInitIsLightweight() {
        assertInitTime(of: AudioPlayerViewModel.self) {
            AudioPlayerViewModel()
        }
    }
    
    func testViewModelIsMainActor() {
        let viewModel = AudioPlayerViewModel()
        // Should be @MainActor
        XCTAssertTrue(viewModel is ObservableObject)
    }
    
    func testViewModelDoesNotAccessServiceInInit() {
        // Init should not crash even if service doesn't exist
        let viewModel = AudioPlayerViewModel()
        XCTAssertNotNil(viewModel)
        // Service should not be connected yet
        XCTAssertFalse(viewModel.isConnected)
    }
    
    func testPublishedPropertiesUpdate() async {
        // Given
        let viewModel = AudioPlayerViewModel()
        let expectation = XCTestExpectation(description: "Published update")
        
        let cancellable = viewModel.$isPlaying.sink { _ in
            expectation.fulfill()
        }
        
        // When
        await viewModel.connect()
        viewModel.play()
        
        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        cancellable.cancel()
    }
}
```

#### Step 2: Create Safety Check Utilities (2 hours)
Create `Briefeed/Core/Utilities/SafetyChecks.swift`:

```swift
import Foundation
import os.log

/// Runtime safety checks for development
enum SafetyCheck {
    private static let logger = Logger(subsystem: "com.briefeed", category: "safety")
    
    /// Check if running on main thread when shouldn't be
    static func assertNotMainThread(
        function: String = #function,
        file: String = #file,
        line: Int = #line
    ) {
        #if DEBUG
        if Thread.isMainThread {
            let message = "⚠️ \(function) called on main thread at \(file):\(line)"
            logger.error("\(message)")
            assertionFailure(message)
        }
        #endif
    }
    
    /// Check if NOT running on main thread when should be
    static func assertMainThread(
        function: String = #function,
        file: String = #file,
        line: Int = #line
    ) {
        #if DEBUG
        if !Thread.isMainThread {
            let message = "⚠️ \(function) called off main thread at \(file):\(line)"
            logger.error("\(message)")
            assertionFailure(message)
        }
        #endif
    }
    
    /// Detect potential infinite loops
    static func checkInfiniteLoop(
        counter: inout Int,
        threshold: Int = 1000,
        function: String = #function
    ) {
        #if DEBUG
        counter += 1
        if counter > threshold {
            let message = "⚠️ Potential infinite loop in \(function)"
            logger.error("\(message)")
            assertionFailure(message)
        }
        #endif
    }
    
    /// Measure and warn about slow operations
    static func measureOperation<T>(
        _ operation: () throws -> T,
        threshold: TimeInterval = 0.016, // One frame at 60fps
        name: String
    ) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try operation()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        #if DEBUG
        if elapsed > threshold {
            logger.warning("⚠️ Slow operation '\(name)' took \(elapsed)s")
        }
        #endif
        
        return result
    }
}
```

Create `Briefeed/Core/Utilities/MainThreadMonitor.swift`:

```swift
import Foundation

/// Monitors main thread for blocking operations
final class MainThreadMonitor {
    static let shared = MainThreadMonitor()
    
    private var timer: Timer?
    private var lastPing = Date()
    private let threshold: TimeInterval = 0.1 // 100ms
    
    func startMonitoring() {
        #if DEBUG
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            let now = Date()
            let elapsed = now.timeIntervalSince(self.lastPing)
            
            if elapsed > self.threshold {
                print("🔴 MAIN THREAD BLOCKED for \(elapsed)s")
                // Could also send to analytics
            }
            
            self.lastPing = now
        }
        #endif
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}
```

#### Step 3: Create GitHub Actions CI/CD (1 hour)
Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  lint:
    runs-on: macos-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Install SwiftLint
      run: brew install swiftlint
    
    - name: Run SwiftLint
      run: swiftlint --strict --reporter github-actions-logging
  
  format:
    runs-on: macos-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Install SwiftFormat
      run: brew install swiftformat
    
    - name: Check Formatting
      run: swiftformat --lint .
  
  test:
    runs-on: macos-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Select Xcode
      run: sudo xcode-select -s /Applications/Xcode_15.0.app
    
    - name: Build
      run: |
        xcodebuild build-for-testing \
          -scheme Briefeed \
          -destination 'platform=iOS Simulator,name=iPhone 15'
    
    - name: Test
      run: |
        xcodebuild test-without-building \
          -scheme Briefeed \
          -destination 'platform=iOS Simulator,name=iPhone 15' \
          -enableCodeCoverage YES
    
    - name: Upload Coverage
      run: |
        bash <(curl -s https://codecov.io/bash)
  
  performance:
    runs-on: macos-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Run Performance Tests
      run: |
        xcodebuild test \
          -scheme Briefeed \
          -only-testing:BriefeedTests/PerformanceTests \
          -destination 'platform=iOS Simulator,name=iPhone 15'
    
    - name: Check Unused Code
      run: |
        brew install periphery
        periphery scan --strict
```

#### Step 4: Create Testing Documentation (1 hour)
Create `docs/TESTING-GUIDE.md`:

```markdown
# Testing Guide

## TDD Process

### 1. Red Phase - Write Failing Test First
```swift
func testNewFeature() {
    // Given
    let service = AudioStreamingService.shared
    
    // When
    let result = service.newFeature() // Doesn't exist yet
    
    // Then
    XCTAssertEqual(result, expectedValue)
}
```

### 2. Green Phase - Minimal Implementation
```swift
func newFeature() -> ResultType {
    return expectedValue // Simplest thing that makes test pass
}
```

### 3. Refactor Phase - Improve Code
- Clean up implementation
- Remove duplication
- Improve performance
- All tests must still pass

## Test Coverage Requirements

- **Minimum**: 70% overall
- **Critical paths**: 90% (audio playback, queue)
- **New code**: 85%
- **UI Components**: Snapshot tests required

## Running Tests

### Local Development
```bash
# All tests
xcodebuild test -scheme Briefeed

# Specific test file
xcodebuild test -scheme Briefeed -only-testing:BriefeedTests/AudioStreamingServiceTests

# With coverage
xcodebuild test -scheme Briefeed -enableCodeCoverage YES

# Performance tests only
xcodebuild test -scheme Briefeed -only-testing:BriefeedTests/PerformanceTests
```

### Pre-Commit Checks
```bash
# Runs automatically via git hook
# Manual run:
./scripts/pre-commit-checks.sh
```

### CI/CD
- Runs on every PR
- Must pass before merge
- Coverage reports posted to PR

## Test Categories

### Unit Tests
- Service logic
- ViewModels
- Models
- Utilities

### Integration Tests
- Service interactions
- Data flow
- Queue persistence

### UI Tests
- User flows
- Tab navigation
- Audio controls
- No freezes

### Performance Tests
- Init times < 10ms
- Memory usage < 150MB
- No main thread blocks
- 60fps maintained

### Snapshot Tests
- UI components
- Different states
- Dark/light mode
- Device sizes

## Safety Checks

### Runtime Assertions
```swift
SafetyCheck.assertMainThread()
SafetyCheck.assertNotMainThread()
SafetyCheck.measureOperation({ 
    // code
}, threshold: 0.016, name: "Operation")
```

### Memory Leak Detection
```swift
func testNoMemoryLeak() {
    var object: MyClass? = MyClass()
    assertNoMemoryLeak(object!)
    object = nil
}
```

### Main Thread Monitoring
```swift
// In AppDelegate
MainThreadMonitor.shared.startMonitoring()
```

## Code Quality Metrics

### SwiftLint Rules
- No force unwrapping
- No singleton ObservableObject
- No @Published in services
- No heavy init work
- Max line length: 120
- Max file length: 500

### Required Checks
- [ ] Tests pass
- [ ] Coverage > 70%
- [ ] SwiftLint clean
- [ ] SwiftFormat clean
- [ ] No unused code
- [ ] Performance tests pass
- [ ] Snapshot tests pass
```

---

## Integration with Implementation Plan

### How This Integrates with Each Day

#### Day 1-2: Architecture Foundation
**TDD Approach:**
1. Write service interface tests FIRST
2. Tests define the contract
3. Implementation follows tests
4. Safety checks prevent anti-patterns

```swift
// Write this test BEFORE creating service
func testServiceArchitecture() {
    // Service must be plain singleton
    XCTAssertFalse(AudioStreamingService.shared is ObservableObject)
    
    // Init must be lightweight
    assertInitTime(of: AudioStreamingService.self)
    
    // Must have async initialize
    let service = AudioStreamingService.shared
    XCTAssertTrue(service.responds(to: #selector(initialize)))
}
```

#### Day 3-5: AudioStreaming Integration
**Test-First Implementation:**
1. Write playback tests
2. Write speed control tests
3. Implement to pass tests
4. Refactor with safety

```swift
// Day 3: Write these tests FIRST
class AudioPlaybackTests: XCTestCase {
    func testPlaybackSpeed4x() {
        // Test MUST pass before feature is done
        service.setRate(4.0)
        XCTAssertEqual(service.playbackRate, 4.0)
    }
}
```

#### Day 6-7: Queue Management
**TDD Queue Implementation:**
```swift
// Write queue tests BEFORE implementation
func testQueuePersistence() {
    // Given
    let service = QueueServiceV3.shared
    service.addToQueue(item)
    
    // When
    app.terminate()
    app.launch()
    
    // Then
    XCTAssertEqual(service.queue.count, 1)
}
```

#### Day 8-10: Testing & Polish
**Continuous Validation:**
- All tests must pass
- Performance benchmarks met
- Coverage requirements satisfied
- Safety checks clean

---

## Enforcement Strategy

### Pre-Commit Hooks
```bash
#!/bin/bash
# .git/hooks/pre-commit

# 1. Format code
swiftformat .

# 2. Lint
if ! swiftlint --strict; then
    echo "❌ SwiftLint failed"
    exit 1
fi

# 3. Run tests
if ! xcodebuild test -scheme Briefeed; then
    echo "❌ Tests failed"
    exit 1
fi

# 4. Check coverage
coverage=$(xcov --scheme Briefeed --json | jq '.coverage')
if (( $(echo "$coverage < 70" | bc -l) )); then
    echo "❌ Coverage below 70%"
    exit 1
fi

echo "✅ All checks passed"
```

### PR Requirements
- [ ] All CI checks pass
- [ ] Test coverage > 70%
- [ ] No SwiftLint violations
- [ ] Performance tests pass
- [ ] Code review approved
- [ ] Snapshot tests updated if UI changed

### Definition of Done
A feature is only "done" when:
1. Tests written (TDD)
2. Implementation complete
3. Tests pass
4. Coverage adequate
5. Linting clean
6. Performance validated
7. Safety checks pass
8. Documentation updated
9. PR approved

---

## Benefits of This Approach

### Quality Assurance
- Bugs caught early (TDD)
- Consistent code style (SwiftLint)
- Performance guaranteed (Tests)
- No regressions (CI/CD)

### Developer Confidence
- Safe refactoring (Tests)
- Clear requirements (TDD)
- Fast feedback (Pre-commit)
- Automated checks (CI)

### Project Health
- Maintainable code
- Living documentation (Tests)
- Performance tracking
- Technical debt prevention

---

## Quick Start Commands

```bash
# Setup everything
./scripts/setup-testing-infrastructure.sh

# Run all checks locally
./scripts/run-all-checks.sh

# TDD workflow
./scripts/tdd-watch.sh  # Watches files and runs tests

# Before committing
./scripts/pre-commit-checks.sh

# Generate coverage report
./scripts/coverage-report.sh
```

This infrastructure ensures that the AudioStreaming implementation is built on a solid foundation of tests, safety checks, and quality controls from day one.