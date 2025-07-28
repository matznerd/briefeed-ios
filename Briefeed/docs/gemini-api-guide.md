# Gemini API Integration Guide

## Overview
This document provides the correct implementation details for Google's Gemini API, including both text-to-speech (TTS) and text generation capabilities.

## API Endpoints

### Text-to-Speech (TTS)
```
https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent
```

### Text Generation (Summaries)
```
https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent
```

## Authentication
All requests require an API key as a query parameter:
```
?key=YOUR_API_KEY
```

## Important: Field Naming Convention
**ALL JSON fields MUST use snake_case, not camelCase**

❌ Wrong: `generationConfig`, `responseModalities`  
✅ Correct: `generation_config`, `response_modalities`

## Text-to-Speech (TTS) API

### Request Format
```json
{
  "contents": [{
    "parts": [{
      "text": "Your text to convert to speech"
    }],
    "role": "user"
  }],
  "generation_config": {
    "response_modalities": ["AUDIO"],
    "speech_config": {
      "voice_config": {
        "prebuilt_voice_config": {
          "voice_name": "Zephyr"
        }
      }
    }
  }
}
```

### Available Voices
```
Autonoe, Zephyr, Puck, Charon, Kore, Fenrir,
Leda, Orus, Aoede, Callirhoe, Enceladus, Iapetus,
Umbriel, Algieba, Despina, Erinome, Algenib, Rasalgethi,
Laomedeia, Achernar, Alnilam, Schedar, Gacrux, Pulcherrima,
Achird, Zubenelgenubi, Vindemiatrix, Sadachbia, Sadaltager, Sulafar
```

### Response Format
```json
{
  "candidates": [{
    "content": {
      "parts": [{
        "inline_data": {
          "mime_type": "audio/L16;codec=pcm;rate=24000",
          "data": "BASE64_ENCODED_PCM_AUDIO"
        }
      }],
      "role": "model"
    }
  }]
}
```

### Audio Format Details
- **Format**: PCM (Linear 16-bit)
- **Sample Rate**: 24000 Hz
- **Channels**: Mono
- **Encoding**: Base64

### Converting PCM to WAV
The API returns raw PCM data that needs WAV headers:
```swift
func pcmToWav(pcmData: Data, sampleRate: Int = 24000) -> Data {
    var wavData = Data()
    
    // RIFF header
    wavData.append("RIFF".data(using: .ascii)!)
    wavData.append(UInt32(36 + pcmData.count).littleEndianData)
    wavData.append("WAVE".data(using: .ascii)!)
    
    // fmt chunk
    wavData.append("fmt ".data(using: .ascii)!)
    wavData.append(UInt32(16).littleEndianData)
    wavData.append(UInt16(1).littleEndianData) // PCM
    wavData.append(UInt16(1).littleEndianData) // Mono
    wavData.append(UInt32(sampleRate).littleEndianData)
    wavData.append(UInt32(sampleRate * 2).littleEndianData)
    wavData.append(UInt16(2).littleEndianData)
    wavData.append(UInt16(16).littleEndianData)
    
    // data chunk
    wavData.append("data".data(using: .ascii)!)
    wavData.append(UInt32(pcmData.count).littleEndianData)
    wavData.append(pcmData)
    
    return wavData
}
```

## Text Generation API (Summaries)

### Request Format
```json
{
  "contents": [{
    "parts": [{
      "text": "Summarize this article: [article content]"
    }],
    "role": "user"
  }],
  "generation_config": {
    "temperature": 0.7,
    "max_output_tokens": 500,
    "top_p": 0.95,
    "top_k": 40
  }
}
```

### Response Format
```json
{
  "candidates": [{
    "content": {
      "parts": [{
        "text": "Generated summary text"
      }],
      "role": "model"
    },
    "finish_reason": "STOP",
    "safety_ratings": [...]
  }]
}
```

## Error Handling

### Common Error Responses
```json
{
  "error": {
    "code": 400,
    "message": "Invalid JSON payload received. Unknown name \"config\": Cannot find field.",
    "status": "INVALID_ARGUMENT",
    "details": [{
      "@type": "type.googleapis.com/google.rpc.BadRequest",
      "field_violations": [{
        "description": "Invalid JSON payload received. Unknown name \"config\": Cannot find field."
      }]
    }]
  }
}
```

### Error Codes
- **400**: Bad Request (check field names, ensure snake_case)
- **401**: Invalid API key
- **403**: Forbidden (check API key permissions)
- **429**: Rate limit exceeded
- **500**: Internal server error

## Rate Limits
- **TTS**: Limited requests per minute (exact limit varies by tier)
- **Text Generation**: 60 requests per minute (free tier)
- **Context Window**: 32k tokens for TTS

## Best Practices

### 1. Always Use Snake_Case
```swift
// Swift struct with coding keys
struct GeminiTTSConfig: Codable {
    let responseModalities: [String]
    let speechConfig: GeminiSpeechConfig
    
    enum CodingKeys: String, CodingKey {
        case responseModalities = "response_modalities"
        case speechConfig = "speech_config"
    }
}
```

### 2. Handle Rate Limiting
```swift
if httpResponse.statusCode == 429 {
    // Implement exponential backoff
    let delay = getBackoffDelay(attemptNumber)
    try await Task.sleep(nanoseconds: delay * 1_000_000_000)
    // Retry request
}
```

### 3. Validate Responses
```swift
guard let audioData = response.candidates?.first?.content.parts.first?.inlineData?.data else {
    throw GeminiError.invalidResponse("No audio data in response")
}
```

### 4. Error Recovery
```swift
do {
    return try await generateWithGemini(text: text)
} catch {
    // Log error for debugging
    print("Gemini TTS failed: \(error)")
    // Fall back to device TTS
    return generateWithDeviceTTS(text: text)
}
```

## Testing Considerations

### 1. Mock Responses
Create realistic mock responses for testing:
```json
// Mock success response
{
  "candidates": [{
    "content": {
      "parts": [{
        "inline_data": {
          "mime_type": "audio/L16;codec=pcm;rate=24000",
          "data": "UklGRg..."
        }
      }]
    }
  }]
}
```

### 2. Test Field Names
Always test that your JSON encoding produces snake_case:
```swift
let encoder = JSONEncoder()
encoder.keyEncodingStrategy = .convertToSnakeCase // Don't use this!
// Instead, use explicit CodingKeys
```

### 3. Integration Tests
```swift
func testLiveGeminiTTS() async throws {
    guard let apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] else {
        throw XCTSkip("GEMINI_API_KEY not set")
    }
    
    let service = GeminiTTSService(apiKey: apiKey)
    let result = try await service.generateSpeech(text: "Hello world")
    
    XCTAssertTrue(result.success)
    XCTAssertNotNil(result.audioData)
}
```

## Troubleshooting

### "Unknown field" errors
- Check ALL field names are snake_case
- Verify JSON structure matches exactly
- Use explicit CodingKeys in Swift

### No audio output
- Verify base64 decoding
- Check PCM to WAV conversion
- Ensure audio session is configured

### Rate limiting
- Implement retry with backoff
- Cache generated audio
- Use batch requests where possible

## Migration Notes

### From v1 to v1beta
- Endpoint changed from `/v1/` to `/v1beta/`
- Field naming changed from camelCase to snake_case
- New model names with "-preview-tts" suffix

## Resources
- [Official Gemini API Docs](https://ai.google.dev/gemini-api/docs)
- [TTS Documentation](https://ai.google.dev/gemini-api/docs/speech-generation)
- [API Playground](https://makersuite.google.com/)