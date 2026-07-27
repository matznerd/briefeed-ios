# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Configuration

| Setting | Value |
|---------|-------|
| **Project** | `Briefeed.xcodeproj` |
| **Scheme** | `Briefeed` |
| **Bundle ID** | `Matznerd.Briefeed` |
| **Min iOS Target** | `18.2` |
| **Simulator** | `iPhone 17` |
| **iOS Version** | `26.0.1` |
| **Simulator UUID** | `CCCE8AC6-751D-4AA8-BD08-45FB55EE8EBC` |
| **Unit Test Target** | `BriefeedTests` |
| **UI Test Target** | `BriefeedUITests` |

---

## Project Overview

Briefeed is an iOS app built with SwiftUI that provides an RSS feed reader with unique audio playback capabilities. The app allows users to manage RSS feeds, queue articles for reading, and listen to AI-generated summaries of articles using text-to-speech.

The app now includes a Live News feature that works like a radio - automatically playing the latest RSS podcast episodes from your configured feeds with a single tap.

## Build and Development Commands

Use the Makefile for all build/test/run operations. The Makefile lives at `Briefeed/Makefile` (same directory as the `.xcodeproj`).

```bash
# Build for simulator
make -C Briefeed build

# Run all tests
make -C Briefeed test

# Run unit tests only
make -C Briefeed test-unit

# Run UI tests only
make -C Briefeed test-ui

# Build and launch on simulator
make -C Briefeed run

# Clean build artifacts
make -C Briefeed clean

# Get accessibility tree (app must be running)
make -C Briefeed ui-tree

# Take simulator screenshot
make -C Briefeed screenshot

# Tap a UI element
make -C Briefeed tap ELEMENT=<accessibility-id>

# Install agent tools
make -C Briefeed install-tools
```

## 1. CLI Tools

All four agent tools are installed:

### xcbeautify -- Build Output Formatter

Pipes xcodebuild output into readable, color-coded results. Propagates exit codes.

```bash
xcodebuild build \
  -project Briefeed.xcodeproj \
  -scheme Briefeed \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0.1' \
  | xcbeautify
```

**Why agents need this**: Raw xcodebuild output is thousands of lines. xcbeautify reduces it to errors/warnings only.

### xcp -- Xcode Project File Manager

Adds, removes, or moves Swift files in the `.xcodeproj` from the command line. **Every new `.swift` file MUST be registered with xcp** or Xcode won't compile it.

```bash
# Add a new source file to the main target
xcp add-file Briefeed.xcodeproj \
  --file Briefeed/Path/To/NewFile.swift \
  --targets Briefeed \
  --create-groups

# Add a test file to the test target
xcp add-file Briefeed.xcodeproj \
  --file BriefeedTests/NewTest.swift \
  --targets BriefeedTests \
  --create-groups

# Remove a file
xcp remove-file Briefeed.xcodeproj \
  --file Briefeed/Path/To/OldFile.swift

# Move a file (updates project references)
xcp move-file Briefeed.xcodeproj \
  --from Briefeed/Old/Path.swift \
  --to Briefeed/New/Path.swift
```

**Critical rule**: If you create a new `.swift` file with the `Write` tool, you MUST immediately run `xcp add-file` to register it. Otherwise the build will fail with "no such module" or missing symbol errors.

### axe -- Simulator UI Interaction

Interacts with the running app in the simulator via accessibility APIs.

```bash
# Get the full accessibility tree as JSON
axe --bundle-id Matznerd.Briefeed tree

# Tap a button by accessibility identifier
axe --bundle-id Matznerd.Briefeed tap --id "login.submitButton"

# Type text into the focused field
axe --bundle-id Matznerd.Briefeed type "hello@example.com"

# Take a screenshot
axe --bundle-id Matznerd.Briefeed screenshot --output screenshot.png
```

### peekaboo -- Screenshot with AI Analysis

```bash
# Capture a screenshot
peekaboo capture --output screenshots/verification.png

# Capture with AI analysis
peekaboo capture --analyze
```

---

