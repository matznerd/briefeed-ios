# On-Device TTS Decision Framework for Briefeed

**Last updated**: 2026-02-07
**Research date**: 2026-02-07 (all data current as of this date)
**Status**: Decision document -- thinking through options before implementation

---

## The Problem

Gemini TTS takes **26 seconds** to generate 58s of audio via a blocking cloud API call. Users wait half a minute before hearing anything. We need to get time-to-first-audio under 1 second.

---

## Question 1: Do we need MLX?

**No. Use CoreML.**

| | CoreML | MLX | ONNX Runtime |
|---|---|---|---|
| **Apple's stance** | Production deployment framework | Research/experimentation framework | Third-party, cross-platform |
| **Runs on** | Neural Engine (ANE) -- most power-efficient | Metal GPU -- draws more power | CoreML EP or CPU |
| **Model caching** | Compiled `.mlmodelc` cached on disk, ~2s reload | No persistent compilation cache | Depends on EP |
| **iOS maturity** | Mature, battle-tested since iOS 11 | Experimental on iOS, not recommended by Apple for production | Works but slower on iPhone |
| **Kokoro-82M speed** | **23.2x real-time** (Mac M4 Pro) | **23.8x real-time** (Mac M4 Pro) | **0.8x real-time** on mobile (slower than real-time!) |
| **Peak memory** | **1.5 GB** | **3.37 GB** | Not benchmarked |
| **First-load compile** | ~15s (cached after) | ~2s (not cached) | N/A |
| **Swift Package** | FluidAudio (1,416 stars, Apache 2.0) | mlx-audio-swift (88 stars, MIT) | Manual integration |

**Why CoreML wins:**
1. **2x lower memory** (1.5 GB vs 3.37 GB) -- critical on iPhone where total RAM is 6-8 GB
2. **Neural Engine** uses dedicated silicon, doesn't compete with GPU for UI rendering
3. **Compiled models cached** on disk -- subsequent launches load in ~2s vs recompiling
4. Apple explicitly says MLX is "for research, not production deployment"
5. ONNX is a non-starter at 0.8x real-time (slower than real-time on mobile)

**Conclusion:** CoreML via FluidAudio is the clear choice for a shipping iOS app.

---

## Question 2: Which CoreML package?

**FluidAudio** is the only serious option.

