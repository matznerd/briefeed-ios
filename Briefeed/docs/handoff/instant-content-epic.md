# Epic 1: Instant Content Display (Phase 1)

**Priority:** P1 (High)
**Type:** Epic
**Status:** Ready to implement

---

## Overview

Load article URLs directly in WKWebView immediately when user taps, removing blocking waits. Firecrawl runs in background while user reads.

## Goal

Show article content instantly - user sees webpage loading immediately instead of waiting for Firecrawl to scrape content first.

## Current Flow (Problem)

```
User taps article
    ↓
ArticleView loads
    ↓
Shows "Fetch Full Article" button (BLOCKING)
    ↓
User taps fetch → Firecrawl scrapes (1-5s wait)
    ↓
Content appears
```

## Target Flow (Solution)

```
User taps article
    ↓
ArticleView loads
    ↓
WKWebView immediately loads article URL (instant)
    ↓
User reads while Firecrawl runs in background
    ↓
Summary card slides in when ready (non-blocking)
```

---

## Implementation Tasks

### Task 1.1: Modify ArticleView to Load URL First

**File:** `Briefeed/Features/Article/ArticleView.swift`

**Changes:**
- Add WKWebView that loads `article.url` immediately on view appear
- Remove the "Fetch Full Article" button from critical path
- Keep summary section but make it appear asynchronously

**Acceptance Criteria:**
- [ ] Article URL loads in WebView within 500ms of tap
- [ ] No blocking UI before content appears
- [ ] WebView respects dark/light mode

### Task 1.2: Background Firecrawl Processing

**File:** `Briefeed/Core/ViewModels/ArticleViewModel.swift`

**Changes:**
- Move `loadArticleContent()` to background task triggered on view appear
- Don't block UI on Firecrawl completion
- Store scraped content in Core Data for future use (TTS, summary)

**Acceptance Criteria:**
- [ ] Firecrawl starts automatically when ArticleView appears
- [ ] UI is never blocked waiting for Firecrawl
- [ ] Content is cached for offline/TTS use

### Task 1.3: Update ArticleReaderView for URL-First Loading

**File:** `Briefeed/Features/Article/ArticleReaderView.swift`

**Changes:**
- Ensure `init(url:fontSize:isReaderMode:)` initializer works as primary path
- Verify reader mode JS works on live URLs
- Add loading indicator for WebView network loading

**Acceptance Criteria:**
- [ ] URL-based initialization is default for articles with URLs
- [ ] Reader mode toggle works on live URLs
- [ ] Loading spinner shows during network load

---

## Files to Modify

| File | Change Type | Description |
|------|-------------|-------------|
| `ArticleView.swift` | Major | Load URL first, async summary |
| `ArticleViewModel.swift` | Major | Background processing |
| `ArticleReaderView.swift` | Minor | URL-first loading |

## Dependencies

- None (this is Phase 1)

## Blocks

- Epic 2: Non-Blocking Summary UI (depends on this)
- Epic 3: Optimistic Audio Pre-generation (depends on Epic 2)

---

## Test Plan

1. **Instant Load Test**
   - Tap article with URL
   - Verify content visible < 500ms
   - Verify no loading spinner blocking content

2. **Background Processing Test**
   - Open article
   - Verify Firecrawl runs without UI interruption
   - Verify content cached after background fetch

3. **Offline Behavior**
   - Load article online
   - Go offline
   - Verify cached content still accessible

---

## Handoff Notes

When completing this epic, update the status and add notes here:

**Completed:** [ ] Yes / [x] No
**Completion Date:** _________
**Notes:**
```
(Add implementation notes, gotchas, or decisions made here)
```

---

## Next Epic

After completing this epic, proceed to:
**[Epic 2: Non-Blocking Summary UI](./summary-ui-epic.md)**
