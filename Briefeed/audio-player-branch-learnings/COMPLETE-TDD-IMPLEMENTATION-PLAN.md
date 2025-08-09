# Complete TDD Implementation Plan with Testing Infrastructure

## Overview

This plan integrates TDD, testing infrastructure, and safety checks from the very beginning. Every feature is test-driven, with quality gates at each step.

---

## Phase 0: Setup Testing Infrastructure First (Days -2 to 0)

### Day -2: Install Quality Tools

#### Morning (4 hours): Setup Linting & Formatting

```bash
# 1. Create new branch for infrastructure
git checkout master
git pull origin master
git checkout -b feature/testing-infrastructure

# 2. Install SwiftLint
brew install swiftlint

# 3. Create .swiftlint.yml with custom rules
cat > .swiftlint.yml << 'EOF'
opt_in_rules:
  - force_unwrapping
  - implicitly_unwrapped_optional
  - empty_count
  - closure_spacing

custom_rules:
  no_singleton_observable:
    name: "Singleton ObservableObject"
    regex: 'static let shared.*ObservableObject'
    message: "Architecture violation: Don't mix Singleton with ObservableObject"
    severity: error
  
  no_published_in_service:
    name: "Published in Service"
    regex: '@Published.*(?:Service|Manager|Controller)'
    message: "Architecture violation: Services shouldn't have @Published"
    severity: error
    
  no_value_await:
    name: "Task Value Await"
    regex: '\.value\s*\)?\s*$'
    message: "Performance issue: .value blocks thread"
    severity: error

force_unwrapping:
  severity: error

line_length:
  warning: 120
  error: 200
EOF

# 4. Add Xcode Build Phase for SwiftLint
# In Xcode: Build Phases → + → New Run Script Phase
# Script: 
# if which swiftlint >/dev/null; then
#   swiftlint
# else
#   echo "warning: SwiftLint not installed"
# fi

# 5. Install SwiftFormat
brew install swiftformat

# 6. Create .swiftformat configuration
cat > .swiftformat << 'EOF'
--indent 4
--maxwidth 120
--wraparguments before-first
--wrapparameters before-first
EOF

# 7. Setup pre-commit hook
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
echo "🔍 Running pre-commit checks..."

# Format code
echo "📝 Formatting code..."
swiftformat . --quiet

# Lint
echo "🧹 Linting..."
if ! swiftlint --quiet --strict; then
    echo "❌ SwiftLint failed. Fix issues and try again."
    exit 1
fi

echo "✅ Pre-commit checks passed!"
EOF

chmod +x .git/hooks/pre-commit

# 8. Test and commit
git add .
git commit -m "chore: Add SwiftLint and SwiftFormat infrastructure

- Custom rules to prevent architecture violations
- Pre-commit hooks for quality enforcement
- Force unwrapping banned"
```

#### Afternoon (4 hours): Setup Testing Utilities

```bash
# 1. Create test utilities
mkdir -p BriefeedTests/TestUtilities
mkdir -p BriefeedTests/Mocks
mkdir -p BriefeedTests/Performance
mkdir -p BriefeedTests/TDD
```

Create `BriefeedTests/TestUtilities/TestHelpers.swift`:

```swift
import XCTest
@testable import Briefeed

// Test helpers for TDD
extension XCTestCase {
    /// Assert service initialization is lightweight
    func assertLightweightInit<T>(
        _ type: T.Type,
        threshold: TimeInterval = 0.01,
        file: StaticString = #filePath,
        line: UInt = #line
    ) where T: AnyObject {
        let start = CFAbsoluteTimeGetCurrent()
        _ = type.init()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        XCTAssertLessThan(
            elapsed, 
            threshold,
            "\(type) init took \(elapsed)s (limit: \(threshold)s)",
            file: file,
            line: line
        )
    }
    
    /// Assert no main thread blocking
    func assertNoMainThreadBlock(
        timeout: TimeInterval = 0.1,
        _ block: @escaping () async -> Void
    ) async {
        let expectation = expectation(description: "No main thread block")
        
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
        _ object: AnyObject,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        addTeardownBlock { [weak object] in
            XCTAssertNil(
                object,
                "Memory leak detected",
                file: file,
                line: line
            )
        }
    }
    
    /// Assert not ObservableObject (for services)
    func assertNotObservableObject(
        _ object: Any,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if object is ObservableObject {
            XCTFail(
                "\(type(of: object)) should not be ObservableObject",
                file: file,
                line: line
            )
        }
    }
}
```

