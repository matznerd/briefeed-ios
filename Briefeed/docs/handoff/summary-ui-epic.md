# Epic 2: Non-Blocking Summary UI (Phase 2)

**Priority:** P2 (Medium)
**Type:** Epic
**Status:** Blocked by Epic 1
**Depends On:** [Epic 1: Instant Content Display](./instant-content-epic.md)

---

## Overview

Summary card slides in from bottom without interrupting user's reading position. User can continue scrolling while summary prepares.

## Goal

Summary appears as a non-intrusive slide-up card that doesn't reset scroll position or block the article view.

## Current Flow (Problem)

```
User reads article in WebView
    ↓
Summary generation completes
    ↓
UI updates, potentially resetting scroll position
    ↓
User loses their place in the article
```

## Target Flow (Solution)

```
User reads article in WebView (scroll position: 50%)
    ↓
Summary generation completes in background
    ↓
Small card slides up from bottom
    ↓
User still at 50% scroll position, can ignore or tap card
    ↓
Tap card → Expands to full summary sheet
```

---

## UI States

### State 1: Loading (User Reading)

```
┌─────────────────────────────────┐
│ Article Title                   │
├─────────────────────────────────┤
│                                 │
│  [WKWebView content]            │
│  User is reading here...        │
│                                 │
├─────────────────────────────────┤
│ ⏳ Preparing summary...         │  ← Subtle, non-blocking
└─────────────────────────────────┘
```

### State 2: Ready (Card Slides In)

```
┌─────────────────────────────────┐
│ Article Title                   │
├─────────────────────────────────┤
│                                 │
│  [WKWebView content]            │  ← SAME scroll position!
│  User is reading here...        │
│                                 │
├─────────────────────────────────┤
│ 📝 Summary Ready    [▶️ Play]   │  ← Tappable card
│ Tap to expand                   │
└─────────────────────────────────┘
```

### State 3: Expanded (User Tapped Card)

```
┌─────────────────────────────────┐
│ 📝 Quick Facts            [✕]   │
├─────────────────────────────────┤
│ • What: Key event described     │
│ • Who: People involved          │
│ • When: Timeline                │
│ • Key Numbers: Statistics       │
├─────────────────────────────────┤
│ The Story                       │
│ [Full narrative summary text    │
│  that explains the article...]  │
├─────────────────────────────────┤
│     [▶️ Play Summary]           │
│     [✕ Close]                   │
└─────────────────────────────────┘
```

---

## Implementation Tasks

### Task 2.1: Create SummarySlideCard Component

**New File:** `Briefeed/Features/Article/Components/SummarySlideCard.swift`

```swift
struct SummarySlideCard: View {
    enum State {
        case loading
        case ready(summary: FormattedArticleSummary)
        case error(message: String)
    }

    let state: State
    let onTap: () -> Void
    let onPlay: () -> Void

    var body: some View {
        // Compact card that shows at bottom of screen
        // Animates in when state changes from loading to ready
    }
}
```

**Acceptance Criteria:**
- [ ] Card animates smoothly from bottom (spring animation)
- [ ] Shows loading state with subtle spinner
- [ ] Shows "📝 Summary Ready" with play button when ready
- [ ] Tap anywhere on card triggers expansion
- [ ] Play button triggers audio without expanding

### Task 2.2: Create ExpandableSummarySheet Component

**New File:** `Briefeed/Features/Article/Components/ExpandableSummarySheet.swift`

```swift
struct ExpandableSummarySheet: View {
    let summary: FormattedArticleSummary
    let onPlay: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        // Full summary view with Quick Facts and The Story
        // Uses .presentationDetents for half/full height
    }
}
```

**Acceptance Criteria:**
- [ ] Shows Quick Facts (whatHappened, who, whenWhere, keyNumbers)
- [ ] Shows "The Story" narrative section
- [ ] Play button generates/plays audio
- [ ] Close button dismisses sheet
- [ ] Supports half-height and full-height presentation

### Task 2.3: Integrate Cards into ArticleView

**File:** `Briefeed/Features/Article/ArticleView.swift`

**Changes:**
- Add ZStack with WebView and overlay card
- Track summary state separately from content state
- Animate card appearance when summary ready
- Present sheet on card tap

**Acceptance Criteria:**
- [ ] Card appears as overlay, not pushing content
- [ ] WebView scroll position unchanged when card appears
- [ ] Sheet presents over everything when tapped
- [ ] Dismissing sheet returns to reading view

### Task 2.4: Update ArticleViewModel for Async Summary State

**File:** `Briefeed/Core/ViewModels/ArticleViewModel.swift`

**Changes:**
- Add `@Published var summaryState: SummaryState` enum
- Separate summary loading from content loading
- Notify when summary ready without UI blocking

```swift
enum SummaryState {
    case idle
    case loading
    case ready(FormattedArticleSummary)
    case error(String)
}
```

**Acceptance Criteria:**
- [ ] Summary state tracked independently
- [ ] State changes trigger card animations
- [ ] Error state shows in card, not alert

---

## Files to Create

| File | Type | Description |
|------|------|-------------|
| `SummarySlideCard.swift` | New | Bottom slide-in card |
| `ExpandableSummarySheet.swift` | New | Full summary sheet |

## Files to Modify

| File | Change Type | Description |
|------|-------------|-------------|
| `ArticleView.swift` | Moderate | Add overlay card |
| `ArticleViewModel.swift` | Minor | Add summary state enum |

## Dependencies

- **Requires:** Epic 1: Instant Content Display
  - Must have WKWebView loading URLs first
  - Must have background processing in place

## Blocks

- Epic 3: Optimistic Audio Pre-generation (depends on this)

---

## Animation Specifications

### Card Slide-In Animation

```swift
.transition(.move(edge: .bottom).combined(with: .opacity))
.animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
```

### Sheet Presentation

```swift
.sheet(isPresented: $showExpandedSummary) {
    ExpandableSummarySheet(...)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
}
```

---

## Test Plan

1. **Scroll Position Preservation**
   - Scroll to middle of article
   - Wait for summary to complete
   - Verify scroll position unchanged

2. **Card Animation**
   - Verify smooth slide-up animation
   - Verify no jank or layout jumps

3. **Sheet Interaction**
   - Tap card → Sheet expands
   - Tap play in sheet → Audio starts
   - Dismiss sheet → Return to article at same position

---

## Handoff Notes

**Completed:** [ ] Yes / [x] No
**Completion Date:** _________
**Prerequisites Verified:**
- [ ] Epic 1 completed
- [ ] URL-first loading works
- [ ] Background processing works

**Notes:**
```
(Add implementation notes here)
```

---

## Next Epic

After completing this epic, proceed to:
**[Epic 3: Optimistic Audio Pre-generation](./optimistic-audio-epic.md)**