## 2. MCP Servers

### XcodeBuildMCP -- Full Xcode Build System + Simulator Control

Set session defaults at the start of every session:
```json
{
  "projectPath": "/Users/me/ericode/briefeed-app/briefeed-ios/Briefeed/Briefeed.xcodeproj",
  "scheme": "Briefeed",
  "simulatorId": "CCCE8AC6-751D-4AA8-BD08-45FB55EE8EBC",
  "useLatestOS": false
}
```

Key operations: `build_sim`, `build_run_sim`, `test_sim`, `screenshot`, `describe_ui`, `tap`, `type_text`, `swipe`, `list_schemes`, `clean`, `boot_sim`, `list_sims`

### swiftlens -- Swift LSP Intelligence

Workflow: orient -> investigate -> analyze -> modify -> verify

1. **Orient** -- `swift_get_symbols_overview` (cheap, do first)
2. **Investigate** -- `swift_find_symbol_references_files`, `swift_get_symbol_definition`, `swift_get_hover_info`
3. **Analyze** -- `swift_analyze_files` (expensive, use sparingly)
4. **Modify** -- `swift_replace_symbol_body` for surgical changes
5. **Verify** -- `swift_validate_file` after ANY modification
6. **Rebuild index** -- `swift_build_index` after structural changes

### apple-doc-mcp -- Apple Developer Docs

`search_symbols`, `get_documentation`, `list_technologies`

---

## 3. Architecture Overview

### Core Structure

The app follows a clean architecture pattern with clear separation of concerns:

- **App Entry**: `BriefeedApp.swift` - Main app entry point, handles app lifecycle, theme management, and Core Data initialization
- **Navigation**: `ContentView.swift` - Tab-based navigation with Feed, Brief (queue), Live News, and Settings tabs
- **Persistence**: `Persistence.swift` - Core Data stack management
- **Audio Player**: Always-visible mini player at bottom of screen

### Key Services

1. **QueueService** (`Core/Services/QueueService.swift`): Manages persistent audio queue across app launches, syncs with AudioService, handles background audio generation
2. **AudioService** (`Core/Services/AudioService.swift`): Audio playback using AVSpeechSynthesizer, manages state/speed/queue
3. **GeminiService** (`Core/Services/GeminiService.swift`): Gemini API integration for article summarization
4. **FirecrawlService** (`Core/Services/FirecrawlService.swift`): Scrapes article content from URLs
5. **StorageService** (`Core/Services/StorageService.swift`): Article storage and archiving
6. **RSSAudioService** (`Core/Services/RSS/RSSAudioService.swift`): RSS podcast feeds and episodes

### Feature Organization