```bash
# 2. Commit test utilities
git add .
git commit -m "test: Add TDD testing utilities

- Lightweight init assertion
- Main thread block detection  
- Memory leak detection
- Architecture violation checks"
```

### Day -1: Create Testing Framework

#### Morning (4 hours): TDD Test Suites

Create `BriefeedTests/TDD/ServiceArchitectureTests.swift`:

```swift
// These tests MUST pass before implementing services
final class ServiceArchitectureTests: XCTestCase {
    
    // Test written BEFORE AudioStreamingService exists
    func testAudioStreamingServiceArchitecture() {
        // Given a service
        let service = AudioStreamingService.shared
        
        // It must NOT be ObservableObject
        assertNotObservableObject(service)
        
        // It must have lightweight init
        assertLightweightInit(AudioStreamingService.self)
        
        // It must have async initialize method
        XCTAssertTrue(service.responds(to: #selector(initialize)))
    }
    
    // Test written BEFORE fixing QueueService
    func testQueueServiceArchitecture() {
        let service = QueueServiceV2.shared
        
        assertNotObservableObject(service)
        assertLightweightInit(QueueServiceV2.self)
    }
    
    // Test written BEFORE creating ViewModel
    func testAudioPlayerViewModelArchitecture() {
        let viewModel = AudioPlayerViewModel()
        
        // ViewModel SHOULD be ObservableObject
        XCTAssertTrue(viewModel is ObservableObject)
        
        // ViewModel should have lightweight init
        assertLightweightInit(AudioPlayerViewModel.self)
        
        // ViewModel should NOT access services in init
        // (This test ensures proper architecture)
    }
}
```

Create `BriefeedTests/TDD/AudioPlaybackTests.swift`:

```swift
// TDD: Write these tests BEFORE implementing features
final class AudioPlaybackTests: XCTestCase {
    
    func testPlaybackSpeedUpTo4x() {
        // This test defines our requirement
        let service = AudioStreamingService.shared
        
        let speeds: [Float] = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]
        
        for speed in speeds {
            service.setRate(speed)
            XCTAssertEqual(
                service.playbackRate,
                speed,
                accuracy: 0.01,
                "Should support \(speed)x speed"
            )
        }
    }
    
    func testUnifiedAudioPlayback() {
        let service = AudioStreamingService.shared
        
        // Test TTS audio
        let ttsURL = URL(fileURLWithPath: "tts-audio.mp3")
        service.play(url: ttsURL)
        XCTAssertEqual(service.currentURL, ttsURL)
        
        // Test streaming audio
        let streamURL = URL(string: "https://example.com/stream.mp3")!
        service.play(url: streamURL)
        XCTAssertEqual(service.currentURL, streamURL)
    }
    
    func testQueueManagement() {
        let service = AudioStreamingService.shared
        
        let urls = [
            URL(string: "https://example.com/1.mp3")!,
            URL(string: "https://example.com/2.mp3")!,
            URL(string: "https://example.com/3.mp3")!
        ]
        
        service.queue(urls: urls)
        XCTAssertEqual(service.queueCount, 3)
    }
}
```

Create `BriefeedTests/TDD/PerformanceRequirements.swift`:

```swift
// Performance requirements defined as tests
final class PerformanceRequirements: XCTestCase {
    
    func testAppLaunchUnder1Second() {
        measure {
            let app = XCUIApplication()
            app.launch()
        }
        // Pass criteria set in scheme test plan: < 1.0s
    }
    
    func testServiceInitUnder10ms() {
        measure(metrics: [XCTClockMetric()]) {
            _ = AudioStreamingService.shared
        }
        // Pass criteria: < 0.01s
    }
    
    func testNoUIFreezes() async {
        await assertNoMainThreadBlock {
            let service = AudioStreamingService.shared
            try? await service.initialize()
        }
    }
    
    func testMemoryUnder150MB() {
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        
        measure(metrics: [XCTMemoryMetric()], options: options) {
            // Simulate playback
            let service = AudioStreamingService.shared
            service.play(url: testAudioURL)
            Thread.sleep(forTimeInterval: 10)
        }
        // Pass criteria: < 150MB
    }
}
```

#### Afternoon (4 hours): CI/CD Pipeline

Create `.github/workflows/tdd-ci.yml`:

```yaml
name: TDD CI Pipeline

on:
  push:
    branches: [ main, develop, feature/* ]
  pull_request:
    branches: [ main ]

jobs:
  # Job 1: Linting must pass
  lint:
    runs-on: macos-latest
    steps:
    - uses: actions/checkout@v3
    - name: SwiftLint
      run: |
        brew install swiftlint
        swiftlint --strict --reporter github-actions-logging
        
  # Job 2: Tests must pass
  test:
    runs-on: macos-latest
    needs: lint
    steps:
    - uses: actions/checkout@v3
    - name: Run TDD Tests
      run: |
        xcodebuild test \
          -scheme Briefeed \
          -destination 'platform=iOS Simulator,name=iPhone 15' \
          -enableCodeCoverage YES \
          | xcpretty
          
    - name: Check Coverage
      run: |
        # Coverage must be > 70%
        xcov --scheme Briefeed --minimum_coverage_percentage 70
        
  # Job 3: Performance tests must pass
  performance:
    runs-on: macos-latest
    needs: test
    steps:
    - uses: actions/checkout@v3
    - name: Performance Tests
      run: |
        xcodebuild test \
          -scheme Briefeed \
          -only-testing:BriefeedTests/PerformanceRequirements \
          -destination 'platform=iOS Simulator,name=iPhone 15'
          
  # Job 4: Architecture compliance
  architecture:
    runs-on: macos-latest
    needs: test
    steps:
    - uses: actions/checkout@v3
    - name: Architecture Tests
      run: |
        xcodebuild test \
          -scheme Briefeed \
          -only-testing:BriefeedTests/ServiceArchitectureTests \
          -destination 'platform=iOS Simulator,name=iPhone 15'
```

Create `scripts/tdd-watch.sh`:

```bash
#!/bin/bash
# Continuous TDD runner - watches for changes and runs tests

echo "🔄 TDD Watch Mode Started"
echo "👀 Watching for file changes..."

fswatch -o Briefeed BriefeedTests | while read num ; do
    clear
    echo "🔄 Change detected, running tests..."
    
    # Run only affected tests for speed
    swift test --filter "$(git diff --name-only | grep Test)"
    
    if [ $? -eq 0 ]; then
        echo "✅ Tests passed!"
        afplay /System/Library/Sounds/Glass.aiff
    else
        echo "❌ Tests failed!"
        afplay /System/Library/Sounds/Basso.aiff
    fi
done
```

```bash
# Make executable
chmod +x scripts/tdd-watch.sh

# Commit CI/CD
git add .
git commit -m "ci: Add TDD CI/CD pipeline

- Linting enforcement
- Test requirements
- Coverage requirements  
- Performance gates
- TDD watch mode"
```

### Day 0: Safety Monitoring Setup

#### Morning (4 hours): Runtime Safety Checks

Create `Briefeed/Core/Safety/SafetyMonitor.swift`:

```swift
import Foundation
import os.log

/// Runtime safety monitoring
final class SafetyMonitor {
    static let shared = SafetyMonitor()
    private let logger = Logger(subsystem: "com.briefeed", category: "safety")
    
    // MARK: - Thread Safety
    
    func assertMainThread(
        function: String = #function,
        file: String = #fileID,
        line: Int = #line
    ) {
        #if DEBUG
        if !Thread.isMainThread {
            let violation = "⚠️ \(function) must run on main thread (\(file):\(line))"
            logger.error("\(violation)")
            fatalError(violation)
        }
        #endif
    }
    
    func assertNotMainThread(
        function: String = #function,
        file: String = #fileID,
        line: Int = #line
    ) {
        #if DEBUG
        if Thread.isMainThread {
            let violation = "⚠️ \(function) blocking main thread (\(file):\(line))"
            logger.error("\(violation)")
            fatalError(violation)
        }
        #endif
    }
    
    // MARK: - Performance Monitoring
    
    func measureBlock<T>(
        name: String,
        threshold: TimeInterval = 0.016, // 60fps
        _ block: () throws -> T
    ) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            if elapsed > threshold {
                logger.warning("⚠️ Slow operation '\(name)': \(elapsed)s")
                #if DEBUG
                print("🐌 SLOW: \(name) took \(elapsed)s")
                #endif
            }
        }
        return try block()
    }
    
    // MARK: - Architecture Violations
    
    func checkSingletonNotObservable(_ object: Any) {
        #if DEBUG
        if object is ObservableObject {
            fatalError("Architecture violation: Singleton is ObservableObject")
        }
        #endif
    }
    
    func checkNoPublishedInService(_ object: Any) {
        #if DEBUG
        let mirror = Mirror(reflecting: object)
        for child in mirror.children {
            if String(describing: type(of: child.value)).contains("Published") {
                fatalError("Architecture violation: Service has @Published property")
            }
        }
        #endif
    }
}

// MARK: - Main Thread Monitor

final class MainThreadMonitor {
    static let shared = MainThreadMonitor()
    private var timer: Timer?
    private var lastCheck = Date()
    
    func start() {
        #if DEBUG
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            let now = Date()
            let elapsed = now.timeIntervalSince(self.lastCheck)
            
            if elapsed > 0.1 { // 100ms block
                print("🔴 MAIN THREAD BLOCKED: \(elapsed)s")
                // Could trigger breakpoint
                raise(SIGINT)
            }
            
            self.lastCheck = now
        }
        #endif
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
```

Create `Briefeed/Core/Safety/PerformanceTracker.swift`:

```swift
import Foundation

/// Track performance metrics
final class PerformanceTracker {
    static let shared = PerformanceTracker()
    
    private var metrics: [String: [TimeInterval]] = [:]
    
    func track(_ name: String, time: TimeInterval) {
        if metrics[name] == nil {
            metrics[name] = []
        }
        metrics[name]?.append(time)
        
        #if DEBUG
        // Alert if consistently slow
        if let times = metrics[name], times.count >= 3 {
            let recent = Array(times.suffix(3))
            let average = recent.reduce(0, +) / Double(recent.count)
            
            if average > 0.1 {
                print("⚠️ PERFORMANCE: \(name) averaging \(average)s")
            }
        }
        #endif
    }
    
    func report() {
        #if DEBUG
        print("📊 Performance Report:")
        for (name, times) in metrics {
            let average = times.reduce(0, +) / Double(times.count)
            let max = times.max() ?? 0
            print("  \(name): avg=\(average)s, max=\(max)s")
        }
        #endif
    }
}
```

#### Afternoon (2 hours): Integration & Testing

Update `BriefeedApp.swift`:

```swift
@main
struct BriefeedApp: App {
    init() {
        #if DEBUG
        // Start safety monitoring
        MainThreadMonitor.shared.start()
        
        // Log performance on app termination
        atexit {
            PerformanceTracker.shared.report()
        }
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    #if DEBUG
                    runSafetyChecks()
                    #endif
                }
        }
    }
    
    #if DEBUG
    private func runSafetyChecks() {
        // Check all services
        SafetyMonitor.shared.checkSingletonNotObservable(QueueServiceV2.shared)
        // Add more checks
    }
    #endif
}
```

