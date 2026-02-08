# CLAUDE.md - iOS Agent Toolchain & Testing Guide

> **Copy this file** into any iOS project root and fill in the `[PLACEHOLDERS]` below.

## Project Configuration

| Setting | Value |
|---------|-------|
| **Project** | `[YOUR_PROJECT].xcodeproj` or `.xcworkspace` |
| **Scheme** | `[YOUR_SCHEME]` |
| **Bundle ID** | `[com.yourcompany.yourapp]` |
| **Min iOS Target** | `[17.0]` |
| **Simulator** | `[iPhone 17]` |
| **iOS Version** | `[26.0.1]` |
| **Simulator UUID** | `[run: xcrun simctl list devices | grep Booted]` |
| **Unit Test Target** | `[YourAppTests]` |
| **UI Test Target** | `[YourAppUITests]` |

---

## 1. CLI Tools

Install all four tools before starting any agent work:

```bash
brew install xcbeautify axe xcp
brew tap steipete/peekaboo && brew install peekaboo
```

Or use the Makefile: `make install-tools`

### xcbeautify — Build Output Formatter

Pipes xcodebuild output into readable, color-coded results. Propagates exit codes so agents know if the build actually failed.

```bash
xcodebuild build \
  -project "[YOUR_PROJECT].xcodeproj" \
  -scheme "[YOUR_SCHEME]" \
  -destination 'platform=iOS Simulator,name=[iPhone 17],OS=[26.0.1]' \
  | xcbeautify
```

**Why agents need this**: Raw xcodebuild output is thousands of lines. xcbeautify reduces it to errors/warnings only, so the agent can parse success/failure without burning context.

### xcp — Xcode Project File Manager

Adds, removes, or moves Swift files in the `.xcodeproj` from the command line. **Every new `.swift` file MUST be registered with xcp** or Xcode won't compile it.

```bash
# Add a new source file to the main target
xcp add-file "[YOUR_PROJECT].xcodeproj" \
  --file [YourApp]/Path/To/NewFile.swift \
  --targets "[YOUR_MAIN_TARGET]" \
  --create-groups

# Add a test file to the test target
xcp add-file "[YOUR_PROJECT].xcodeproj" \
  --file [YourAppTests]/NewTest.swift \
  --targets "[YOUR_TEST_TARGET]" \
  --create-groups

# Remove a file
xcp remove-file "[YOUR_PROJECT].xcodeproj" \
  --file [YourApp]/Path/To/OldFile.swift

# Move a file (updates project references)
xcp move-file "[YOUR_PROJECT].xcodeproj" \
  --from [YourApp]/Old/Path.swift \
  --to [YourApp]/New/Path.swift
```

**Critical rule**: If you create a new `.swift` file with the `Write` tool, you MUST immediately run `xcp add-file` to register it. Otherwise the build will fail with "no such module" or missing symbol errors.

### axe — Simulator UI Interaction

Interacts with the running app in the simulator via accessibility APIs. Can tap buttons, type text, read the accessibility tree, and take screenshots.

```bash
# Get the full accessibility tree as JSON (structured UI description)
axe --bundle-id [com.yourcompany.yourapp] tree

# Tap a button by accessibility identifier
axe --bundle-id [com.yourcompany.yourapp] tap --id "login.submitButton"

# Type text into the focused field
axe --bundle-id [com.yourcompany.yourapp] type "hello@example.com"

# Take a screenshot
axe --bundle-id [com.yourcompany.yourapp] screenshot --output screenshot.png
```

**Why agents need this**: After `make run`, agents use `axe tree` to verify the UI rendered correctly. It returns structured JSON with every visible element, its frame, label, and accessibility identifier — far more reliable than screenshot-based verification.

### peekaboo — Screenshot with AI Analysis

Captures simulator screenshots and can analyze them with AI for visual verification.

```bash
# Capture a screenshot
peekaboo capture --output screenshots/verification.png

# Capture with AI analysis (describe what's on screen)
peekaboo capture --analyze
```

