# Text-to-Speech Audio Pipeline

## Overview
The app converts article text into speech using Google's Gemini TTS API with fallback to device TTS.

## Service: `GeminiTTSService.swift`

### TTS Flow
1. **Text Preparation** → Format article for speech
2. **Voice Selection** → Choose from 30+ voices
3. **API Request** → Send to Gemini TTS
4. **Audio Processing** → Convert PCM to WAV
5. **Caching** → Store for reuse
6. **Fallback** → Device TTS if API fails

## Text Preparation

### Article to Speech Text
```swift
func formatStoryForSpeech(_ article: Article) -> String {
    var speechText = ""
    
    // 1. Add title
    if let title = article.title {
        speechText += "\(title). "
    }
    
    // 2. Priority: Summary > Content
    if let summary = article.summary, !summary.isEmpty {
        // Clean markdown and formatting
        let cleanSummary = summary
            .replacingOccurrences(of: "**", with: "")  // Remove bold
            .replacingOccurrences(of: "*", with: "")   // Remove italic
            .replacingOccurrences(of: "#", with: "")   // Remove headers
            .replacingOccurrences(of: "\n\n", with: ". ")
            .replacingOccurrences(of: "\n", with: " ")
        speechText += cleanSummary
    } else if let content = article.content {
        // Fallback to content, limit to 5000 chars
        let cleanContent = content.stripHTML
        if cleanContent.count > 5000 {
            speechText += String(cleanContent.prefix(5000))
            speechText += "... Content truncated for speech."
        }
    }
    
    return speechText
}
```

## Voice Selection

### Available Voices (30 total)
```swift
static let availableVoices = [
    "Autonoe", "Zephyr", "Puck", "Charon", "Kore", "Fenrir",
    "Leda", "Orus", "Aoede", "Callirhoe", "Enceladus", "Iapetus",
    "Umbriel", "Algieba", "Despina", "Erinome", "Algenib", "Rasalgethi",
    "Laomedeia", "Achernar", "Alnilam", "Schedar", "Gacrux", "Pulcherrima",
    "Achird", "Zubenelgenubi", "Vindemiatrix", "Sadachbia", "Sadaltager", "Sulafar"
]
```

### Voice Rotation Logic
```swift
private func selectNextVoice() -> String {
    // Sequential rotation for variety
    let voice = availableVoices[lastUsedVoiceIndex]
    lastUsedVoiceIndex = (lastUsedVoiceIndex + 1) % availableVoices.count
    return voice
}
```

## Gemini TTS API

### Request Structure
```swift
GeminiTTSRequest {
    contents: [{
        parts: [{ text: "Article text here" }],
        role: "user"
    }],
    generationConfig: {
        responseModalities: ["AUDIO"],
        speechConfig: {
            voiceConfig: {
                prebuiltVoiceConfig: {
                    voiceName: "Autonoe"
                }
            }
        }
    }
}
```

### API Endpoint
```
POST https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key={API_KEY}
```

### Response Processing
1. **Base64 decode** audio data
2. **PCM format** (24kHz, 16-bit, mono)
3. **Convert to WAV** with headers
4. **Save to cache** for reuse

## PCM to WAV Conversion

### WAV Header Construction
```swift
private func pcmToWav(pcmData: Data, sampleRate: Int = 24000) -> Data {
    var wavData = Data()
    
    // RIFF header
    wavData.append("RIFF".data(using: .ascii)!)
    wavData.append(UInt32(fileSize).littleEndianData)
    wavData.append("WAVE".data(using: .ascii)!)
    
    // fmt subchunk
    wavData.append("fmt ".data(using: .ascii)!)
    wavData.append(UInt32(16).littleEndianData)        // Subchunk size
    wavData.append(UInt16(1).littleEndianData)         // PCM format
    wavData.append(UInt16(1).littleEndianData)         // Mono
    wavData.append(UInt32(24000).littleEndianData)     // Sample rate
    wavData.append(UInt32(48000).littleEndianData)     // Byte rate
    wavData.append(UInt16(2).littleEndianData)         // Block align
    wavData.append(UInt16(16).littleEndianData)        // Bits per sample
    
    // data subchunk
    wavData.append("data".data(using: .ascii)!)
    wavData.append(UInt32(pcmData.count).littleEndianData)
    wavData.append(pcmData)
    
    return wavData
}
```

## Audio Caching

### Cache Strategy
```swift
// Cache location
~/Library/Caches/AudioCache/

// Filename format
{text_hash_prefix}_{voice_name}.wav

// Example
"a1b2c3d4e5f6g7h8_Autonoe.wav"
```

### Cache Lookup
```swift
func generateSpeech(text: String, voiceName: String) async -> TTSResult {
    // Generate cache key
    let textHash = text.data(using: .utf8)?.base64EncodedString()
    let fileName = "\(textHash.prefix(32))_\(voiceName).wav"
    let cachedURL = cacheDir.appendingPathComponent(fileName)
    
    // Check cache first
    if FileManager.default.fileExists(atPath: cachedURL.path) {
        if let cachedData = try? Data(contentsOf: cachedURL) {
            return TTSResult(success: true, audioData: cachedData)
        }
    }
    
    // Generate if not cached...
}
```

## Fallback to Device TTS

### AVSpeechSynthesizer Fallback
```swift
private func generateWithDeviceTTS(text: String) async -> TTSResult {
    let utterance = AVSpeechUtterance(string: text)
    utterance.rate = UserDefaultsManager.shared.playbackSpeed
    utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
    
    // Note: Currently returns flag indicating device TTS should be used
    // Actual playback handled by audio service
    return TTSResult(
        success: true,
        audioData: nil,
        audioURL: nil,
        error: nil,
        usedFallback: true,
        voiceUsed: "Device TTS"
    )
}
```

## Error Handling

### API Failures
- **Invalid API key**: Fall back to device TTS
- **Rate limiting**: Retry with exponential backoff
- **Network errors**: Use cached audio if available
- **Timeout**: 60 second timeout for generation

### Audio Validation
```swift
// Validate generated audio can be played
do {
    let testPlayer = try AVAudioPlayer(contentsOf: audioURL)
    print("Audio duration: \(testPlayer.duration) seconds")
} catch {
    print("WARNING: Generated audio cannot be played")
}
```

## Performance

### Optimizations
- **Caching**: Reuse generated audio
- **Voice rotation**: Different voice each time for variety
- **Background generation**: Pre-generate for queued items
- **Compression**: WAV format balances size/quality

### Known Issues
- Large texts may timeout
- Some voices have pronunciation quirks
- Cache can grow large over time
- No streaming support (full generation required)