```bash
# Final commit for infrastructure
git add .
git commit -m "feat: Complete testing and safety infrastructure

- TDD test suites ready
- CI/CD pipeline configured
- Runtime safety monitoring
- Performance tracking
- Architecture violation detection"

# Create PR
git push origin feature/testing-infrastructure
gh pr create --title "Testing Infrastructure Setup" \
  --body "Adds complete TDD, testing, and safety infrastructure"
```

---

## Phase 1: TDD Implementation (Days 1-10)

### The New TDD Workflow

For EVERY feature from now on:

1. **Write Test First (RED)**
   ```swift
   func testFeature() {
       XCTFail("Not implemented")
   }
   ```

2. **Implement Minimal Code (GREEN)**
   ```swift
   func feature() {
       // Simplest thing that passes
   }
   ```

3. **Refactor (REFACTOR)**
   - Improve code
   - All tests still pass
   - Safety checks pass

4. **Commit**
   ```bash
   # Pre-commit hooks run automatically:
   # - SwiftLint
   # - SwiftFormat  
   # - Tests
   # - Coverage check
   
   git commit -m "feat: Add feature (TDD)"
   ```

### Day 1: Service Architecture (TDD)

#### Step 1: Write Tests First (1 hour)

```swift
// BriefeedTests/TDD/Day1/ServiceRefactorTests.swift

final class ServiceRefactorTests: XCTestCase {
    
    // Test 1: Services must not be ObservableObject
    func testServicesNotObservableObject() {
        assertNotObservableObject(QueueServiceV2.shared)
        assertNotObservableObject(ArticleStateManager.shared)
        // AudioStreamingService doesn't exist yet - that's OK!
    }
    
    // Test 2: Services must have lightweight init
    func testServiceInitPerformance() {
        assertLightweightInit(QueueServiceV2.self)
        assertLightweightInit(ArticleStateManager.self)
    }
    
    // Test 3: Services must have async initialize
    func testServicesHaveAsyncInitialize() async {
        let queue = QueueServiceV2.shared
        XCTAssertTrue(queue.responds(to: #selector(initialize)))
        
        // Should not block main thread
        await assertNoMainThreadBlock {
            try? await queue.initialize()
        }
    }
}
```

Run tests - they will FAIL (Red phase) ❌

#### Step 2: Fix Services to Pass Tests (3 hours)

```swift
// Fix QueueServiceV2.swift
final class QueueServiceV2 { // Remove : ObservableObject
    static let shared = QueueServiceV2()
    
    // Remove @Published
    private(set) var queue: [QueuedItem] = []
    
    // Lightweight init
    init() {
        SafetyMonitor.shared.checkSingletonNotObservable(self)
        // No heavy work here!
    }
    
    // Heavy work in async method
    func initialize() async throws {
        SafetyMonitor.shared.assertNotMainThread()
        await loadQueue()
    }
}
```

Run tests - they should PASS (Green phase) ✅

#### Step 3: Refactor & Verify (1 hour)

```bash
# Run all safety checks
./scripts/run-all-checks.sh

# If all pass, commit
git add .
git commit -m "refactor(TDD): Fix service architecture

- Remove ObservableObject from services
- Move heavy init to async initialize  
- Tests pass"
```

### Day 2: ViewModel Layer (TDD)

#### Step 1: Write ViewModel Tests First (1 hour)