| Package | Stars | Last release | TTS Models | iOS support | License |
|---------|-------|-------------|------------|-------------|---------|
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | 1,416 | v0.12.0 (2026-02-03) | Kokoro, **Pocket TTS** | iOS 17+ | Apache 2.0 (core) |
| [kokoro-ios](https://github.com/mlalma/kokoro-ios) | small | - | Kokoro only | iOS 18+ | - |
| [kokoro-coreml](https://github.com/mattmireles/kokoro-coreml) | small | - | Kokoro only | - | - |
| [OtosakuTTS-iOS](https://github.com/Otosaku/OtosakuTTS-iOS) | small | - | FastPitch+HiFiGAN | iOS 17+ | - |

**Why FluidAudio:**
- Most active development (12 releases in 2 months)
- Already converted Pocket TTS to CoreML (released 4 days ago)
- Plan to deprecate Kokoro in favor of Pocket TTS
- Full Swift package with SPM integration
- Also includes ASR, VAD, speaker diarization (useful future features)
- Well-documented with benchmarks

---

## Question 3: Which TTS model?

**Pocket TTS** (not Kokoro).

FluidAudio's v0.12.0 release notes say: *"we plan to deprecate kokoro tts in the future soon"*

### Pocket TTS vs Kokoro comparison

| | Pocket TTS | Kokoro-82M |
|---|---|---|
| **Parameters** | 100M | 82M |
| **CoreML size** | ~601 MB (4 models) | ~82 MB |
| **Languages** | English only | EN, JA, ZH, FR, ES, IT, PT, HI |
| **Voices** | 4 (alba, azelma, cosette, javert) | 21 expressive presets |
| **Voice cloning** | Yes (model supports it, but not in CoreML yet) | No |
| **eSpeak dependency** | **No** (feeds raw text tokens) | **Yes (GPL-3.0)** |
| **License** | **CC-BY-4.0** (just attribution) | Apache 2.0, but eSpeak is **GPL-3.0** |
| **Quality (WER)** | **1.84%** | Not published |
| **Quality (ELO)** | **2016** (beats F5-TTS) | Not benchmarked against |
| **Streaming** | Yes (Mimi decoder, 1920 samples/frame = 80ms) | Not natively |
| **Pronunciation control** | No SSML/IPA (text-only input) | Yes, via eSpeak IPA phonemes |
| **FluidAudio status** | **Active, recommended** | **Planned for deprecation** |

### Why Pocket TTS wins for Briefeed:

1. **No GPL dependency** -- Kokoro requires eSpeak (GPL-3.0), which has viral licensing implications. Pocket TTS feeds raw text tokens directly to the model, no phonemizer needed.

2. **Better audio quality** -- WER 1.84%, ELO 2016 (outperforms F5-TTS and DSM in benchmarks).

3. **Streaming architecture** -- Mimi decoder outputs 80ms audio frames, enabling progressive playback.

4. **Future-proof** -- FluidAudio is deprecating Kokoro in favor of Pocket TTS.

5. **Voice cloning potential** -- Model architecture supports it (gated weights from Kyutai), even though CoreML version doesn't include it yet.

### Downsides to accept:

1. **601 MB model** -- Significantly larger than Kokoro's 82 MB. Will need on-demand download, not bundled.
2. **English only** -- No multilingual support (Kokoro has 8 languages).
3. **4 voices only** -- Fewer than Kokoro's 21 presets.
4. **No pronunciation control** -- Can't override how it says specific words (no SSML phoneme support).
5. **No iPhone benchmarks yet** -- Only Mac benchmarks exist. iPhone performance is unknown but should be similar to Kokoro's 3.3x RT.
6. **CC-BY-4.0** -- Requires attribution to Kyutai (easy to do in Settings/About screen).

---

## Question 4: What about cloud TTS as complement?

On-device TTS has a generation speed ceiling (~3-5x real-time on iPhone). For 58s of audio, that's still 12-20 seconds of generation. With streaming we can start playback within ~200ms, but the full audio takes time to generate.

**Cloud streaming TTS** can start playback in 150-250ms AND the full audio is generated server-side at 35-100x real-time.

**Recommended hybrid approach:**

| Scenario | TTS Engine | TTFB | Notes |
|----------|-----------|------|-------|
| Has OpenAI key + internet | OpenAI streaming (gpt-4o-mini-tts) | ~200ms | Best quality + speed |
| Has Gemini key + internet | Gemini TTS (current) | ~26s | Fallback, already works |
| No API key / offline | Pocket TTS (on-device) | ~200ms (streaming) | Zero cost, works anywhere |
| Airplane mode | Pocket TTS (on-device) | ~200ms (streaming) | Only option that works |

**Priority order for TTS provider selection:**
1. OpenAI streaming (if key configured) -- fastest cloud, best quality
2. Pocket TTS on-device (if model downloaded) -- zero cost, offline capable
3. Gemini TTS (if key configured) -- current fallback, slow but works
4. AVSpeechSynthesizer -- system TTS, instant, lower quality, always available

---

## Known Models (as of 2026-02-07)

### On-Device (viable for iPhone)

| Model | Params | Size | Speed (Mac) | Speed (iPhone est.) | Quality | License | iOS Package |
|-------|--------|------|-------------|--------------------|---------|---------|----|
| **Pocket TTS** | 100M | 601 MB CoreML | ~23x RT est. | ~3-5x RT est. | Excellent (ELO 2016) | CC-BY-4.0 | FluidAudio v0.12.0 |
| **Kokoro-82M** | 82M | 82 MB CoreML | 23.2x RT | 3.3x RT (iPhone 13 Pro) | Good | Apache 2.0 + GPL (eSpeak) | FluidAudio (deprecating) |
| **KittenTTS** | 15M | 25 MB | Fast | Fast est. | Fair | Apache 2.0 | None (ONNX) |
| **Piper** | varies | 22-100 MB | Very fast | Very fast est. | Low-Medium | MIT | sherpa-onnx (complex) |

### Cloud Streaming (viable as complement)

| Provider | TTFB | Cost/article | Quality | Existing code |
|----------|------|-------------|---------|---------------|
| **OpenAI gpt-4o-mini-tts** | 150-250ms | $0.015 | Very Good | `OpenAITTSServiceSimple.swift` |
| ElevenLabs Flash v2.5 | 75-252ms | $0.15 | Excellent | None |
| Deepgram Aura-2 | 90-200ms | $0.03 | Good | None |
| Cartesia Sonic Turbo | 40-90ms | $0.04 | Very Good | None |
| **Gemini TTS** (current) | ~26s | Very cheap | Good | `GeminiTTSService.swift` |

### Not viable for iPhone

| Model | Why not |
|-------|---------|
| Qwen3-TTS (0.6-1.7B) | Too large, requires CUDA GPU |
| F5-TTS (335M) | Requires 6.4 GB VRAM, GPU only |
| Dia (1.6B) | 10 GB VRAM, dialogue-focused |
| MARS5 (1.2B) | Too large, PyTorch only |
| StyleTTS2 | 2 GB VRAM, PyTorch only |
| Bark (Suno) | Extremely slow, inconsistent |

---

## FluidAudio Integration Details

### SPM Setup

```swift
// Package.swift or Xcode SPM
.package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.0")

// Target dependency
.product(name: "FluidAudioTTS", package: "FluidAudio")
```

### Pocket TTS API

```swift
import FluidAudioTTS

let manager = PocketTtsManager()
try await manager.initialize()  // Downloads + compiles CoreML models (~15s first time, ~2s after)

let audioData = try await manager.synthesize(text: "Today's top stories...")
// audioData is WAV at 24kHz mono
```

### CoreML Model Details

| Component | Size | Purpose |
|-----------|------|---------|
| `cond_step` | ~200 MB | Voice + text conditioning (KV cache prefill) |
| `flowlm_step` | ~200 MB | Autoregressive generation |
| `flow_decoder` | ~190 MB | Flow matching denoiser (8 Euler steps/frame) |
| `mimi_decoder` | ~11 MB | Streaming audio codec (1920 samples/frame) |

- Compute: `.cpuAndGPU` (ANE causes artifacts in Mimi state feedback)
- First-load compile: ~15s, cached after (~2s reload)
- Chunking: 50 tokens max per chunk, auto-split at sentence/clause boundaries
- EOS detection: natural stop when eos_logit > -4.0

### Model Download Strategy

601 MB is too large to bundle in the app binary. Options:
1. **On-demand download**: Download on first "Play" tap, show progress bar
2. **Background download**: Start downloading after onboarding, before user needs it
3. **Lazy download**: Only download if user has no cloud API keys configured

---

## Open Questions

1. **iPhone benchmarks for Pocket TTS** -- No published data. Kokoro was 3.3x RT on iPhone 13 Pro; Pocket TTS is slightly larger (100M vs 82M) so expect similar or slightly slower.

2. **Memory pressure on iPhone** -- Kokoro CoreML peaked at 1.5 GB on Mac. iPhone has 6-8 GB RAM shared with system. Need to test if 1.5+ GB allocation causes memory warnings.

3. **Background generation** -- Can we generate TTS audio while app is backgrounded? iOS limits background execution but we might get ~30s via `beginBackgroundTask`.

4. **Model download UX** -- How to handle the 601 MB download? Show in Settings? Auto-download on WiFi? Bundle a fallback (AVSpeechSynthesizer) while downloading?

5. **Voice cloning** -- Kyutai gates the voice cloning weights separately. If they release them under CC-BY-4.0, FluidAudio could add CoreML voice cloning. Worth monitoring.

6. **Pronunciation issues** -- Pocket TTS has no phoneme control. If it mispronounces proper nouns in news articles, the only workaround is text substitution ("NVIDIA" → "en-vidia") which is unreliable.

---

## Decision Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Framework | **CoreML** (not MLX, not ONNX) | Production-ready, lower memory, Neural Engine, compiled model caching |
| Package | **FluidAudio** | Most active, has Pocket TTS CoreML, SPM, well-documented |
| Primary model | **Pocket TTS** | Best quality, no GPL, streaming, FluidAudio's recommended path |
| Cloud complement | **OpenAI streaming** | Existing code, 200ms TTFB, $0.015/article |
| Fallback | **AVSpeechSynthesizer** | Zero setup, instant, always available |

---

## Sources

- [FluidAudio GitHub](https://github.com/FluidInference/FluidAudio) (1,416 stars)
- [FluidAudio v0.12.0 Release Notes](https://github.com/FluidInference/FluidAudio/releases/tag/v0.12.0) (2026-02-03)
- [FluidAudio Benchmarks](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)
- [FluidAudio PocketTTS Docs](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/TTS/PocketTTS.md)
- [Pocket TTS CoreML Model](https://huggingface.co/FluidInference/pocket-tts-coreml)
- [Pocket TTS Original (Kyutai)](https://github.com/kyutai-labs/pocket-tts) (3,070 stars)
- [Pocket TTS Technical Report](https://kyutai.org/pocket-tts-technical-report)
- [mlx-audio-swift Package.swift](https://github.com/Blaizzy/mlx-audio-swift) (88 stars, iOS 17+)
- [Kokoro-82M CoreML](https://huggingface.co/FluidInference/kokoro-82m-coreml)
- [Kokoro on-device Benchmarks (NimbleEdge)](https://www.nimbleedge.com/blog/how-to-run-kokoro-tts-model-on-device/)
- [OpenAI TTS Guide](https://platform.openai.com/docs/guides/text-to-speech)