**Why agents need this**: When `axe tree` confirms the right elements exist but you need to verify visual layout (colors, spacing, alignment), peekaboo provides visual ground truth.

---

## 2. MCP Servers

These are available to Claude Code agents automatically when configured in `.mcp.json`:

### XcodeBuildMCP — Full Xcode Build System + Simulator Control

Controls the entire Xcode build system and simulator from agent context.

**Set session defaults at the start of every session:**
```json
{
  "projectPath": "/absolute/path/to/[YOUR_PROJECT].xcodeproj",
  "scheme": "[YOUR_SCHEME]",
  "simulatorId": "[YOUR_SIMULATOR_UUID]",
  "useLatestOS": false
}
```
> Use `simulatorId` (not `simulatorName` + `useLatestOS: true`) for reliable builds.

**Key operations:**
| Tool | Purpose |
|------|---------|
| `build_sim` | Build for simulator |
| `build_run_sim` | Build and launch on simulator |
| `test_sim` | Run tests on simulator |
| `screenshot` | Capture simulator screenshot |
| `describe_ui` | Get accessibility tree (like `axe tree`) |
| `tap` / `type_text` / `swipe` | Interact with running app |
| `list_schemes` | List available schemes |
| `clean` | Clean build artifacts |
| `boot_sim` / `list_sims` | Manage simulators |

### swiftlens — Swift LSP Intelligence

Provides compiler-accurate Swift code analysis: symbol lookup, references, hover info, file validation, and code modification.

**Workflow (orient → investigate → analyze → modify → verify):**

1. **Orient** — `swift_get_symbols_overview` on a file to get a quick architectural map (cheap, do this first)
2. **Investigate** — `swift_find_symbol_references_files`, `swift_get_symbol_definition`, `swift_get_hover_info` to trace relationships
3. **Analyze** — `swift_analyze_files` for full symbol analysis (expensive, use sparingly)
4. **Modify** — `swift_replace_symbol_body` for surgical code changes
5. **Verify** — `swift_validate_file` immediately after ANY modification (catches syntax errors before building)
6. **Rebuild index** — `swift_build_index` after structural changes (new files, renamed symbols, changed signatures)

**When to rebuild the index:**
- After creating new Swift files
- After modifying function/method signatures
- If `swift_find_symbol_references_files` returns unexpectedly empty results
- After modifying `Package.swift` or project dependencies

### apple-doc-mcp — Apple Developer Docs

Search Apple's developer documentation directly from agent context.

| Tool | Purpose |
|------|---------|
| `search_symbols` | Find API symbols by name |
| `get_documentation` | Get full docs for a symbol/page |
| `list_technologies` | List all Apple frameworks |

---

## 3. Plugins & Skills

### axiom (Plugin) — 60+ iOS Auditor Skills

Axiom provides specialized analysis skills for iOS development. These run as agents that scan your codebase for issues.

**Key auditor skills:**
| Skill | Use When |
|-------|----------|
| `axiom:concurrency-auditor` | Checking Swift 6 concurrency / data race issues |
| `axiom:memory-auditor` | Finding retain cycles, timer leaks, observer leaks |
| `axiom:swiftui-performance-analyzer` | Diagnosing janky scrolling, excessive view updates |
| `axiom:swiftui-architecture-auditor` | Checking separation of concerns, logic in views |
| `axiom:swiftui-nav-auditor` | Navigation architecture, deep linking, state restoration |
| `axiom:accessibility-auditor` | VoiceOver, Dynamic Type, WCAG compliance |
| `axiom:security-privacy-scanner` | Hardcoded keys, insecure storage, Privacy Manifests |
| `axiom:codable-auditor` | JSON encoding/decoding anti-patterns |
| `axiom:energy-auditor` | Battery drain: timers, polling, location, animation leaks |
| `axiom:networking-auditor` | Deprecated networking APIs, App Store rejection risks |
| `axiom:testing-auditor` | Flaky tests, missing assertions, Swift Testing migration |
| `axiom:build-fixer` | Diagnosing Xcode build failures |
| `axiom:modernization-helper` | Migrating to iOS 17/18 patterns (@Observable, etc.) |