Features are organized by domain:
- **Article/**: Article list, reader, and summary views
- **Audio/**: Audio player UI components
- **Brief/**: Queue management and playlist views
- **Feed/**: RSS feed management and article fetching
- **LiveNews/**: RSS podcast feed management and radio-like playback
- **Settings/**: App preferences and configuration

### State Management

- **UserDefaultsManager**: Singleton for app settings (theme, playback speed, etc.)
- **Core Data**: For persistent storage of feeds and articles
- **@StateObject/@ObservedObject**: For reactive UI updates
- **Combine**: For reactive programming patterns

### Key Models

- **Article**: Core Data entity for RSS articles
- **Feed**: Core Data entity for RSS feeds
- **RSSFeed**: Core Data entity for RSS podcast feeds
- **RSSEpisode**: Core Data entity for RSS podcast episodes
- **ArticleSummary**: Struct for AI-generated summaries
- **QueuedItem**: Persistent queue item structure
- **EnhancedQueueItem**: Unified queue item supporting both articles and RSS episodes

## Important Implementation Details

1. **Audio Session**: Configured for spoken audio with mix-with-others capability
2. **Theme Management**: Dark/light mode preference applied at window level
3. **Queue Persistence**: Queue state saved to UserDefaults and restored on app launch
4. **Background Processing**: Articles in queue have summaries generated in background
5. **Error Handling**: Services use async/await with proper error propagation
6. **RSS Radio Mode**: "Play Live News" button queues only latest unlistened episodes from each feed
7. **Auto-play**: Optional auto-play on app launch for radio-like experience
8. **Episode Management**: Listened episodes are automatically removed from queue

## UI Components

- **MarqueeText**: Scrolling text for long titles
- **WaveformView**: Audio visualization during playback
- **LoadingButton**: Button with loading state
- **SpeedPicker**: Playback speed selection

---

## 4. Testing

### Test Structure

```
Briefeed/
├── BriefeedTests/           # Unit tests
│   ├── TDD/                 # TDD-driven feature tests
│   └── ScrollingTests.swift
├── BriefeedUITests/         # UI tests (XCUITest)
└── Briefeed/
    └── Shared/
        └── AccessibilityIdentifiers.swift  # Centralized IDs (TODO)
```

### TDD: Red-Green-Refactor with Agent Tools

```
1. WRITE TEST (Red)
   -> Create test file in BriefeedTests/
   -> xcp add-file Briefeed.xcodeproj --file <path> --targets BriefeedTests --create-groups
   -> make test-unit  (confirm test fails -- RED)

2. IMPLEMENT (Green)
   -> Write minimal code to pass
   -> xcp add-file Briefeed.xcodeproj --file <path> --targets Briefeed --create-groups
   -> make test-unit  (confirm test passes -- GREEN)

3. REFACTOR
   -> Clean up implementation
   -> swiftlens swift_validate_file (syntax check)
   -> make test  (confirm nothing broke)

4. VERIFY
   -> make build  (full build passes)
   -> For UI changes: make run -> axe tree / peekaboo capture
   -> axiom auditors as needed

5. COMMIT
   -> git add <files> && git commit -m "feat: description"
```

### Test Naming Convention

```swift
// Pattern: test<Feature>_<Condition>_<ExpectedResult>
func testLogin_ValidCredentials_ReturnsSuccess() { ... }
```

---

## 5. Critical Rules for AI Agents

1. **NEVER create a `.swift` file without running `xcp add-file`** -- Xcode won't see it.
2. **ALWAYS pipe xcodebuild through `xcbeautify`** -- Raw output overwhelms agent context.
3. **ALWAYS verify builds actually succeeded** -- Check exit code, don't trust output text alone.
4. **ALWAYS add accessibility identifiers to new interactive elements** -- Buttons, fields, toggles, cells.
5. **NEVER use CALayer for visible elements** -- They're invisible to accessibility/testing APIs.
6. **ALWAYS run `make -C Briefeed test` before committing** -- No broken tests in commits.
7. **Use `axe tree` to verify UI** -- Structured data is more reliable than screenshots for agents.
8. **Use `swiftlens swift_validate_file` after modifications** -- Catches syntax errors before a full build.
9. **Rebuild swiftlens index after structural changes** -- `swift_build_index` after new files or signature changes.

---

## 6. Agent Workflow (End to End)

```
Agent creates/modifies code
  -> Write tool (create .swift file)
  -> xcp add-file (register in .xcodeproj -- REQUIRED for new files)
  -> make -C Briefeed build (xcodebuild + xcbeautify)
  -> make -C Briefeed test-unit (run unit tests)
  -> make -C Briefeed run (install + launch in simulator)
  -> axe tree / XcodeBuildMCP describe_ui (verify UI)
  -> axe screenshot / peekaboo capture (visual verification)
  -> swiftlens swift_validate_file (syntax validation)
  -> axiom auditors (concurrency, memory, architecture checks)
  -> git commit (when all green)
```

### Verification Checklist (Before Claiming "Done")

```
[ ] Build succeeds (make -C Briefeed build exits 0)
[ ] Unit tests pass (make -C Briefeed test-unit exits 0)
[ ] New files registered with xcp
[ ] Accessibility identifiers added to new interactive elements
[ ] UI verified via axe tree or describe_ui
[ ] No warnings in xcbeautify output
[ ] Visual check via screenshot (for UI changes)
```
