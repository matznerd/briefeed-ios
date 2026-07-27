# TTS Alternatives Research Report

**Date**: 2026-02-07
**Context**: Gemini TTS takes ~26s to generate 58s of audio. Goal: reduce time-to-first-audio to <1s.

## Current Baseline

| Metric | Value |
|--------|-------|
| Provider | Gemini 2.5 Flash Preview TTS |
| API style | Non-streaming `generateContent` |
| TTFB | ~26s (waits for full response) |
| Audio duration | 58s |
| Cost | Very cheap (token-based) |
| Cache hit | 0.03s |

---

## Option 1: On-Device TTS (No network, instant start)

### A. Kokoro-82M via FluidAudio (CoreML) -- RECOMMENDED FOR QUICK WIN

| Attribute | Details |
|-----------|---------|
| **Params** | 82M |
| **Model size** | ~82 MB CoreML |
| **Languages** | EN, JA, ZH, FR, ES, IT, PT, HI |
| **Voice cloning** | No |
| **Voices** | 21 expressive presets |
| **License** | Apache 2.0 |
| **Swift package** | [FluidAudio](https://github.com/FluidInference/FluidAudio) (1,415 stars) |
| **iOS support** | iOS 17+ (confirmed in Package.swift) |
| **iPhone perf** | **3.3x real-time on iPhone 13 Pro** |
| **Mac perf** | **23.8x real-time** (CoreML Neural Engine) |
| **Peak memory** | 3.37 GB |
| **Integration** | SPM: `FluidAudioTTS` library, CocoaPods also available |

**What this means for Briefeed:**
- 58s of audio would generate in ~18s on iPhone 13 Pro
- On newer iPhones (A17/A18): likely 8-12s
- Audio starts instantly (no network round-trip)
- Zero API cost, fully offline
- Works on airplane mode
- SPM integration: add `FluidAudio` package, call `FluidAudioTTS` API

**Downsides:**
- ~82 MB model download on first use
- 3.37 GB peak memory during generation
- No streaming (generates full audio, then plays)
- Quality good but not as natural as cloud TTS

### B. Kokoro-82M via mlx-audio-swift (MLX)

| Attribute | Details |
|-----------|---------|
| **Swift package** | [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) (88 stars) |
| **iOS support** | iOS 17+ (confirmed in Package.swift) |
| **Models** | Kokoro, Qwen3-TTS, CSM, Dia, OuteTTS, Spark, Chatterbox, Soprano |
| **License** | MIT |

**vs FluidAudio:** More models available, but MLX on iOS is less mature than CoreML. FluidAudio uses CoreML which is Apple's production-optimized path. mlx-audio-swift uses MLX which Apple considers "research" framework.

### C. Pocket TTS (100M, ONNX) -- BEST QUALITY ON-DEVICE

| Attribute | Details |
|-----------|---------|
| **Params** | 100M |
| **Size (INT8)** | ~200 MB (all components) |
| **Languages** | English only |
| **Voice cloning** | Yes (from 5s of audio) |
| **Streaming** | Yes, ~200ms TTFB |
| **License** | MIT |
| **CPU perf** | ~6x real-time on M4 (2 cores only) |
| **Quality** | WER 1.84%, ELO 2016 (beats F5-TTS) |
| **iOS port** | No official Swift SDK. ONNX Runtime iOS works. |

**What this means for Briefeed:**
- 58s of audio in ~10s (at 6x RT, potentially faster on A17/A18)
- With streaming: audio plays within 200ms of tapping Play
- Voice cloning possible (user could use their own voice)
- Best quality among on-device options

**Downsides:**
- No Swift SDK yet -- need to write ONNX Runtime iOS wrapper
- 200 MB model size
- English only
- More integration work than FluidAudio

### D. KittenTTS (15M, ultra-tiny)

| Attribute | Details |
|-----------|---------|
| **Params** | 15M |
| **Size** | <25 MB |
| **Languages** | English only |
| **Voices** | 8 preset |
| **Voice cloning** | No |
| **License** | Apache 2.0 |
| **iOS port** | No (ONNX-based, trivially portable) |

**Verdict:** Too low quality for a polished news narration app. Better suited for IoT/embedded.

### E. OtosakuTTS-iOS (CoreML FastPitch + HiFiGAN)

| Attribute | Details |
|-----------|---------|
| **Framework** | Native Swift + CoreML |
| **Output** | 22.05 kHz |
| **Fully offline** | Yes |
| **Benchmarks** | None published |

**Verdict:** Interesting but unproven. No performance data available.

---

## Option 2: Cloud Streaming TTS (Low latency, higher quality)

### A. OpenAI TTS -- RECOMMENDED FOR CLOUD PATH

| Attribute | Details |
|-----------|---------|
| **Models** | tts-1, tts-1-hd, gpt-4o-mini-tts |
| **Streaming** | Yes, chunked HTTP (Transfer-Encoding: chunked) |
| **TTFB** | 150-250ms |
| **Quality** | Good (tts-1), Excellent (gpt-4o-mini-tts with style instructions) |
| **Cost** | $0.015/1K chars |
| **Voices** | 10 (coral, sage recommended for news) |
| **Max input** | 4096 chars |
| **Swift SDK** | [MacPaw/OpenAI](https://github.com/MacPaw/OpenAI), or URLSession bytes() |
| **Existing code** | `OpenAITTSServiceSimple.swift` already in codebase |

**What this means for Briefeed:**
- Audio starts playing within ~200ms of tapping Play
- Stream chunks via `URLSession.shared.bytes(for:)`
- Feed chunks to AVAudioEngine for progressive playback
- gpt-4o-mini-tts: "Read like a professional news anchor" instruction
- Cost: ~$0.015 per article (~1000 chars)
- You already have OpenAI TTS code in the app

**Downsides:**
- Requires API key + internet
- $0.015/article adds up for heavy users
- Need to implement chunk-to-audio pipeline

### B. ElevenLabs Flash v2.5

| Attribute | Details |
|-----------|---------|
| **TTFB** | 75-252ms |
| **Quality** | Best in class |
| **Cost** | $0.12-0.30/1K chars (8-20x OpenAI) |
| **Swift SDK** | [Official](https://github.com/elevenlabs/elevenlabs-swift-sdk) |
| **Voice cloning** | Yes |

**Verdict:** Best quality but too expensive for a consumer news app.

### C. Deepgram Aura-2

| Attribute | Details |
|-----------|---------|
| **TTFB** | 90-200ms |
| **Quality** | Good, professional |
| **Cost** | $0.027-0.030/1K chars |
| **$200 free credit** | ~13M characters to start |

**Verdict:** Good price/performance. Simple REST API. No Swift SDK.

### D. Cartesia Sonic Turbo

| Attribute | Details |
|-----------|---------|
| **TTFB** | 40-90ms (industry leading) |
| **Quality** | Very good |
| **Cost** | $0.037-0.05/1K chars |
| **API** | WebSocket only (more complex) |

**Verdict:** Fastest TTFB but WebSocket-only adds complexity.

### E. Inworld TTS-1.5

| Attribute | Details |
|-----------|---------|
| **TTFB** | <130ms (Mini), <250ms (Max) |
| **Quality** | Top-rated (ELO #1) |
| **Cost** | $5/M chars (Mini), $10/M chars (Max) |

**Verdict:** New entrant, very competitive. Worth watching.

---

## Option 3: Self-Hosted TTS (best of both)

### Kokoro-82M via Docker (OpenAI-compatible API)

[kokoro-web](https://github.com/eduardolat/kokoro-web) provides an OpenAI-compatible API:
```
POST http://your-server:8000/v1/audio/speech
{"model": "kokoro", "input": "text", "voice": "af_heart"}
```

**Why this matters:** You could self-host on a cheap VPS, get cloud-like latency with zero per-request cost, and your app's existing OpenAI TTS code would work with just a URL change.

### F5-TTS via Docker (335M params)

| Attribute | Details |
|-----------|---------|
| **Params** | 335M |
| **GPU needed** | 6.4 GB VRAM |
| **Languages** | EN, ZH |
| **Voice cloning** | Yes |

**Verdict:** Requires GPU server. Overkill for this use case.

---

## Recommendation Matrix

| Priority | Approach | TTFB | Cost | Quality | Effort |
|----------|----------|------|------|---------|--------|
| **Quick win** | FluidAudio (Kokoro CoreML) | 0ms (local) | $0 | Good | Low (SPM add) |
| **Best streaming** | OpenAI gpt-4o-mini-tts | 200ms | $0.015/article | Very Good | Low (existing code) |
| **Best on-device** | Pocket TTS (ONNX) | 200ms streaming | $0 | Excellent | Medium (ONNX wrapper) |
| **Best quality** | ElevenLabs Flash v2.5 | 75ms | $0.15/article | Excellent | Low (Swift SDK) |
| **Zero cost cloud** | Self-hosted Kokoro | ~100ms | VPS only | Good | Medium (Docker) |

## Recommended Implementation Plan

### Phase 1: OpenAI Streaming TTS (fastest to ship)
1. Enable streaming in existing `OpenAITTSServiceSimple.swift`
2. Use `URLSession.shared.bytes(for:)` for chunked response
3. Buffer first ~50KB then start AVAudioEngine playback
4. Result: ~200ms TTFB vs current 26s

### Phase 2: FluidAudio On-Device Fallback
1. Add `FluidAudio` SPM dependency
2. Download Kokoro-82M CoreML model on first use (~82 MB)
3. Use as fallback when no API key / offline / airplane mode
4. Result: fully offline TTS at 3.3x+ real-time

### Phase 3 (future): Pocket TTS Integration
1. When official iOS SDK ships, evaluate as primary on-device engine
2. Streaming support + voice cloning + better quality than Kokoro
3. Monitor [kyutai-labs/pocket-tts](https://github.com/kyutai-labs/pocket-tts) for Swift/iOS port

---

## Sources

### Cloud APIs
- [OpenAI TTS Guide](https://platform.openai.com/docs/guides/text-to-speech)
- [ElevenLabs Stream API](https://elevenlabs.io/docs/api-reference/text-to-speech/stream)
- [Deepgram TTS Streaming](https://developers.deepgram.com/docs/tts-streaming-feature-overview)
- [Cartesia Sonic 3](https://docs.cartesia.ai/build-with-cartesia/tts-models/latest)
- [Inworld TTS-1.5](https://inworld.ai/blog/introducing-inworld-tts-1-5)
- [Gemini TTS Latency Issues](https://discuss.ai.google.dev/t/gemini-flash-tts-speed-hows-your-experience/85165)

### On-Device Models
- [Pocket TTS](https://github.com/kyutai-labs/pocket-tts) (3,070 stars, MIT)
- [Pocket TTS Technical Report](https://kyutai.org/pocket-tts-technical-report)
- [Pocket TTS ONNX](https://huggingface.co/KevinAHM/pocket-tts-onnx)
- [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) (Apache 2.0)
- [KittenTTS](https://github.com/KittenML/KittenTTS) (Apache 2.0)
- [Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS) (Apache 2.0)
- [NeuTTS](https://github.com/neuphonic/neutts) (Apache 2.0)

### iOS/Swift Packages
- [FluidAudio](https://github.com/FluidInference/FluidAudio) (1,415 stars, CoreML Kokoro, iOS 17+)
- [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) (88 stars, MLX, iOS 17+)
- [kokoro-swift-mlx](https://github.com/mattmireles/kokoro-swift-mlx) (MLX Swift port)
- [kokoro-ios](https://github.com/mlalma/kokoro-ios) (iOS + macOS)
- [OtosakuTTS-iOS](https://github.com/Otosaku/OtosakuTTS-iOS) (CoreML FastPitch+HiFiGAN)
- [MacPaw/OpenAI](https://github.com/MacPaw/OpenAI) (Swift SDK with TTS streaming)

### Self-Hosted
- [kokoro-web](https://github.com/eduardolat/kokoro-web) (OpenAI-compatible API)
- [F5-TTS](https://github.com/SWivid/F5-TTS) (335M, GPU required)
