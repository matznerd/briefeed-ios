# UI Actions & Button Mappings

## Overview
The app uses gesture-based interactions and contextual buttons for content management and playback control.

## Article Row Actions

### Swipe Gestures
Location: `ArticleRowView.swift`

#### Right Swipe → Save Article
```swift
// Swipe threshold: 100 points
if offset > swipeThreshold {
    onSave()
    // Visual feedback: Green background
    // Haptic feedback: Impact medium
}
```

#### Left Swipe → Archive Article
```swift
if offset < -swipeThreshold {
    onDelete()
    // Visual feedback: Red background
    // Haptic feedback: Impact medium
}
```

### Long Press → Action Menu
Shows contextual buttons with countdown timer (5 seconds):

```swift
// Action buttons overlay
HStack {
    Button("Play Now") {
        queueService.addArticle(article, playNext: false)
        audioService.playNow()
    }
    
    Button("Play Next") {
        queueService.addArticle(article, playNext: true)
    }
}
```

## Audio Player Controls

### Mini Player (Bottom Bar)
Location: `MiniAudioPlayerV3.swift`

```swift
HStack {
    // Play/Pause button
    Button(action: { audioService.togglePlayPause() }) {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
    }
    
    // Title (tap to expand)
    Button(action: { showExpandedPlayer = true }) {
        MarqueeText(currentItem.title)
    }
    
    // Skip button
    Button(action: { audioService.skipToNext() }) {
        Image(systemName: "forward.fill")
    }
}
```

### Expanded Player
Location: `ExpandedAudioPlayerV2.swift`

```swift
VStack {
    // Dismiss button (top)
    Button("Done") { dismiss() }
    
    // Progress slider
    Slider(value: $currentTime, in: 0...duration) {
        audioService.seek(to: $0)
    }
    
    // Control buttons
    HStack(spacing: 40) {
        // Previous
        Button { audioService.skipToPrevious() } {
            Image(systemName: "backward.fill")
        }
        
        // Play/Pause (large)
        Button { audioService.togglePlayPause() } {
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 72))
        }
        
        // Next
        Button { audioService.skipToNext() } {
            Image(systemName: "forward.fill")
        }
    }
    
    // Speed control
    SpeedPicker(speed: $playbackSpeed)
    
    // Queue button
    Button { showQueue = true } {
        Label("Queue", systemImage: "list.bullet")
    }
}
```

## Queue Management

### Brief View Actions
Location: `BriefViewV2.swift`

```swift
// Top toolbar
.toolbar {
    ToolbarItem(placement: .navigationBarTrailing) {
        Menu {
            Button("Clear All") {
                queueService.clearQueue()
            }
            Button("Play All") {
                queueService.playFromStart()
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}

// Swipe actions on queue items
.swipeActions(edge: .trailing) {
    Button(role: .destructive) {
        queueService.removeItem(at: index)
    } label: {
        Label("Remove", systemImage: "trash")
    }
}

// Drag to reorder
.onMove { source, destination in
    queueService.moveItem(from: source, to: destination)
}
```

## Feed Management

### Feed List Actions
Location: `FeedListView.swift`

```swift
// Add feed button
Button(action: { showAddFeed = true }) {
    Image(systemName: "plus.circle.fill")
}

// Feed row actions
.contextMenu {
    Button("Refresh") {
        feedViewModel.refreshFeed(feed)
    }
    Button("Edit") {
        editingFeed = feed
    }
    Button(role: .destructive, "Delete") {
        feedViewModel.deleteFeed(feed)
    }
}
```

## Live News Controls

### Radio-Style Playback
Location: `LiveNewsViewV2.swift`

```swift
// Main play button
Button(action: { 
    rssAudioService.playLiveNews()
}) {
    VStack {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 60))
        Text("Play Live News")
            .font(.headline)
    }
}
.buttonStyle(PrimaryButtonStyle())

// RSS feed management
ForEach(rssFeeds) { feed in
    HStack {
        Toggle(isOn: feed.isEnabled) {
            Text(feed.name)
        }
        Button("Refresh") {
            rssAudioService.refreshFeed(feed)
        }
    }
}
```

## Settings Actions

### Settings View
Location: `SettingsViewV2.swift`

```swift
// Theme toggle
Picker("Theme", selection: $theme) {
    Text("Light").tag(Theme.light)
    Text("Dark").tag(Theme.dark)
    Text("System").tag(Theme.system)
}

// Playback speed
Slider(value: $playbackSpeed, in: 0.5...2.0, step: 0.25) {
    Text("Speed: \(playbackSpeed, specifier: "%.2fx")")
}

// API key input
SecureField("Gemini API Key", text: $geminiAPIKey)
Button("Save") {
    UserDefaultsManager.shared.geminiAPIKey = geminiAPIKey
}

// Cache management
Button("Clear Audio Cache") {
    GeminiTTSService.shared.clearAudioCache()
}

// Voice selection
Picker("TTS Voice", selection: $selectedVoice) {
    ForEach(GeminiTTSService.availableVoices, id: \.self) { voice in
        Text(voice).tag(voice)
    }
}
```

## Gesture Recognizers

### Common Gestures

#### Swipe
```swift
DragGesture()
    .onChanged { value in
        offset = value.translation.width
        if abs(offset) > swipeThreshold && !hasTriggeredHaptic {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            hasTriggeredHaptic = true
        }
    }
    .onEnded { value in
        if abs(offset) > swipeThreshold {
            // Trigger action
        } else {
            // Snap back
            offset = 0
        }
    }
```

#### Long Press
```swift
LongPressGesture(minimumDuration: 0.5)
    .onEnded { _ in
        showActionButtons = true
        startCountdownTimer()
    }
```

#### Tap
```swift
TapGesture()
    .onEnded {
        // Handle tap
    }
```

## Button Styles

### Primary Button
```swift
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding()
            .background(Color.blue)
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}
```

### Loading Button
```swift
struct LoadingButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                }
                Text(title)
            }
        }
        .disabled(isLoading)
    }
}
```

## Navigation

### Tab Bar
```swift
TabView(selection: $selectedTab) {
    FeedView()
        .tabItem {
            Label("Feed", systemImage: "newspaper")
        }
        .tag(0)
    
    BriefView()
        .tabItem {
            Label("Brief", systemImage: "list.bullet")
        }
        .tag(1)
    
    LiveNewsView()
        .tabItem {
            Label("Live", systemImage: "dot.radiowaves.left.and.right")
        }
        .tag(2)
    
    SettingsView()
        .tabItem {
            Label("Settings", systemImage: "gear")
        }
        .tag(3)
}
```

## Accessibility

### Voice Over Support
```swift
.accessibilityLabel("Play article")
.accessibilityHint("Double tap to add to queue and play")
.accessibilityAddTraits(.isButton)
```

### Dynamic Type
```swift
.font(.system(.body))
.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
```