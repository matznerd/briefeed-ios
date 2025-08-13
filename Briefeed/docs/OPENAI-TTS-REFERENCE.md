# OpenAI TTS API Reference & Implementation Guide

## Executive Summary

OpenAI's Text-to-Speech (TTS) API offers a robust alternative to Gemini's limited TTS preview models. With no daily generation limits on the paid tier, streaming support, and the new `gpt-4o-mini-tts` model's advanced voice control capabilities, it's an excellent choice for Briefeed's audio generation needs.

## Key Advantages Over Gemini TTS

1. **No Daily Limits**: Unlike Gemini's 100 generations/day limit
2. **Streaming Support**: Real-time audio delivery with chunked transfer encoding
3. **Voice Customization**: Control accent, emotion, intonation, speed, and tone
4. **Multiple Output Formats**: MP3, Opus, AAC, FLAC, WAV, PCM
5. **Competitive Pricing**: $0.015-$0.030 per 1K characters

## Models & Pricing

### Available Models

| Model | Price/1K chars | Best For | Features |
|-------|---------------|----------|----------|
| **gpt-4o-mini-tts** | ~$0.015 | News narration | Voice control, emotions, accents |
| **tts-1** | $0.015 | Low latency | Basic TTS, faster response |
| **tts-1-hd** | $0.030 | High quality | Superior audio quality |

### Voice Control (gpt-4o-mini-tts)

The `gpt-4o-mini-tts` model accepts instructions to control:
- **Accent**: British, American, Australian, etc.
- **Emotional range**: Happy, sad, excited, calm
- **Intonation**: News broadcaster, conversational, formal
- **Speed**: Slow, normal, fast speech
- **Tone**: Professional, friendly, serious
- **Whispering**: For emphasis or quiet delivery

## Available Voices

11 built-in voices optimized for English:
- `alloy` - Neutral, versatile
- `ash` - Masculine, deep
- `ballad` - Warm, storytelling
- `coral` - Cheerful, upbeat
- `echo` - Smooth, professional
- `fable` - British accent
- `nova` - Energetic, young
- `onyx` - Deep, authoritative
- `sage` - Wise, mature
- `shimmer` - Feminine, clear

## Streaming Implementation

### Why Streaming Matters for Briefeed

Streaming allows audio playback to begin immediately while the rest generates, crucial for:
- **Reduced perceived latency**: Users hear audio within 1-2 seconds
- **Better UX**: No waiting for full generation
- **Memory efficiency**: No need to buffer entire audio file

### Transfer Encoding: Chunked

OpenAI uses HTTP chunked transfer encoding for streaming:
```
Transfer-Encoding: chunked
```

Each chunk contains:
1. Hex size indicator
2. `\r\n`
3. Chunk data
4. `\r\n`
5. Terminal chunk is size 0

### Output Format Recommendations

For **lowest latency** streaming in iOS:
1. **PCM** (best): Raw 24kHz samples, no decoding overhead
2. **WAV**: Uncompressed, minimal processing
3. **Opus**: Good compression, low latency

Avoid for streaming:
- **MP3**: Requires full frame decoding
- **FLAC**: Lossless but slower
- **AAC**: Additional decoding overhead

## iOS/Swift Implementation

### Using MacPaw OpenAI SDK (Recommended)

The MacPaw OpenAI SDK (https://github.com/MacPaw/OpenAI) provides a clean, type-safe implementation for iOS.

#### Installation via Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/MacPaw/OpenAI.git", from: "0.3.0")
]
```

#### Basic TTS Implementation with SDK

```swift
import OpenAI
import AVFoundation

class OpenAITTSService {
    private let openAI: OpenAI
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    
    init(apiKey: String) {
        let configuration = OpenAI.Configuration(
            token: apiKey,
            timeoutInterval: 30.0
        )
        self.openAI = OpenAI(configuration: configuration)
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        
        // PCM format for OpenAI: 24kHz, mono, 16-bit
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: 1,
            interleaved: false
        )!
        
        audioEngine.connect(
            playerNode,
            to: audioEngine.mainMixerNode,
            format: format
        )
        