**Invoking axiom skills:**
```
# As slash commands
/axiom:fix-build
/axiom:run-tests
/axiom:screenshot

# As agent auditors (use Task tool with the matching agent type)
axiom:concurrency-auditor
axiom:memory-auditor
```

### ios-agent-verification (Skill) — Build Verification Workflow

Prevents agents from claiming "build succeeded" when it didn't. The verification workflow:
1. Check xcodebuild exit code
2. Grep output for `error:` and `BUILD FAILED`
3. Take screenshot to confirm app launched
4. Run `describe-ui` / `axe tree` to verify expected elements
5. Interact with the app to confirm functionality

### xcuitest-implementation (Skill) — XCUITest Patterns

Provides guidance on:
- Page Object model for test maintainability
- Accessibility identifier naming (`screen.element.qualifier`)
- `--uitesting` launch argument handling for test-specific app behavior
- Makefile integration for running tests

---

## 4. Accessibility Identifiers — Making Your App Testable

Accessibility identifiers are the bridge between your app's UI and automated testing (both XCUITest and agent-driven `axe` interaction). **Every interactive element needs one.**

### The Pattern

Create a centralized `AccessibilityIdentifiers.swift` file with a nested enum structure:

```swift
import Foundation

/// Centralized accessibility identifiers for XCUITest and agent automation.
/// Naming convention: `screen.element.qualifier`
enum AccessibilityID {

    // MARK: - Tab Bar
    enum TabBar {
        static let container = "tabBar.container"
        static let homeTab = "tabBar.homeTab"
        static let settingsTab = "tabBar.settingsTab"
        static let profileTab = "tabBar.profileTab"
    }

    // MARK: - Login Screen
    enum Login {
        static let container = "login.container"
        static let emailField = "login.emailField"
        static let passwordField = "login.passwordField"
        static let submitButton = "login.submitButton"
        static let forgotPasswordButton = "login.forgotPasswordButton"
        static let errorMessage = "login.errorMessage"
        static let loadingIndicator = "login.loadingIndicator"
    }

    // MARK: - Home Screen
    enum Home {
        static let container = "home.container"
        static let scrollView = "home.scrollView"
        static let headerTitle = "home.headerTitle"

        // Dynamic content uses functions
        static func listItem(id: String) -> String {
            "home.listItem.\(id)"
        }

        static func actionButton(id: String) -> String {
            "home.actionButton.\(id)"
        }
    }

    // MARK: - Settings
    enum Settings {
        static let container = "settings.container"
        static let notificationsToggle = "settings.notificationsToggle"
        static let darkModeToggle = "settings.darkModeToggle"
        static let logoutButton = "settings.logoutButton"
        static let versionLabel = "settings.versionLabel"
    }

    // MARK: - Alerts & Dialogs
    enum Alert {
        static let container = "alert.container"
        static let title = "alert.title"
        static let message = "alert.message"
        static let confirmButton = "alert.confirmButton"
        static let cancelButton = "alert.cancelButton"
    }

    // MARK: - Common Components
    enum Common {
        static let loadingSpinner = "common.loadingSpinner"
        static let errorView = "common.errorView"
        static let retryButton = "common.retryButton"
        static let emptyStateView = "common.emptyStateView"
    }
}
```

### Applying Identifiers in SwiftUI Views

```swift
// Static elements — use the enum constant
TextField("Email", text: $email)
    .accessibilityIdentifier(AccessibilityID.Login.emailField)

Button("Submit") { login() }
    .accessibilityIdentifier(AccessibilityID.Login.submitButton)

// Dynamic lists — use the function with item ID
ForEach(items) { item in
    ItemRow(item: item)
        .accessibilityIdentifier(AccessibilityID.Home.listItem(id: item.id))
}

// Containers — identify scroll views and parent containers
ScrollView {
    // content
}
.accessibilityIdentifier(AccessibilityID.Home.scrollView)
```

