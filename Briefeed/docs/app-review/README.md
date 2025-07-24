# Briefeed App Review & TDD Implementation

This directory contains a comprehensive review of the Briefeed iOS app with a focus on implementing Test-Driven Development (TDD) to fix broken features and improve code quality.

## Documents

### 1. [Feature Mapping](feature-mapping.md)
Complete inventory of all app features including:
- RSS Feed Management
- Article Management  
- AI-Powered Summaries
- Audio Features
- Queue System
- Live News (RSS Podcasts)
- Reddit Integration (BROKEN)
- Settings & Customization

Key findings:
- Reddit import functionality is broken
- 0% test coverage across the entire app
- No existing test infrastructure

### 2. [Test Strategy](test-strategy.md)
Comprehensive testing approach following the testing pyramid:
- **70% Unit Tests**: Fast, isolated component tests
- **20% Integration Tests**: Component interaction tests
- **10% UI Tests**: Critical user flow tests

Includes:
- Test organization structure
- CI/CD integration setup
- Success metrics and goals
- 4-week implementation timeline

### 3. [TDD Implementation Guide](tdd-implementation-guide.md)
Detailed TDD approach for each feature with:
- iOS/SwiftUI best practices
- Red-Green-Refactor cycle
- Clean architecture testing patterns
- Briefeed-specific testing examples
- Mock and dependency injection strategies

### 4. [Critical Test Cases](critical-test-cases.md)
Specific test cases to debug the Reddit import issue:
- Network layer diagnostics
- URL parsing validation
- JSON response handling
- Core Data integration
- End-to-end import flow

## Quick Start

### Running Tests
```bash
# Run all tests
xcodebuild test -project Briefeed.xcodeproj -scheme Briefeed -destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test file
xcodebuild test -project Briefeed.xcodeproj -scheme Briefeed -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:BriefeedTests/RedditServiceTests

# Run with coverage
xcodebuild test -project Briefeed.xcodeproj -scheme Briefeed -destination 'platform=iOS Simulator,name=iPhone 15' -enableCodeCoverage YES
```

### Priority Actions

1. **Fix Reddit Import (Week 1)**
   - Implement RedditServiceTests
   - Add network diagnostics
   - Test URL parsing and API responses
   - Verify Core Data persistence

2. **Core Service Tests (Week 2)**
   - QueueService persistence
   - AudioService state management
   - GeminiService API integration
   - FirecrawlService content extraction

3. **Integration Tests (Week 3)**
   - Feed refresh workflows
   - Queue to audio pipeline
   - Background processing
   - Error propagation

4. **UI Tests (Week 4)**
   - Critical user paths
   - Navigation flows
   - State synchronization

## TDD Best Practices

1. **Write the test first** - Let failing tests drive implementation
2. **One assertion per test** - Keep tests focused and debuggable
3. **Fast and isolated** - No network/DB calls in unit tests
4. **Descriptive names** - `testMethodName_Scenario_ExpectedResult`
5. **Arrange-Act-Assert** - Clear test structure

## Architecture Considerations

Based on CLAUDE.md, the app uses:
- **Clean Architecture**: Clear separation of concerns
- **SwiftUI + Combine**: Reactive UI updates
- **Core Data**: Persistent storage
- **Async/Await**: Modern concurrency
- **Singleton Services**: Shared state management

Testing approach must respect these patterns:
- Use protocols for service dependencies
- Inject mocks for testing
- Test @Published properties with Combine
- Use in-memory Core Data stores
- Handle async code properly

## Next Steps

1. Create test targets if they don't exist
2. Add testing dependencies (ViewInspector, etc.)
3. Implement MockNetworkService
4. Write first failing test for Reddit import
5. Fix Reddit service to pass test
6. Continue with remaining critical tests

## Success Metrics

- Reddit import working again
- 80% unit test coverage
- All critical paths have integration tests
- CI/CD running tests on every commit
- No flaky tests
- Bug detection rate > 90%

This TDD approach will not only fix current issues but establish a robust testing culture for future development.