        try? audioEngine.start()
    }
    
    /// Generate speech for news article with broadcaster voice
    func generateNewsAudio(
        text: String,
        voice: AudioSpeechQuery.AudioSpeechVoice = .coral
    ) async throws -> Data {
        
        let query = AudioSpeechQuery(
            model: .gpt4o_mini_tts,
            input: text,
            voice: voice,
            responseFormat: .pcm,  // Lowest latency
            speed: 1.0
        )
        
        // Add instructions for news broadcaster style
        var modifiedQuery = query
        modifiedQuery.instructions = """
            Speak like a professional news broadcaster. 
            Use clear enunciation, appropriate pauses between sentences, 
            and emphasize key facts and figures. 
            Maintain a steady, authoritative pace.
            """
        
        let result = try await openAI.audioCreateSpeech(query: modifiedQuery)
        return result.audio
    }
    
    /// Stream audio for immediate playback
    func streamNewsAudio(
        text: String,
        voice: AudioSpeechQuery.AudioSpeechVoice = .coral,
        onChunk: @escaping (Data) -> Void
    ) async throws {
        
        let query = AudioSpeechQuery(
            model: .gpt4o_mini_tts,
            input: text,
            voice: voice,
            responseFormat: .pcm,
            speed: 1.0
        )
        
        var modifiedQuery = query
        modifiedQuery.instructions = getNewsInstructions(for: text)
        
        // Stream the response
        let stream = try await openAI.audioCreateSpeechStream(query: modifiedQuery)
        
        for try await chunk in stream {
            onChunk(chunk.audio)
            processPCMChunk(chunk.audio)
        }
    }
    
    private func getNewsInstructions(for text: String) -> String {
        // Analyze content type for appropriate instructions
        if text.count < 100 {
            // Headline
            return "Speak like a news anchor introducing a major story. Authoritative and attention-grabbing."
        } else if text.contains("\"") && text.contains("said") {
            // Contains quotes
            return "Professional broadcaster tone with slightly slower pace for quoted material."
        } else {
            // Standard article
            return "Clear, professional news narration with steady pacing and emphasis on key facts."
        }
    }
    
    private func processPCMChunk(_ data: Data) {
        // Process in 4800-sample chunks (200ms at 24kHz)
        let chunkSize = 4800 * 2  // 16-bit samples
        
        guard data.count >= chunkSize else { return }
        
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: 1,
            interleaved: false
        )!
        
        let frameCount = UInt32(data.count) / 2
        
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else { return }
        
        buffer.frameLength = frameCount
        
        data.withUnsafeBytes { bytes in
            memcpy(buffer.int16ChannelData![0], bytes.baseAddress!, data.count)
        }
        
        playerNode.scheduleBuffer(buffer)
        
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }
}
```

### Streaming Implementation

```swift
import AVFoundation

class OpenAIStreamingTTS: NSObject {
    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private let apiKey: String
    private var session: URLSession!
    private var audioQueue = DispatchQueue(label: "audio.streaming.queue")
    private var pcmBuffer = Data()
    
    override init() {
        self.apiKey = UserDefaultsManager.shared.openAIAPIKey ?? ""
        super.init()
        setupAudioEngine()
        setupURLSession()
    }
    
    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        
        // PCM format: 24kHz, mono, 16-bit
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: 1,
            interleaved: false
        )!
        
        audioEngine.connect(
            playerNode,
            to: audioEngine.mainMixerNode,
            format: format
        )
        
        try? audioEngine.start()
    }
    
    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(
            configuration: config,
            delegate: self,
            delegateQueue: nil
        )
    }
    
    func streamSpeech(
        text: String,
        voice: String = "coral",
        newscastStyle: Bool = true
    ) {
        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let instructions = newscastStyle 
            ? "Speak like a professional news broadcaster. Use clear enunciation, appropriate pauses, and emphasize key points. Maintain a steady, authoritative pace."
            : "Speak naturally and conversationally."
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini-tts",
            "input": text,
            "voice": voice,
            "instructions": instructions,
            "response_format": "pcm"  // Raw audio for streaming
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let task = session.dataTask(with: request)
        task.resume()
        
        playerNode.play()
    }
    
    private func processPCMChunk(_ data: Data) {
        pcmBuffer.append(data)
        
        // Process in 4800-sample chunks (200ms at 24kHz)
        let chunkSize = 4800 * 2  // 16-bit samples
        
        while pcmBuffer.count >= chunkSize {
            let chunk = pcmBuffer.prefix(chunkSize)
            pcmBuffer.removeFirst(chunkSize)
            
            playPCMChunk(chunk)
        }
    }
    
    private func playPCMChunk(_ data: Data) {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: 1,
            interleaved: false
        )!
        
        let frameCount = UInt32(data.count) / 2  // 16-bit samples
        
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else { return }
        
        buffer.frameLength = frameCount
        
        data.withUnsafeBytes { bytes in
            memcpy(buffer.int16ChannelData![0], bytes.baseAddress!, data.count)
        }
        
        playerNode.scheduleBuffer(buffer)
    }
}