### Naming Convention Rules

| Rule | Example |
|------|---------|
| Format: `screen.element.qualifier` | `login.emailField`, `home.listItem.abc123` |
| Screens are lowercase | `login`, `home`, `settings`, `profile` |
| Elements are camelCase | `emailField`, `submitButton`, `scrollView` |
| Dynamic items use functions | `AccessibilityID.Home.listItem(id: item.id)` |
| Nested screens use dot path | `settings.notifications.toggle` |
| Buttons end with `Button` | `login.submitButton`, `alert.confirmButton` |
| Text fields end with `Field` | `login.emailField`, `register.nameField` |
| Labels end with `Label` | `home.headerTitle`, `profile.nameLabel` |
| Toggles end with `Toggle` | `settings.darkModeToggle` |

### What to Identify

**Always add identifiers to:**
- All buttons and tappable elements
- All text fields and inputs
- All toggles, sliders, pickers
- Container views and scroll views
- Labels that display dynamic state (errors, counts, status)
- List/collection items (with dynamic IDs)
- Navigation elements (back, close, done buttons)
- Loading indicators and empty states

**Skip identifiers for:**
- Pure decorative elements (dividers, spacers)
- Static images that aren't interactive
- Background colors/gradients

### UIView Rule (UIKit)

**Never use CALayer for visible elements.** CALayers are invisible to accessibility APIs (and therefore invisible to `axe` and XCUITest). Always use UIView subclasses instead.

---

## 5. Testing Workflows

### TDD: Red-Green-Refactor with Agent Tools

```
1. WRITE TEST (Red)
   → Create test file in [YourAppTests]/
   → xcp add-file "[YOUR_PROJECT].xcodeproj" --file <path> --targets "[YOUR_TEST_TARGET]" --create-groups
   → make test-unit  (confirm test fails — RED)

2. IMPLEMENT (Green)
   → Write minimal code to pass
   → xcp add-file "[YOUR_PROJECT].xcodeproj" --file <path> --targets "[YOUR_MAIN_TARGET]" --create-groups
   → make test-unit  (confirm test passes — GREEN)

3. REFACTOR
   → Clean up implementation
   → swiftlens swift_validate_file (syntax check)
   → make test  (confirm nothing broke)

4. VERIFY
   → make build  (full build passes)
   → For UI changes: make run → axe tree / peekaboo capture (visual check)
   → axiom auditors as needed (memory, concurrency, architecture)

5. COMMIT
   → git add <files> && git commit -m "feat: description"
```

### Test Structure

```
[YourApp]/
├── [YourAppTests]/                    # Unit tests
│   ├── Helpers/                       # TestHelpers.swift, async utilities
│   ├── Mocks/                         # MockURLSession, MockKeychain, etc.
│   ├── [FeatureA]Tests.swift
│   ├── [FeatureB]Tests.swift
│   └── README.md
├── [YourAppUITests]/                  # UI tests (XCUITest)
│   └── PageObjects/                   # Page object classes
└── Shared/
    └── AccessibilityIdentifiers.swift # Centralized IDs
```

### Test Naming Convention

```swift
class LoginViewModelTests: XCTestCase {
    var sut: LoginViewModel!   // "sut" = system under test

    override func setUp() {
        super.setUp()
        sut = LoginViewModel()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // Pattern: test<Feature>_<Condition>_<ExpectedResult>
    func testLogin_ValidCredentials_ReturnsSuccess() {
        // Arrange
        let email = "test@example.com"
        let password = "validPassword"

        // Act
        let result = sut.login(email: email, password: password)

        // Assert
        XCTAssertTrue(result.isSuccess)
    }

    // Async test
    func testFetchData_NetworkAvailable_ReturnsResults() async throws {
        let result = try await sut.fetchData()
        XCTAssertFalse(result.isEmpty)
    }
}
```

