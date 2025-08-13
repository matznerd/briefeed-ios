# OpenAI TTS Migration Guide

## Overview

This guide explains how to migrate from Gemini TTS to OpenAI TTS in Briefeed, addressing the 100 generations/day limitation on Gemini's paid tier.

## Why Migrate?

### Gemini TTS Limitations
- **100 generations/day limit** even on paid plans
- No streaming support
- Limited voice customization
- Includes "thinking tokens" in output limits

### OpenAI TTS Advantages
- **No daily generation limits**
- Real-time streaming with chunked transfer encoding
- Advanced voice control (gpt-4o-mini-tts)
- News broadcaster voice customization
- Lower latency with PCM format streaming
- Competitive pricing ($0.015/1K chars)

## Implementation Status

### ✅ Completed
1. **OpenAITTSService.swift** - Full OpenAI TTS implementation
   - Streaming support with PCM format
   - News broadcaster voice profiles
   - Cost tracking
   - URLSession delegate for chunked streaming

2. **UnifiedAudioPlayer Integration**
   - Automatic fallback system
   - OpenAI as primary when configured
   - Gemini as fallback option
   - Smart error handling

3. **Documentation**
   - Comprehensive API reference (OPENAI-TTS-REFERENCE.md)
   - Implementation examples
   - Cost analysis

### 🚧 Configuration Steps

#### 1. Add OpenAI API Key

Add to your Settings view or configuration:

```swift
// In Settings or during app setup
UserDefaultsManager.shared.openAIAPIKey = "sk-..."
UserDefaultsManager.shared.preferredOpenAIVoice = .coral  // News voice
UserDefaultsManager.shared.useOpenAIStreaming = true      // Enable streaming
```

#### 2. Environment Variable (Alternative)

Set in Xcode scheme or .env file:
```bash
export OPENAI_API_KEY="sk-..."
```

## Migration Strategy

### Phase 1: Dual Service (Current Implementation)
```
┌─────────────────┐
│ UnifiedAudioPlayer │
└────────┬────────┘
         │
    ┌────▼────┐
    │ Has OpenAI │
    │   Key?    │
    └─┬──────┬─┘
      │      │
     Yes     No
      │      │
┌─────▼──┐ ┌─▼──────┐
│OpenAI  │ │Gemini  │
│  TTS   │ │  TTS   │
└────┬───┘ └───┬────┘
     │         │
     │    (100/day limit)
     │         │
┌────▼─────────▼────┐
│  Audio Playback   │
└───────────────────┘
```

### Phase 2: OpenAI Primary (Recommended)
- Configure OpenAI API key in app settings
- Monitor usage and costs
- Keep Gemini for summarization only

### Phase 3: Full Migration
- Remove Gemini TTS dependency
- Use OpenAI for all TTS needs
- Optimize streaming for best UX

## Cost Analysis

### Daily Usage Scenarios

| Articles/Day | Avg Chars | OpenAI Cost | Gemini Cost |
|-------------|-----------|-------------|-------------|
| 100         | 500       | $0.75       | Free (limit) |
| 500         | 500       | $3.75       | Not possible |
| 1000        | 500       | $7.50       | Not possible |

### Cost Optimization Tips
1. Cache generated audio files
2. Use streaming to reduce perceived latency
3. Implement user-based quotas if needed
4. Pre-generate popular content during off-peak

## Feature Comparison

| Feature | Gemini TTS | OpenAI TTS |
|---------|------------|------------|
| Daily Limit | 100 | Unlimited |
| Streaming | ❌ | ✅ |
| Voice Control | Basic | Advanced |
| News Voices | ❌ | ✅ |
| Cost | Free (limited) | $0.015/1K chars |
| Latency | Higher | Lower (streaming) |

## Testing the Migration

### 1. Test OpenAI Service
```swift
// Test in ContentView or debug view
Task {
    do {
        let url = try await OpenAITTSService.shared.generateNewsAudio(
            "This is a test of the OpenAI text-to-speech system."
        )
        print("Audio generated: \(url)")
    } catch {
        print("Error: \(error)")
    }
}
```

### 2. Test Streaming
```swift
OpenAITTSService.shared.streamAudio(
    text: "Breaking news: Streaming audio test successful.",
    voice: .coral,
    onStart: {
        print("Streaming started")
    },
    completion: { result in
        switch result {
        case .success(let url):
            print("Streaming complete: \(url)")
        case .failure(let error):
            print("Streaming failed: \(error)")
        }
    }
)
```

### 3. Monitor Costs
```swift
let cost = OpenAITTSService.shared.getEstimatedCost()
print("Estimated OpenAI TTS cost: $\(String(format: "%.4f", cost))")
```

## Error Handling

The system automatically handles common scenarios:

1. **No OpenAI Key**: Falls back to Gemini TTS
2. **OpenAI Rate Limit**: Falls back to Gemini TTS
3. **Gemini Quota Exceeded**: Logs warning, suggests OpenAI configuration
4. **Network Errors**: Retries with exponential backoff

## Voice Selection Guide

### For News Content
- **Primary**: `coral` - Clear, professional, upbeat
- **Alternative**: `sage` - Mature, authoritative
- **British**: `fable` - For UK news sources

### Voice Rotation
Implement voice variety to prevent monotony:
```swift
let voices: [OpenAIVoice] = [.coral, .sage, .echo]
let selectedVoice = voices.randomElement() ?? .coral
```

## Monitoring & Debugging

### Enable Debug Logging
```swift
// In OpenAITTSService
print("[OpenAITTS] Generating audio for \(text.count) characters")
print("[OpenAITTS] Using voice: \(voice.rawValue)")
print("[OpenAITTS] Estimated cost: $\(String(format: "%.4f", cost))")
```

### Track Service Usage
```swift
// In UnifiedAudioPlayer
if UserDefaultsManager.shared.openAIAPIKey != nil {
    print("[UnifiedPlayer] Using OpenAI TTS")
} else {
    print("[UnifiedPlayer] Using Gemini TTS (limited to 100/day)")
}
```

## Future Enhancements

1. **A/B Testing Framework**
   - Compare user engagement
   - Track audio quality feedback
   - Optimize voice selection

2. **Advanced Caching**
   - Store generated audio in Core Data
   - Implement LRU cache
   - Pre-generate trending articles

3. **Voice Cloning** (Future)
   - Custom news anchor voices
   - Regional accent support
   - Celebrity voice partnerships

## Troubleshooting

### Issue: "No audio generated"
- Check OpenAI API key is valid
- Verify network connectivity
- Check console logs for specific errors

### Issue: "Audio cuts off"
- Ensure full text is sent to API
- Check for special characters in text
- Verify audio buffer is properly flushed

### Issue: "High costs"
- Implement caching strategy
- Reduce summary lengths
- Use tts-1 model for non-critical content

## Support

For issues or questions:
1. Check console logs for [OpenAITTS] prefixed messages
2. Verify API key configuration
3. Monitor daily usage and costs
4. Test with simple text first

---

*Last Updated: January 2025*