// MARK: - URLSessionDataDelegate
extension OpenAIStreamingTTS: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Process incoming PCM chunks
        audioQueue.async { [weak self] in
            self?.processPCMChunk(data)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("Streaming error: \(error)")
        }
        
        // Play any remaining buffered audio
        if !pcmBuffer.isEmpty {
            playPCMChunk(pcmBuffer)
            pcmBuffer.removeAll()
        }
    }
}
```

## Briefeed-Specific Implementation

### News Broadcaster Voice Profile

For optimal news narration, use these settings:

```swift
struct NewsVoiceProfile {
    let model = "gpt-4o-mini-tts"
    let voice = "coral"  // Professional, clear
    let alternativeVoice = "sage"  // For variety
    
    func instructions(for content: ArticleContent) -> String {
        switch content.type {
        case .headline:
            return "Speak like a news anchor introducing a major story. Authoritative and attention-grabbing."
        case .summary:
            return "Professional news broadcaster tone. Clear enunciation, appropriate pauses between sentences. Emphasize key facts and figures."
        case .quote:
            return "Slightly slower pace for quoted material. Add subtle emphasis to convey the speaker's intent."
        default:
            return "Clear, professional news narration with steady pacing."
        }
    }
}
```

### Integration with UnifiedAudioPlayer

```swift
extension UnifiedAudioPlayer {
    private func generateAudioWithOpenAI(_ text: String) async throws -> URL {
        let service = OpenAIStreamingTTS()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).pcm")
        
        // Stream and save simultaneously
        service.streamSpeech(
            text: text,
            voice: "coral",
            newscastStyle: true
        )
        
        // Save for caching
        let data = try await service.getCompleteAudio()
        try data.write(to: tempURL)
        
        return tempURL
    }
}
```

## Migration Strategy from Gemini

### Phase 1: Fallback Implementation
1. Keep Gemini as primary
2. Use OpenAI when Gemini hits daily limit
3. Monitor quality and performance

### Phase 2: A/B Testing
1. Random selection between services
2. Track user engagement metrics
3. Compare audio quality feedback

### Phase 3: Full Migration
1. OpenAI as primary TTS
2. Keep Gemini for summarization only
3. Optimize streaming for best UX

## Cost Analysis

### Comparison for Briefeed Usage

Assuming 1000 articles/day, 500 chars average:

| Service | Cost/Day | Limits | Quality |
|---------|----------|--------|---------|
| Gemini TTS | Free (100/day) | Hard limit | Good |
| OpenAI tts-1 | $7.50 | None | Good |
| OpenAI gpt-4o-mini | $7.50 | None | Excellent |
| OpenAI tts-1-hd | $15.00 | None | Best |

### Recommendation
Start with `gpt-4o-mini-tts` for:
- News broadcaster voice control
- No daily limits
- Reasonable cost
- Streaming support

## Best Practices

1. **Cache Generated Audio**: Store PCM/WAV files locally
2. **Pregenerate Popular Content**: Top articles during off-peak
3. **Use Streaming**: Start playback immediately
4. **Voice Rotation**: Alternate voices for variety
5. **Error Handling**: Fallback to AVSpeechSynthesizer

## API Rate Limits

- **Tier 1**: 500 RPM
- **Tier 2**: 1,000 RPM  
- **Tier 3**: 2,000 RPM
- **Tier 4**: 10,000 RPM
- **Tier 5**: 10,000 RPM

Most apps start at Tier 2-3, sufficient for Briefeed's needs.

## Conclusion

OpenAI's TTS API, particularly the `gpt-4o-mini-tts` model, offers significant advantages over Gemini's preview TTS:

1. **No daily generation limits**
2. **Advanced voice control for news narration**
3. **Real-time streaming with chunked encoding**
4. **Competitive pricing at scale**
5. **Multiple output formats for optimization**

For Briefeed's use case of news article narration, the ability to control intonation and speaking style to match a news broadcaster is invaluable. Combined with streaming support for immediate playback, OpenAI TTS provides a superior user experience.

## Implementation Checklist

- [ ] Add OpenAI API key to UserDefaultsManager
- [ ] Implement OpenAITTSService class
- [ ] Add streaming support with URLSession
- [ ] Create NewsVoiceProfile for broadcaster style
- [ ] Implement PCM audio handling
- [ ] Add caching layer for generated audio
- [ ] Create fallback to AVSpeechSynthesizer
- [ ] Add A/B testing framework
- [ ] Monitor costs and usage
- [ ] Optimize chunk sizes for streaming

---
*Last Updated: January 2025*
*Based on OpenAI API Documentation and production requirements for Briefeed iOS*