### Page Object Pattern (XCUITest)

```swift
// PageObjects/LoginPage.swift
class LoginPage {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var emailField: XCUIElement {
        app.textFields[AccessibilityID.Login.emailField]
    }

    var passwordField: XCUIElement {
        app.secureTextFields[AccessibilityID.Login.passwordField]
    }

    var submitButton: XCUIElement {
        app.buttons[AccessibilityID.Login.submitButton]
    }

    @discardableResult
    func enterEmail(_ email: String) -> Self {
        emailField.tap()
        emailField.typeText(email)
        return self
    }

    @discardableResult
    func enterPassword(_ password: String) -> Self {
        passwordField.tap()
        passwordField.typeText(password)
        return self
    }

    @discardableResult
    func tapSubmit() -> Self {
        submitButton.tap()
        return self
    }
}

// In test:
func testSuccessfulLogin() {
    let loginPage = LoginPage(app: app)
    loginPage
        .enterEmail("test@example.com")
        .enterPassword("password123")
        .tapSubmit()

    XCTAssertTrue(app.otherElements[AccessibilityID.Home.container].waitForExistence(timeout: 5))
}
```

### TDD Rules for Agents

1. **Tests first** — Write the test before the implementation. Run it to confirm it fails.
2. **Minimal implementation** — Write only enough code to make the failing test pass.
3. **No skipping the red step** — If the test passes immediately, the test isn't testing anything useful.
4. **One behavior per test** — Each test should verify one specific behavior.
5. **Mock external dependencies** — Use `Mocks/` classes for network, keychain, database.
6. **Register files with xcp** — Every new `.swift` file must be added to the `.xcodeproj` via `xcp add-file`.
7. **Run full suite before commits** — `make test` must pass before any commit.
8. **Coverage on new code** — All new code must have tests. Aim for 80%+ coverage.

---

## 6. Agent Workflow (End to End)

The complete agent development loop:

```
Agent creates/modifies code
  → Write tool (create .swift file)
  → xcp add-file (register in .xcodeproj — REQUIRED for new files)
  → make build (xcodebuild + xcbeautify — check for compile errors)
  → make test-unit (run unit tests — verify logic)
  → make run (install + launch in simulator)
  → axe tree / XcodeBuildMCP describe_ui (verify UI via accessibility tree)
  → axe screenshot / peekaboo capture (visual verification)
  → swiftlens swift_validate_file (syntax validation)
  → axiom auditors (concurrency, memory, architecture checks)
  → git commit (when all green)
```

### Verification Checklist (Before Claiming "Done")

```
[ ] Build succeeds (make build exits 0)
[ ] Unit tests pass (make test-unit exits 0)
[ ] New files registered with xcp
[ ] Accessibility identifiers added to new interactive elements
[ ] UI verified via axe tree or describe_ui
[ ] No warnings in xcbeautify output
[ ] Visual check via screenshot (for UI changes)
```

---

## 7. Makefile

Drop this Makefile into your iOS project root. Replace the placeholders at the top.

