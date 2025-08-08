# Performance Logging Guide

## Overview

Comprehensive performance logging has been added throughout the Briefeed app to help diagnose UI freezes and performance issues. The logging system captures detailed timing information, thread states, and operation durations.

## How to Use the Logging

### Running the App with Logging

1. Build and run the app in Xcode
2. Open the Console app (Applications > Utilities > Console)
3. Filter for "Briefeed" or look for the performance log prefixes

### Log Format

Logs follow this format:
```
[Timestamp][Time since app start][Event #][Thread][Category] File:Line - Message
```

Example:
```
[17:13:45.123][0.234s][#0042][MAIN][⚙️] AppViewModel.swift:305 - Getting BriefeedAudioService...
```

### Categories

- 📝 General - General log messages
- ⚙️ Service - Service method calls and operations
- 🖼️ View - SwiftUI view lifecycle events
- 📢 Publisher - @Published property changes
- 🔄 Thread - Thread transitions
- 💾 Memory - Memory usage tracking
- ⚠️ Warning - Potential issues
- ❌ Error - Errors
- 📋 Queue - Queue operations
- 🎵 Audio - Audio playback events
- 🌐 Network - Network operations
- 💿 CoreData - Database operations

### Operation Timing

Operations are tracked with start/end markers:
```
⏱️ START[17:13:45.123][0.234s][MAIN] Operation: AppViewModel.connectToServices
🟢 END[17:13:45.456][0.567s][MAIN] Operation: AppViewModel.connectToServices - Duration: 333.0ms
```

- 🟢 Green = Fast (<50ms)
- 🟡 Yellow = Medium (50-100ms)  
- 🔴 Red = Slow (>100ms)

### Key Areas to Monitor

1. **Service Initialization**
   - Look for `BriefeedAudioService.init`
   - Look for `QueueServiceV2.init`
   - Look for `ProcessingStatusService.init`
   - Check for circular dependencies

2. **View Updates**
   - Look for `ContentView.body`
   - Look for `MiniAudioPlayerV3.body`
   - Check for rapid re-renders

3. **Published Properties**
   - Look for rapid `@Published` changes
   - Check for update loops

4. **Main Thread Blocking**
   - Look for `⚠️ MAIN THREAD:` warnings
   - Check operation durations on MAIN thread

## Diagnosing UI Freezes

### Steps to Identify Freeze Location

1. **Run the app and trigger the freeze**
   - Note the exact time when the freeze occurs
   - Note what action triggered it

2. **Look for patterns in the logs:**
   - Slow operations (🔴 marked operations >100ms)
   - Main thread warnings
   - Rapid publisher updates
   - Service initialization delays

3. **Check for common issues:**
   - **Circular dependencies**: Service A initializes Service B which initializes Service A
   - **Main thread blocking**: Long operations on main thread
   - **Update loops**: Published properties triggering view updates that trigger more published changes
   - **Synchronous singleton access**: Services accessing each other during init

### Example Problem Patterns

#### Circular Dependency
```
⏱️ START AppViewModel.connectToServices
  ⏱️ START Get ArticleStateManager
    ⏱️ START Get BriefeedAudioService
      ⏱️ START Get ArticleStateManager  // CIRCULAR!
```

#### Main Thread Block
```
⚠️ MAIN THREAD: Heavy computation
🔴 END Operation: SomeHeavyOperation - Duration: 2500.0ms  // BAD!
```

#### Update Loop
```
📢 Publisher 'isPlaying' true -> false
🖼️ ContentView.body
📢 Publisher 'isPlaying' false -> true  // LOOP!
🖼️ ContentView.body
```

## Next Steps

After collecting logs:

1. **Identify the freeze pattern** from the logs
2. **Find the root cause** (circular dependency, main thread block, etc.)
3. **Apply appropriate fix**:
   - Defer service initialization
   - Move heavy operations off main thread
   - Break circular dependencies
   - Throttle publisher updates
   - Use Task.detached for background work

## Current Known Issues Fixed

1. ✅ Circular dependencies in service initialization
2. ✅ Task.detached accessing @MainActor singletons causing deadlock
3. ✅ Continuous publisher updates from timer-based operations
4. ✅ Synchronous singleton access during view construction

## Remaining Investigation

If UI freeze still occurs after these fixes, check logs for:
- SwiftUI view update cycles
- Memory pressure (look for 💾 logs)
- Network delays blocking UI
- Core Data fetch operations on main thread