# Briefeed UI Latency Improvement - Handoff Document

**Project:** Briefeed iOS App
**Feature:** Instant Content Display with Non-Blocking Summary and Optimistic Audio
**Created:** 2026-01-12

---

## Quick Start for New Sessions

**If you're an AI starting a new conversation**, use one of the prompts below to get context:

### Starting Epic 1 (Instant Content Display)

```
I'm working on the Briefeed iOS app and need to implement Epic 1: Instant Content Display.

Please read the handoff document at:
docs/handoff/instant-content-epic.md

This epic is about loading article URLs directly in WKWebView immediately when the user taps, instead of waiting for Firecrawl to scrape content first. The goal is instant content display (<500ms).

Key files to modify:
- Briefeed/Features/Article/ArticleView.swift
- Briefeed/Core/ViewModels/ArticleViewModel.swift
- Briefeed/Features/Article/ArticleReaderView.swift

Please review the epic document and begin implementation of the tasks.
```

### Starting Epic 2 (Non-Blocking Summary UI)

```
I'm working on the Briefeed iOS app and need to implement Epic 2: Non-Blocking Summary UI.

Please read the handoff document at:
docs/handoff/summary-ui-epic.md

Prerequisites: Epic 1 (Instant Content Display) must be completed first.

This epic is about creating a summary card that slides in from the bottom without interrupting the user's reading position. The user should be able to continue scrolling while the summary prepares.

New files to create:
- Briefeed/Features/Article/Components/SummarySlideCard.swift
- Briefeed/Features/Article/Components/ExpandableSummarySheet.swift

Please review the epic document and begin implementation of the tasks.
```

### Starting Epic 3 (Optimistic Audio Pre-generation)

```
I'm working on the Briefeed iOS app and need to implement Epic 3: Optimistic Audio Pre-generation.

Please read the handoff document at:
docs/handoff/optimistic-audio-epic.md

Prerequisites: Epic 1 and Epic 2 must be completed first.

This epic is about pre-generating TTS audio immediately when the summary completes, before the user taps Play. We're using Gemini 2.5 Flash TTS (NOT Gemini Live API - that's for interactive conversations).

Key files to modify:
- Briefeed/Core/ViewModels/ArticleViewModel.swift
- Briefeed/Core/Services/Audio/TTSGeneratorService.swift
- Briefeed/Core/ViewModels/AudioPlayerViewModelV2.swift

Please review the epic document and the Gemini TTS docs at:
docs/gemini-tts-docs/gemini-2.5-flash-tts.md

Then begin implementation of the tasks.
```

---

## Epic Overview

### Dependency Graph

```
┌─────────────────────────────────────┐
│ Epic 1: Instant Content Display     │  ← START HERE
│ Priority: P1                        │
│ Status: Ready to implement          │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│ Epic 2: Non-Blocking Summary UI     │
│ Priority: P2                        │
│ Status: Blocked by Epic 1           │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│ Epic 3: Optimistic Audio Pre-gen    │
│ Priority: P2                        │
│ Status: Blocked by Epic 2           │
└─────────────────────────────────────┘
```

### Summary Table

| Epic | Goal | Files Changed | New Files |
|------|------|---------------|-----------|
| 1 | Instant content (<500ms) | 3 | 0 |
| 2 | Non-blocking summary | 2 | 2 |
| 3 | Instant audio playback | 4 | 0 |

---

## Architecture Context

### Current Problem

The app has sequential blocking that causes perceived delays:

```
User taps article
    ↓ (wait)
Firecrawl scrapes content (1-5s)
    ↓ (wait)
Gemini generates summary (2-5s)
    ↓ (wait)
User taps Play
    ↓ (wait)
TTS generates audio (2-5s)
    ↓
Audio plays

Total time to audio: 5-15 seconds of waiting
```

### Target Architecture

Parallel processing with instant display:

```
User taps article
    ↓
WKWebView loads URL (instant)
    │
    ├── Background: Firecrawl + Summary
    │
    ▼
User reads article
    │
    ├── Summary card slides in (non-blocking)
    │
    ├── Background: TTS pre-generation
    │
    ▼
User taps Play
    ↓
Audio plays (instant from cache)

Time to audio: <100ms after tap
```

---

## Technical Decisions

### Why WKWebView over SFSafariViewController?

| Feature | SFSafariViewController | WKWebView |
|---------|----------------------|-----------|
| Overlay custom UI | ❌ Not possible | ✅ Full control |
| Reader Mode | Native (automatic) | Must implement (JS) |
| Best for this use case | ❌ | ✅ |

**Decision:** Use WKWebView because we need to overlay the summary card and play button. SFSafariViewController is opaque and doesn't allow custom UI overlays.

### Why Gemini TTS over Gemini Live API?

| API | Purpose | Our Use Case |
|-----|---------|--------------|
| Gemini Live | Interactive conversations | ❌ Not needed |
| Gemini 2.5 Flash TTS | Exact text recitation | ✅ Perfect fit |

**Decision:** Use `gemini-2.5-flash-preview-tts` for faithful text narration with style control via natural language prompts.

---

## File Reference

### Epic Documents

- [Epic 1: Instant Content Display](./instant-content-epic.md)
- [Epic 2: Non-Blocking Summary UI](./summary-ui-epic.md)
- [Epic 3: Optimistic Audio Pre-generation](./optimistic-audio-epic.md)

### Key Source Files

**Article Views:**
- `Briefeed/Features/Article/ArticleView.swift`
- `Briefeed/Features/Article/ArticleReaderView.swift`
- `Briefeed/Features/Article/ArticleSummaryView.swift`

**ViewModels:**
- `Briefeed/Core/ViewModels/ArticleViewModel.swift`
- `Briefeed/Core/ViewModels/AudioPlayerViewModelV2.swift`
- `Briefeed/Core/ViewModels/AppViewModel.swift`

**Services:**
- `Briefeed/Core/Services/Audio/TTSGeneratorService.swift`
- `Briefeed/Core/Services/Audio/GeminiTTSService.swift`
- `Briefeed/Core/Services/GeminiService.swift`
- `Briefeed/Core/Services/FirecrawlService.swift`

**Documentation:**
- `docs/gemini-tts-docs/gemini-2.5-flash-tts.md`
- `CLAUDE.md` (project guidelines)

---

## Progress Tracking

Update this section as epics are completed:

| Epic | Status | Completed By | Date | Notes |
|------|--------|--------------|------|-------|
| 1 | Not Started | - | - | - |
| 2 | Blocked | - | - | Waiting for Epic 1 |
| 3 | Blocked | - | - | Waiting for Epic 2 |

---

## Session End Checklist

Before ending a session, ensure:

- [ ] Code changes committed with descriptive message
- [ ] Epic document updated with completion status
- [ ] Any blockers or issues documented
- [ ] Progress table above updated
- [ ] `git push` to remote

---

## Questions / Blockers Log

Document any questions or blockers encountered during implementation:

| Date | Epic | Issue | Resolution |
|------|------|-------|------------|
| - | - | - | - |