```makefile
# iOS Project Makefile — Agent-Friendly Build Commands
#
# Usage:
#   make build         - Build for simulator
#   make test          - Run all tests
#   make test-unit     - Run unit tests only
#   make test-ui       - Run UI tests only
#   make run           - Build and launch on simulator
#   make clean         - Clean build artifacts
#   make install-tools - Install agent development tools

.PHONY: build test test-ui test-unit run clean install-tools lint help screenshot ui-tree tap

# ┌─────────────────────────────────────────────┐
# │  EDIT THESE VALUES FOR YOUR PROJECT          │
# └─────────────────────────────────────────────┘
PROJECT = "[YOUR_PROJECT].xcodeproj"
SCHEME = [YOUR_SCHEME]
SIMULATOR = iPhone 17
IOS_VERSION = 26.0.1
BUNDLE_ID = [com.yourcompany.yourapp]
UNIT_TEST_TARGET = [YourAppTests]
UI_TEST_TARGET = [YourAppUITests]
MAIN_TARGET = [YourApp]

# Derived data for faster incremental builds
DERIVED_DATA = $(HOME)/Library/Developer/Xcode/DerivedData/$(SCHEME)-build

# Default target
.DEFAULT_GOAL := help

help:
	@echo "$(SCHEME) iOS Build Commands"
	@echo ""
	@echo "Build & Run:"
	@echo "  make build         - Build for iOS simulator"
	@echo "  make run           - Build and launch on simulator"
	@echo "  make clean         - Clean build artifacts"
	@echo ""
	@echo "Testing:"
	@echo "  make test          - Run all tests (unit + UI)"
	@echo "  make test-unit     - Run unit tests only"
	@echo "  make test-ui       - Run UI tests only"
	@echo ""
	@echo "Agent Tools:"
	@echo "  make ui-tree       - Get accessibility tree (requires running app)"
	@echo "  make screenshot    - Take simulator screenshot"
	@echo "  make tap ELEMENT=x - Tap element by accessibility ID"
	@echo "  make install-tools - Install xcbeautify, axe, xcp, peekaboo"
	@echo ""

# Build for simulator
build:
	@echo "Building $(SCHEME) for $(SIMULATOR)..."
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR),OS=$(IOS_VERSION)' \
		-derivedDataPath $(DERIVED_DATA) \
		-configuration Debug \
		| xcbeautify

# Run all tests
test:
	@echo "Running all tests..."
	xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR),OS=$(IOS_VERSION)' \
		-derivedDataPath $(DERIVED_DATA) \
		| xcbeautify

# Run unit tests only
test-unit:
	@echo "Running unit tests..."
	xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR),OS=$(IOS_VERSION)' \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:"$(UNIT_TEST_TARGET)" \
		| xcbeautify

# Run UI tests only
test-ui:
	@echo "Running UI tests..."
	xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR),OS=$(IOS_VERSION)' \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:"$(UI_TEST_TARGET)" \
		| xcbeautify

# Build and run on simulator
run:
	@echo "Booting simulator..."
	@xcrun simctl boot "$(SIMULATOR)" 2>/dev/null || true
	@echo "Building and installing..."
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR),OS=$(IOS_VERSION)' \
		-derivedDataPath $(DERIVED_DATA) \
		-configuration Debug \
		| xcbeautify
	@echo "Launching app..."
	xcrun simctl launch booted $(BUNDLE_ID)

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	xcodebuild clean -project $(PROJECT) -scheme $(SCHEME)
	rm -rf $(DERIVED_DATA)
	@echo "Clean complete."

# Take simulator screenshot
screenshot:
	@mkdir -p screenshots
	@TIMESTAMP=$$(date +%Y%m%d_%H%M%S); \
	xcrun simctl io booted screenshot "screenshots/screenshot_$$TIMESTAMP.png"; \
	echo "Screenshot saved to screenshots/screenshot_$$TIMESTAMP.png"

# Get accessibility tree using axe
ui-tree:
	@echo "Getting accessibility tree..."
	@axe --bundle-id $(BUNDLE_ID) tree 2>/dev/null || echo "Make sure the app is running and axe is installed"

# Tap a UI element by accessibility identifier
tap:
	@if [ -z "$(ELEMENT)" ]; then \
		echo "Usage: make tap ELEMENT=<accessibility-id>"; \
	else \
		axe --bundle-id $(BUNDLE_ID) tap --id "$(ELEMENT)"; \
	fi

# Install development tools for agent-friendly testing
install-tools:
	@echo "Installing development tools..."
	@which xcbeautify > /dev/null || brew install xcbeautify
	@which axe > /dev/null || brew install axe
	@which xcp > /dev/null || brew install xcp
	@which peekaboo > /dev/null || (brew tap steipete/peekaboo && brew install peekaboo)
	@echo ""
	@echo "Tools installed:"
	@echo "  - xcbeautify: $$(xcbeautify --version 2>/dev/null || echo 'not found')"
	@echo "  - axe: $$(axe --version 2>/dev/null || echo 'not found')"
	@echo "  - xcp: $$(xcp --version 2>/dev/null || echo 'not found')"
	@echo "  - peekaboo: $$(peekaboo --version 2>/dev/null || echo 'not found')"

# Lint Swift files (optional, requires swiftlint)
lint:
	@if which swiftlint > /dev/null; then \
		swiftlint lint $(MAIN_TARGET)/; \
	else \
		echo "SwiftLint not installed. Run: brew install swiftlint"; \
	fi
```