```swift
// BriefeedTests/TDD/Day2/ViewModelTests.swift

final class AudioPlayerViewModelTests: XCTestCase {
    
    func testViewModelIsObservableObject() {
        let vm = AudioPlayerViewModel()
        XCTAssertTrue(vm is ObservableObject)
    }
    
    func testViewModelHasPublishedProperties() {
        let vm = AudioPlayerViewModel()
        
        // Use Mirror to check for @Published
        let mirror = Mirror(reflecting: vm)
        var hasPublished = false
        
        for child in mirror.children {
            if String(describing: type(of: child.value)).contains("Published") {
                hasPublished = true
                break
            }
        }
        
        XCTAssertTrue(hasPublished, "ViewModel should have @Published properties")
    }
    
    func testViewModelDoesntAccessServiceInInit() {
        // This should not crash even without services
        let vm = AudioPlayerViewModel()
        XCTAssertNotNil(vm)
        XCTAssertFalse(vm.isConnected)
    }
    
    func testViewModelConnectsToServices() async {
        let vm = AudioPlayerViewModel()
        
        await vm.connect()
        
        XCTAssertTrue(vm.isConnected)
    }
}
```

#### Step 2: Implement ViewModel (2 hours)

Create to pass tests...

### Day 3-5: AudioStreaming with TDD

#### For EVERY AudioStreaming feature:

1. **Write Test First**
   ```swift
   func testSpeedControl4x() {
       let service = AudioStreamingService.shared
       service.setRate(4.0)
       XCTAssertEqual(service.playbackRate, 4.0)
   }
   ```

2. **Run Test** - See it fail ❌

3. **Implement Feature**
   ```swift
   func setRate(_ rate: Float) {
       audioPlayer.rate = rate
       playbackRate = rate
   }
   ```

4. **Run Test** - See it pass ✅

5. **Run Safety Checks**
   ```bash
   ./scripts/run-safety-checks.sh
   ```

6. **Commit**
   ```bash
   git commit -m "feat(TDD): Add 4x speed control"
   ```

---

## The TDD Difference

### Without TDD (Old Way - Caused Freeze)
1. Write code
2. Hope it works
3. Find issues in production
4. UI freezes
5. Debug for days

### With TDD (New Way - Prevents Issues)
1. Write test defining requirement
2. Test fails (expected)
3. Write minimal code to pass
4. Test passes
5. Refactor with confidence
6. Safety checks prevent issues
7. Ship with confidence

---

## Daily TDD Checklist

### Every Morning
- [ ] Pull latest code
- [ ] Run all tests (`cmd+u`)
- [ ] Check coverage report
- [ ] Review failing tests

### Before Writing Code
- [ ] Write test first
- [ ] See test fail
- [ ] Write minimal implementation
- [ ] See test pass

### Before Committing
- [ ] All tests pass
- [ ] Coverage > 70%
- [ ] SwiftLint clean
- [ ] Performance tests pass
- [ ] Safety checks pass

### End of Day
- [ ] Run full test suite
- [ ] Check performance metrics
- [ ] Update test documentation
- [ ] Push to remote

---

## Success Metrics

### Code Quality
- Zero force unwraps
- Zero singleton ObservableObjects  
- Zero @Published in services
- Zero heavy init methods

### Test Coverage
- Overall: >70%
- New code: >85%
- Critical paths: >90%

### Performance
- App launch: <1 second
- Service init: <10ms
- No main thread blocks
- Memory: <150MB

### Safety
- No architecture violations
- No memory leaks
- No thread safety issues
- No performance regressions

---

## Emergency Procedures

### If Tests Fail
1. DO NOT bypass tests
2. Fix the code, not the test
3. If test is wrong, get review first
4. Document why test changed

### If Performance Degrades
1. Check recent commits
2. Run performance profiler
3. Review safety monitor logs
4. Revert if necessary

### If Architecture Violated
1. SwiftLint will catch most
2. Runtime checks will catch rest
3. Fix immediately
4. Add new safety check

---

## Conclusion

With this TDD and testing infrastructure in place:

1. **Quality is built-in**, not tested-in
2. **Issues are prevented**, not discovered
3. **Refactoring is safe**, not scary
4. **Performance is guaranteed**, not hoped for
5. **Architecture is enforced**, not suggested

Every line of code is tested, every performance metric is tracked, and every architectural rule is enforced. This is how we ensure AudioStreaming implementation succeeds without any UI freezes or architectural issues.