---

## 8. Critical Rules for AI Agents

1. **NEVER create a `.swift` file without running `xcp add-file`** — Xcode won't see it.
2. **ALWAYS use `AccessibilityID` enum** — Never hardcode identifier strings in views or tests.
3. **ALWAYS pipe xcodebuild through `xcbeautify`** — Raw output overwhelms agent context.
4. **ALWAYS verify builds actually succeeded** — Check exit code, don't trust output text alone.
5. **ALWAYS add accessibility identifiers to new interactive elements** — Buttons, fields, toggles, cells.
6. **NEVER use CALayer for visible elements** — They're invisible to accessibility/testing APIs.
7. **ALWAYS run `make test` before committing** — No broken tests in commits.
8. **Use `axe tree` to verify UI** — Structured data is more reliable than screenshots for agents.
9. **Use `swiftlens swift_validate_file` after modifications** — Catches syntax errors before a full build.
10. **Rebuild swiftlens index after structural changes** — `swift_build_index` after new files or signature changes.

---

## 9. Quick Setup Checklist

When setting up a new iOS project for agent development:

```
[ ] 1. Copy this CLAUDE.md and fill in placeholders
[ ] 2. Copy the Makefile and fill in placeholders
[ ] 3. Create Shared/AccessibilityIdentifiers.swift with initial enums
[ ] 4. Run: make install-tools (installs xcbeautify, axe, xcp, peekaboo)
[ ] 5. Verify: make build (should succeed)
[ ] 6. Add UI test target if not present (Xcode → File → New → Target → UI Testing Bundle)
[ ] 7. Create [YourAppUITests]/PageObjects/ directory
[ ] 8. Add AccessibilityIdentifiers.swift to BOTH main and test targets
[ ] 9. Add --uitesting launch argument handling in app delegate/scene:
```

```swift
// In your App struct or AppDelegate
#if DEBUG
if CommandLine.arguments.contains("--uitesting") {
    // Reset state, use test data, skip animations, etc.
}
#endif
```

```
[ ] 10. Verify: make test-unit (should run tests)
[ ] 11. Verify: make run && make ui-tree (should show accessibility tree)
[ ] 12. Configure XcodeBuildMCP session defaults (if using MCP)
```

---

## 10. MCP Configuration Template

Add to your project's `.mcp.json`:

```json
{
  "mcpServers": {
    "XcodeBuildMCP": {
      "command": "npx",
      "args": ["-y", "xcodebuildmcp@latest"]
    },
    "swiftlens": {
      "command": "npx",
      "args": ["-y", "swiftlens-mcp@latest"],
      "env": {
        "PROJECT_ROOT": "/absolute/path/to/your/ios/project"
      }
    },
    "apple-doc-mcp": {
      "command": "npx",
      "args": ["-y", "apple-doc-mcp@latest"]
    }
  }
}
```

---

*This template was generated from the ELSA iOS project's battle-tested agent toolchain. Adapt the placeholders to your project and you'll have a fully agent-friendly iOS development environment.*
