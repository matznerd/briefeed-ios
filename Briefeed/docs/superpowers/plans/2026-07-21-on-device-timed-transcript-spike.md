# On-Device Timed Transcript Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove that Apple SpeechAnalyzer can produce on-device word-or-phrase timing precise enough to drive Briefeed's future one-word or two-line Radio transcript at playback rates from 0.5x through 3x.

**Architecture:** Add a pure timed-transcript domain and media-time index, then place the iOS 26 SpeechAnalyzer implementation behind a small engine protocol. A DEBUG/test-only probe transcribes a rights-cleared local fixture and writes a versioned JSON receipt; it never mutates Radio, Core Data, playback state, or production settings.

**Tech Stack:** Swift 5 language mode, Swift Testing, XCTest, SpeechAnalyzer/SpeechTranscriber on iOS 26, AVFoundation, CoreMedia, CryptoKit, Codable/JSONEncoder, and the repository's owned simulator adapter.

## Global Constraints

- Work in `/Users/me/ericode/briefeed-app/briefeed-ios/.worktrees/live-radio-mvp/Briefeed` on `codex/live-radio-mvp`; preserve unrelated changes.
- Keep `IPHONEOS_DEPLOYMENT_TARGET = 18.2`. Every SpeechAnalyzer symbol is availability-gated to iOS 26.
- Use Apple SpeechAnalyzer as the only implemented engine in this spike.
- Do not upgrade FluidAudio `0.14.5`, load Parakeet, add MLX/ONNX/WhisperKit, or alter PocketTTS.
- Do not add production episode downloads, transcript persistence, Core Data fields, Radio UI, ad detection, or playback mutations.
- Do not infer word timestamps inside a multiword Apple attributed run. Preserve it as a timed phrase.
- Use episode media time, never wall-clock time or playback-rate multiplication, for transcript selection.
- Automated tests never download Apple speech assets silently. Asset installation requires the explicit probe runner.
- Use a rights-cleared generated fixture. Do not commit or redistribute publisher podcast audio.
- No phone installation or device command is part of this plan.
- Simulator commands must use `skills/app-testing/scripts/run-radio.sh` and its owned-lane safety checks; exit `75` is infrastructure pressure, not a product failure.
- Follow red, green, refactor for every production-code change.

## File Map

**Timed transcript domain**

- Create `Briefeed/Core/Transcription/TimedTranscript.swift`: Codable transcript values, validation, and explicit word/phrase granularity.
- Create `Briefeed/Core/Transcription/TimedTranscriptIndex.swift`: binary-search media-time lookup.
- Create `Briefeed/Core/Transcription/TimedTranscriptEngine.swift`: engine protocol, raw attributed-run snapshot, asset policy, and typed errors.
- Create `Briefeed/Core/Transcription/AppleSpeechAnalyzerEngine.swift`: iOS 26 file transcription and Apple attributed-run extraction.

**Probe and fixtures**

- Create `Briefeed/Core/Debug/PodcastTranscriptionProbe.swift`: fixture fingerprinting and JSON receipt output.
- Create `BriefeedTests/Fixtures/Transcription/apple-news-script.txt`: rights-cleared known script.
- Generate `BriefeedTests/Fixtures/Transcription/apple-news-fixture.aiff`: checked-in local speech fixture.
- Create `skills/app-testing/scripts/make-transcript-fixture.sh`: deterministic fixture regeneration.
- Create `skills/app-testing/scripts/run-transcript-probe.sh`: explicit simulator probe with asset-download opt-in.

**Tests and evidence**

- Create `BriefeedTests/Transcription/TimedTranscriptTests.swift`.
- Create `BriefeedTests/Transcription/TimedTranscriptNormalizerTests.swift`.
- Create `BriefeedTests/Transcription/PodcastTranscriptionProbeTests.swift`.
- Create `BriefeedTests/Transcription/AppleSpeechAnalyzerIntegrationTests.swift`.
- Create `docs/research/receipts/2026-07-21-apple-speech-transcript-probe.md` only after the probe runs; record actual output and do not predeclare success.

---

### Task 1: Timed Transcript Domain and Media-Time Index

**Files:**
- Create: `Briefeed/Core/Transcription/TimedTranscript.swift`
- Create: `Briefeed/Core/Transcription/TimedTranscriptIndex.swift`
- Test: `BriefeedTests/Transcription/TimedTranscriptTests.swift`

**Interfaces:**
- Consumes: `TimeInterval`, `Codable`, and `Sendable` only.
- Produces: `TimedTranscriptGranularity`, `TimedTranscriptUnit`, `TimedTranscript`, `TimedTranscriptValidationError`, and `TimedTranscriptIndex.activeUnit(at:)`.

- [ ] **Step 1: Write the failing domain tests**

Create `TimedTranscriptTests.swift` with these behaviors:

```swift
import Foundation
import Testing
@testable import Briefeed

@Suite("Timed transcript")
struct TimedTranscriptTests {
    private let units = [
        TimedTranscriptUnit(text: "Good morning", startSeconds: 0.2, endSeconds: 0.8, confidence: 0.98, granularity: .phrase),
        TimedTranscriptUnit(text: "California", startSeconds: 1.0, endSeconds: 1.5, confidence: 0.95, granularity: .word),
        TimedTranscriptUnit(text: "news", startSeconds: 1.5, endSeconds: 1.9, confidence: nil, granularity: .word)
    ]

    @Test func validatesAndRoundTripsWithoutLosingPrecision() throws {
        let transcript = try TimedTranscript(
            assetFingerprint: "abc123",
            engineIdentifier: "apple-speech-analyzer",
            engineVersion: "iOS-26",
            localeIdentifier: "en-US",
            recognizedText: "Good morning California news",
            audioDurationSeconds: 3,
            processingDurationSeconds: 0.75,
            units: units
        )
        let decoded = try JSONDecoder().decode(TimedTranscript.self, from: JSONEncoder().encode(transcript))
        #expect(decoded == transcript)
    }

    @Test func rejectsOverlappingAndOutOfBoundsRanges() {
        #expect(throws: TimedTranscriptValidationError.self) {
            try TimedTranscript(assetFingerprint: "a", engineIdentifier: "e", engineVersion: "1", localeIdentifier: "en-US", recognizedText: "one two", audioDurationSeconds: 2, processingDurationSeconds: 1, units: [
                TimedTranscriptUnit(text: "one", startSeconds: 0, endSeconds: 1.2, confidence: nil, granularity: .word),
                TimedTranscriptUnit(text: "two", startSeconds: 1, endSeconds: 1.5, confidence: nil, granularity: .word)
            ])
        }
        #expect(throws: TimedTranscriptValidationError.self) {
            try TimedTranscript(assetFingerprint: "a", engineIdentifier: "e", engineVersion: "1", localeIdentifier: "en-US", recognizedText: "late", audioDurationSeconds: 2, processingDurationSeconds: 1, units: [
                TimedTranscriptUnit(text: "late", startSeconds: 1.5, endSeconds: 2.1, confidence: nil, granularity: .word)
            ])
        }
    }

    @Test func mediaTimeSelectsUnitsAndRetainsPriorUnitOnlyInsideInternalGaps() throws {
        let transcript = try TimedTranscript(assetFingerprint: "a", engineIdentifier: "e", engineVersion: "1", localeIdentifier: "en-US", recognizedText: "Good morning California news", audioDurationSeconds: 3, processingDurationSeconds: 1, units: units)
        let index = TimedTranscriptIndex(transcript: transcript)

        #expect(index.activeUnit(at: 0.1) == nil)
        #expect(index.activeUnit(at: 0.2)?.text == "Good morning")
        #expect(index.activeUnit(at: 0.9)?.text == "Good morning")
        #expect(index.activeUnit(at: 1.0)?.text == "California")
        #expect(index.activeUnit(at: 1.5)?.text == "news")
        #expect(index.activeUnit(at: 2.0) == nil)
    }

    @Test(arguments: [0.5, 1.0, 2.0, 3.0])
    func playbackRateNeverChangesMediaTimeLookup(rate: Double) throws {
        let transcript = try TimedTranscript(assetFingerprint: "a", engineIdentifier: "e", engineVersion: "1", localeIdentifier: "en-US", recognizedText: "Good morning California news", audioDurationSeconds: 3, processingDurationSeconds: 1, units: units)
        let index = TimedTranscriptIndex(transcript: transcript)
        #expect(index.activeUnit(at: 1.25)?.text == "California")
        #expect(rate >= 0.5)
    }
}
```

- [ ] **Step 2: Run the compile gate and verify RED**

Run:

```bash
make radio-compile
```

Expected: compilation fails because the timed-transcript symbols do not exist.

- [ ] **Step 3: Implement validated transcript values**

Implement `TimedTranscript.swift` with these exact public shapes:

```swift
import Foundation

enum TimedTranscriptGranularity: String, Codable, Equatable, Sendable {
    case word
    case phrase
}

struct TimedTranscriptUnit: Codable, Equatable, Sendable {
    let text: String
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval
    let confidence: Double?
    let granularity: TimedTranscriptGranularity
}

enum TimedTranscriptValidationError: Error, Equatable {
    case invalidDuration
    case invalidProcessingDuration
    case missingIdentity
    case emptyText(index: Int)
    case invalidRange(index: Int)
    case overlappingRange(index: Int)
}

struct TimedTranscript: Codable, Equatable, Sendable {
    let assetFingerprint: String
    let engineIdentifier: String
    let engineVersion: String
    let localeIdentifier: String
    let recognizedText: String
    let audioDurationSeconds: TimeInterval
    let processingDurationSeconds: TimeInterval
    let units: [TimedTranscriptUnit]

    init(assetFingerprint: String, engineIdentifier: String, engineVersion: String, localeIdentifier: String, recognizedText: String, audioDurationSeconds: TimeInterval, processingDurationSeconds: TimeInterval, units: [TimedTranscriptUnit]) throws {
        guard audioDurationSeconds.isFinite, audioDurationSeconds > 0 else { throw TimedTranscriptValidationError.invalidDuration }
        guard processingDurationSeconds.isFinite, processingDurationSeconds >= 0 else { throw TimedTranscriptValidationError.invalidProcessingDuration }
        guard !assetFingerprint.isEmpty, !engineIdentifier.isEmpty, !engineVersion.isEmpty, !localeIdentifier.isEmpty else { throw TimedTranscriptValidationError.missingIdentity }

        var previousEnd: TimeInterval?
        for (index, unit) in units.enumerated() {
            guard !unit.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TimedTranscriptValidationError.emptyText(index: index) }
            guard unit.startSeconds.isFinite, unit.endSeconds.isFinite, unit.startSeconds >= 0, unit.endSeconds > unit.startSeconds, unit.endSeconds <= audioDurationSeconds else { throw TimedTranscriptValidationError.invalidRange(index: index) }
            if let previousEnd, unit.startSeconds < previousEnd { throw TimedTranscriptValidationError.overlappingRange(index: index) }
            previousEnd = unit.endSeconds
        }

        self.assetFingerprint = assetFingerprint
        self.engineIdentifier = engineIdentifier
        self.engineVersion = engineVersion
        self.localeIdentifier = localeIdentifier
        self.recognizedText = recognizedText
        self.audioDurationSeconds = audioDurationSeconds
        self.processingDurationSeconds = processingDurationSeconds
        self.units = units
    }
}
```

Implement `TimedTranscriptIndex` with this upper-bound binary search. It returns
the preceding unit inside an internal gap, but returns `nil` before the first
start and after the final unit's end:

```swift
struct TimedTranscriptIndex: Sendable {
    private let units: [TimedTranscriptUnit]

    init(transcript: TimedTranscript) {
        units = transcript.units
    }

    func activeUnit(at mediaTime: TimeInterval) -> TimedTranscriptUnit? {
        guard mediaTime.isFinite, mediaTime >= 0, !units.isEmpty else { return nil }
        var lower = 0
        var upper = units.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if units[middle].startSeconds <= mediaTime {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower > 0 else { return nil }
        let candidateIndex = lower - 1
        let candidate = units[candidateIndex]
        if candidateIndex == units.count - 1, mediaTime >= candidate.endSeconds {
            return nil
        }
        return candidate
    }
}
```

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
make radio-compile
RADIO_TEST_SELECTOR=BriefeedTests/TimedTranscriptTests make radio-unit
```

Expected: build-for-testing succeeds and all four timed-transcript tests pass. Exit `75` means the simulator lane was unavailable; do not reinterpret it as a test failure.

- [ ] **Step 5: Commit**

```bash
git add Briefeed/Core/Transcription BriefeedTests/Transcription/TimedTranscriptTests.swift
git commit -m "feat: add timed transcript domain"
```

---

### Task 2: Apple Result Normalization and SpeechAnalyzer Engine

**Files:**
- Create: `Briefeed/Core/Transcription/TimedTranscriptEngine.swift`
- Create: `Briefeed/Core/Transcription/AppleSpeechAnalyzerEngine.swift`
- Test: `BriefeedTests/Transcription/TimedTranscriptNormalizerTests.swift`

**Interfaces:**
- Consumes: Task 1's `TimedTranscript` and `TimedTranscriptUnit`.
- Produces: `TimedTranscriptEngine.transcribe(fileURL:assetFingerprint:locale:assetPolicy:)`, `SpeechAssetPolicy`, `TimedTranscriptEngineError`, `TranscriptAttributedRun`, and `TimedTranscriptNormalizer.normalize(runs:)`.

- [ ] **Step 1: Write failing normalizer tests**

Create tests that pass engine-neutral snapshots:

```swift
import Testing
@testable import Briefeed

@Suite("Timed transcript normalizer")
struct TimedTranscriptNormalizerTests {
    @Test func preservesOneWordAndMultiwordRunGranularity() throws {
        let units = try TimedTranscriptNormalizer.normalize(runs: [
            TranscriptAttributedRun(text: " Today ", startSeconds: 0.1, endSeconds: 0.4, confidence: 0.9),
            TranscriptAttributedRun(text: "in California", startSeconds: 0.5, endSeconds: 1.2, confidence: 0.8)
        ])

        #expect(units[0] == TimedTranscriptUnit(text: "Today", startSeconds: 0.1, endSeconds: 0.4, confidence: 0.9, granularity: .word))
        #expect(units[1] == TimedTranscriptUnit(text: "in California", startSeconds: 0.5, endSeconds: 1.2, confidence: 0.8, granularity: .phrase))
    }

    @Test func dropsUntimedAndWhitespaceOnlyRunsWithoutInventingRanges() throws {
        let units = try TimedTranscriptNormalizer.normalize(runs: [
            TranscriptAttributedRun(text: " ", startSeconds: 0, endSeconds: 0.2, confidence: nil),
            TranscriptAttributedRun(text: "untimed", startSeconds: nil, endSeconds: nil, confidence: nil),
            TranscriptAttributedRun(text: "news", startSeconds: 0.3, endSeconds: 0.7, confidence: nil)
        ])
        #expect(units.map(\.text) == ["news"])
    }
}
```

- [ ] **Step 2: Run compile gate and verify RED**

Run `make radio-compile` and confirm missing normalizer/engine symbols.

- [ ] **Step 3: Implement the engine-neutral boundary**

In `TimedTranscriptEngine.swift`, define:

```swift
import Foundation

enum SpeechAssetPolicy: Equatable, Sendable {
    case installedOnly
    case allowDownload
}

enum TimedTranscriptEngineError: Error, Equatable {
    case unsupportedOS
    case engineUnavailable
    case unsupportedLocale(String)
    case assetRequired(String)
    case emptyTranscript
    case invalidAudio
}

struct TranscriptAttributedRun: Equatable, Sendable {
    let text: String
    let startSeconds: TimeInterval?
    let endSeconds: TimeInterval?
    let confidence: Double?
}

protocol TimedTranscriptEngine: Sendable {
    func transcribe(fileURL: URL, assetFingerprint: String, locale: Locale, assetPolicy: SpeechAssetPolicy) async throws -> TimedTranscript
}

enum TimedTranscriptNormalizer {
    static func normalize(runs: [TranscriptAttributedRun]) throws -> [TimedTranscriptUnit] {
        runs.compactMap { run in
            let text = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let start = run.startSeconds, let end = run.endSeconds else { return nil }
            let count = text.split(whereSeparator: \.isWhitespace).count
            return TimedTranscriptUnit(text: text, startSeconds: start, endSeconds: end, confidence: run.confidence, granularity: count == 1 ? .word : .phrase)
        }
    }
}
```

- [ ] **Step 4: Implement the iOS 26 Apple engine**

In `AppleSpeechAnalyzerEngine.swift`:

- import `AVFoundation`, `CoreMedia`, `Foundation`, and `Speech`;
- mark the concrete actor `@available(iOS 26.0, *)`;
- resolve `SpeechTranscriber.supportedLocale(equivalentTo:)`;
- construct `SpeechTranscriber` with no volatile results and attributes `[.audioTimeRange, .transcriptionConfidence]`;
- check `AssetInventory.status(forModules:)`;
- throw `.assetRequired` under `.installedOnly` when the status is not `.installed`;
- under `.allowDownload`, obtain `assetInstallationRequest(supporting:)` and await `downloadAndInstall()`;
- open the supplied URL with `AVAudioFile(forReading:)`;
- start collecting only finalized `transcriber.results` before calling `analyzeSequence(from:)`;
- call `finalizeAndFinish(through:)` when a last sample exists, otherwise call `cancelAndFinishNow()`;
- extract each attributed run using `run.audioTimeRange`, `run.transcriptionConfidence`, and `String(result.text[run.range].characters)`;
- use `CMTimeGetSeconds` for range bounds and preserve one Apple run as one `TranscriptAttributedRun`;
- concatenate every finalized result into `recognizedText`, including runs that have no audio range, before normalization;
- calculate audio duration from `audioFile.length / audioFile.processingFormat.sampleRate`;
- construct the validated `TimedTranscript` with engine identifier `apple-speech-analyzer` and an engine version containing the operating-system version;
- call `SpeechModels.endRetention()` after analysis and cancellation so model retention is not prolonged by the probe.

The implementation must not request microphone permission and must not import or call FluidAudio.

Use this concrete control flow; retain one attributed run as one timing unit:

```swift
import AVFoundation
import CoreMedia
import Foundation
import Speech

@available(iOS 26.0, *)
actor AppleSpeechAnalyzerEngine: TimedTranscriptEngine {
    func transcribe(fileURL: URL, assetFingerprint: String, locale: Locale, assetPolicy: SpeechAssetPolicy) async throws -> TimedTranscript {
        try Task.checkCancellation()
        guard SpeechTranscriber.isAvailable else { throw TimedTranscriptEngineError.engineUnavailable }
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TimedTranscriptEngineError.unsupportedLocale(locale.identifier)
        }

        let transcriber = SpeechTranscriber(
            locale: supportedLocale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence]
        )
        let modules: [any SpeechModule] = [transcriber]
        let status = await AssetInventory.status(forModules: modules)
        if status != .installed {
            guard assetPolicy == .allowDownload else {
                throw TimedTranscriptEngineError.assetRequired(supportedLocale.identifier)
            }
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await request.downloadAndInstall()
            }
            guard await AssetInventory.status(forModules: modules) == .installed else {
                throw TimedTranscriptEngineError.assetRequired(supportedLocale.identifier)
            }
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            throw TimedTranscriptEngineError.invalidAudio
        }
        let sampleRate = audioFile.processingFormat.sampleRate
        guard sampleRate > 0 else { throw TimedTranscriptEngineError.invalidAudio }
        let duration = TimeInterval(audioFile.length) / sampleRate
        let started = ProcessInfo.processInfo.systemUptime
        let analyzer = SpeechAnalyzer(modules: modules)
        let resultTask = Task<[AttributedString], Error> {
            var finalized: [AttributedString] = []
            for try await result in transcriber.results where result.isFinal {
                finalized.append(result.text)
            }
            return finalized
        }

        do {
            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            try Task.checkCancellation()
            let attributedResults = try await resultTask.value
            var recognizedParts: [String] = []
            var snapshots: [TranscriptAttributedRun] = []
            for attributed in attributedResults {
                recognizedParts.append(String(attributed.characters))
                for run in attributed.runs {
                    let text = String(attributed[run.range].characters)
                    guard let audioRange = run.audioTimeRange else {
                        snapshots.append(TranscriptAttributedRun(text: text, startSeconds: nil, endSeconds: nil, confidence: run.transcriptionConfidence))
                        continue
                    }
                    snapshots.append(TranscriptAttributedRun(
                        text: text,
                        startSeconds: CMTimeGetSeconds(audioRange.start),
                        endSeconds: CMTimeGetSeconds(CMTimeRangeGetEnd(audioRange)),
                        confidence: run.transcriptionConfidence
                    ))
                }
            }
            let recognizedText = recognizedParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let units = try TimedTranscriptNormalizer.normalize(runs: snapshots)
            guard !recognizedText.isEmpty, !units.isEmpty else { throw TimedTranscriptEngineError.emptyTranscript }
            let transcript = try TimedTranscript(
                assetFingerprint: assetFingerprint,
                engineIdentifier: "apple-speech-analyzer",
                engineVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                localeIdentifier: supportedLocale.identifier,
                recognizedText: recognizedText,
                audioDurationSeconds: duration,
                processingDurationSeconds: ProcessInfo.processInfo.systemUptime - started,
                units: units
            )
            await SpeechModels.endRetention()
            return transcript
        } catch {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            await SpeechModels.endRetention()
            throw error
        }
    }
}
```

- [ ] **Step 5: Run focused tests and compile the availability-gated implementation**

```bash
make radio-compile
RADIO_TEST_SELECTOR=BriefeedTests/TimedTranscriptNormalizerTests make radio-unit
```

Expected: build-for-testing succeeds at the iOS 18.2 deployment floor and both normalizer tests pass.

- [ ] **Step 6: Commit**

```bash
git add Briefeed/Core/Transcription BriefeedTests/Transcription/TimedTranscriptNormalizerTests.swift
git commit -m "feat: add Apple timed transcript engine"
```

---

### Task 3: DEBUG Probe, Fingerprint, and Receipt

**Files:**
- Create: `Briefeed/Core/Debug/PodcastTranscriptionProbe.swift`
- Test: `BriefeedTests/Transcription/PodcastTranscriptionProbeTests.swift`

**Interfaces:**
- Consumes: `TimedTranscriptEngine` from Task 2.
- Produces: `PodcastTranscriptionProbe.run(fileURL:referenceText:locale:assetPolicy:outputDirectory:)` and a Codable `PodcastTranscriptionReceipt`.

- [ ] **Step 1: Write failing receipt tests with an injected engine**

The mock engine returns a valid two-unit transcript. Assert that the probe:

- hashes the exact fixture bytes with lowercase SHA-256;
- passes that fingerprint to the engine;
- writes JSON using sorted keys;
- records the OS version, created date, covered-character ratio, median words per unit, word-unit count, and phrase-unit count;
- reports zero word error for an exact reference, insertion/deletion/substitution edits for a changed reference, and `nil` when no reference is supplied;
- propagates engine failures without creating a success receipt.

The mock records the received URL, fingerprint, locale identifier, and asset policy so the test verifies the boundary instead of reimplementing it.

- [ ] **Step 2: Run compile gate and verify RED**

Run `make radio-compile` and confirm the probe symbols are missing.

- [ ] **Step 3: Implement the probe**

Define the receipt shape exactly:

```swift
struct PodcastTranscriptionReceipt: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let createdAt: Date
    let operatingSystemVersion: String
    let transcript: TimedTranscript
    let recognizedCharacterCount: Int
    let timedCharacterCount: Int
    let timingCoverage: Double
    let medianWordsPerUnit: Double
    let wordUnitCount: Int
    let phraseUnitCount: Int
    let referenceWordErrorRate: Double?
}
```

`PodcastTranscriptionProbe` accepts an injected `any TimedTranscriptEngine` and
an optional reference script. Implement normalized word error rate with a pure
Levenshtein distance over lowercased alphanumeric words; divide edit distance
by the reference word count and return `nil` when no reference is supplied.
Read fixture data, calculate `SHA256.hash(data:)`, call the engine, calculate
metrics from normalized text, create the output directory, and atomically write
`transcript-<first 12 fingerprint characters>.json`. Use
`JSONEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]` and ISO-8601 date
encoding.

Keep the file in `Briefeed/Core/Debug` and wrap concrete diagnostic entrypoints
in `#if DEBUG`; the pure receipt type and injected initializer remain testable.

- [ ] **Step 4: Run focused tests and verify GREEN**

```bash
make radio-compile
RADIO_TEST_SELECTOR=BriefeedTests/PodcastTranscriptionProbeTests make radio-unit
```

Expected: compile succeeds and all probe tests pass without a model download.

- [ ] **Step 5: Commit**

```bash
git add Briefeed/Core/Debug/PodcastTranscriptionProbe.swift BriefeedTests/Transcription/PodcastTranscriptionProbeTests.swift
git commit -m "feat: add timed transcript diagnostic receipt"
```

---

### Task 4: Rights-Cleared Fixture and Explicit Simulator Integration Probe

**Files:**
- Create: `BriefeedTests/Fixtures/Transcription/apple-news-script.txt`
- Generate: `BriefeedTests/Fixtures/Transcription/apple-news-fixture.aiff`
- Create: `BriefeedTests/Transcription/AppleSpeechAnalyzerIntegrationTests.swift`
- Create: `skills/app-testing/scripts/make-transcript-fixture.sh`
- Create: `skills/app-testing/scripts/run-transcript-probe.sh`

**Interfaces:**
- Consumes: Tasks 1-3 and the existing owned simulator runner.
- Produces: one repeatable integration command and one JSON receipt copied from the simulator test result.

- [ ] **Step 1: Add the known script and deterministic generator**

The script text must contain 160-200 original words in a neutral public-radio
style, including numbers, names, punctuation, and one deliberate pause between
paragraphs. It must not quote a real broadcast.

`make-transcript-fixture.sh` must:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT/BriefeedTests/Fixtures/Transcription/apple-news-script.txt"
OUTPUT="$ROOT/BriefeedTests/Fixtures/Transcription/apple-news-fixture.aiff"
mkdir -p "$(dirname "$OUTPUT")"
/usr/bin/say -v Samantha -r 150 -f "$SCRIPT" -o "$OUTPUT" --file-format=AIFF --data-format=LEI16@22050
/usr/bin/afinfo "$OUTPUT" | /usr/bin/grep -q 'estimated duration'
```

Run it once and commit the generated AIFF. Confirm the Xcode synchronized test
group copies it into `BriefeedTests.xctest`; do not add manual project UUIDs
unless the build proves automatic resource discovery failed.

- [ ] **Step 2: Write the integration test**

Use XCTest so unsupported environments can throw `XCTSkip`:

```swift
import XCTest
@testable import Briefeed

final class AppleSpeechAnalyzerIntegrationTests: XCTestCase {
    func testRightsClearedFixtureProducesTimedReceipt() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("SpeechAnalyzer requires iOS 26") }
        guard ProcessInfo.processInfo.environment["BRIEFEED_TRANSCRIPT_ALLOW_ASSET_DOWNLOAD"] == "1" else {
            throw XCTSkip("Run through run-transcript-probe.sh to permit the system asset request")
        }
        let bundle = Bundle(for: Self.self)
        guard let fixture = bundle.url(forResource: "apple-news-fixture", withExtension: "aiff", subdirectory: "Fixtures/Transcription")
                ?? bundle.url(forResource: "apple-news-fixture", withExtension: "aiff") else {
            XCTFail("apple-news-fixture.aiff is missing from BriefeedTests.xctest")
            return
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("BriefeedTranscriptProbe", isDirectory: true)
        let probe = PodcastTranscriptionProbe(engine: AppleSpeechAnalyzerEngine())
        guard let script = bundle.url(forResource: "apple-news-script", withExtension: "txt", subdirectory: "Fixtures/Transcription")
                ?? bundle.url(forResource: "apple-news-script", withExtension: "txt") else {
            XCTFail("apple-news-script.txt is missing from BriefeedTests.xctest")
            return
        }
        let referenceText = try String(contentsOf: script, encoding: .utf8)
        let receiptURL = try await probe.run(fileURL: fixture, referenceText: referenceText, locale: Locale(identifier: "en-US"), assetPolicy: .allowDownload, outputDirectory: output)
        let receipt = try JSONDecoder().decode(PodcastTranscriptionReceipt.self, from: Data(contentsOf: receiptURL))

        XCTAssertFalse(receipt.transcript.units.isEmpty)
        XCTAssertGreaterThanOrEqual(receipt.timingCoverage, 0.95)
        XCTAssertLessThanOrEqual(receipt.medianWordsPerUnit, 4)
        XCTAssertLessThanOrEqual(try XCTUnwrap(receipt.referenceWordErrorRate), 0.20)
        XCTAssertTrue(receipt.transcript.units.allSatisfy { $0.startSeconds >= 0 && $0.endSeconds <= receipt.transcript.audioDurationSeconds })
        print("BRIEFEED_TRANSCRIPT_RECEIPT=\(receiptURL.path)")
    }
}
```

Add a second integration test using the same fixture. It must finish with
`CancellationError` and must not hang:

```swift
func testCancellationFinishesWithoutHanging() async throws {
    guard #available(iOS 26.0, *) else { throw XCTSkip("SpeechAnalyzer requires iOS 26") }
    guard ProcessInfo.processInfo.environment["BRIEFEED_TRANSCRIPT_ALLOW_ASSET_DOWNLOAD"] == "1" else {
        throw XCTSkip("Run through run-transcript-probe.sh")
    }
    let bundle = Bundle(for: Self.self)
    let fixture = try XCTUnwrap(
        bundle.url(forResource: "apple-news-fixture", withExtension: "aiff", subdirectory: "Fixtures/Transcription")
            ?? bundle.url(forResource: "apple-news-fixture", withExtension: "aiff")
    )
    let task = Task {
        try await AppleSpeechAnalyzerEngine().transcribe(
            fileURL: fixture,
            assetFingerprint: "cancellation-probe",
            locale: Locale(identifier: "en-US"),
            assetPolicy: .allowDownload
        )
    }
    try await Task.sleep(for: .milliseconds(50))
    task.cancel()
    do {
        _ = try await task.value
        XCTFail("Cancelled transcription unexpectedly completed")
    } catch is CancellationError {
        return
    }
}
```

- [ ] **Step 3: Add the owned-simulator runner**

`run-transcript-probe.sh` must regenerate the fixture, set
`BRIEFEED_TRANSCRIPT_ALLOW_ASSET_DOWNLOAD=1`, select only
`BriefeedTests/AppleSpeechAnalyzerIntegrationTests`, and delegate to:

```bash
RADIO_TEST_SELECTOR=BriefeedTests/AppleSpeechAnalyzerIntegrationTests \
  bash "$ROOT/skills/app-testing/scripts/run-radio.sh" transcript-probe unit
```

It must not call `simctl shutdown all`, erase a simulator, choose the first
booted simulator, or interact with a physical device.

- [ ] **Step 4: Run script checks and compile**

```bash
bash -n skills/app-testing/scripts/make-transcript-fixture.sh
bash -n skills/app-testing/scripts/run-transcript-probe.sh
bash skills/app-testing/scripts/make-transcript-fixture.sh
make radio-compile
```

Expected: both scripts parse, `afinfo` accepts the generated fixture, and the
project builds for testing.

- [ ] **Step 5: Run the integration probe**

```bash
bash skills/app-testing/scripts/run-transcript-probe.sh
```

Expected outcomes are deliberately strict:

- PASS only when a nonempty receipt meets timing coverage and unit-size gates;
- XCTSkip when SpeechAnalyzer or its model asset is unavailable;
- exit `75` when shared simulator capacity is unavailable;
- FAIL for malformed ranges, a missing fixture, empty transcription, or a gate miss.

- [ ] **Step 6: Commit**

```bash
git add BriefeedTests/Fixtures/Transcription BriefeedTests/Transcription/AppleSpeechAnalyzerIntegrationTests.swift skills/app-testing/scripts
git commit -m "test: add Apple timed transcript probe"
```

---

### Task 5: Verification Receipt and Engine Decision

**Files:**
- Create after execution: `docs/research/receipts/2026-07-21-apple-speech-transcript-probe.md`
- Modify: `docs/research/2026-07-20-podcast-ad-skip-spike.md`
- Modify: GitHub issue #10 with a comment; do not close it.

**Interfaces:**
- Consumes: the actual Task 4 JSON receipt and test output.
- Produces: an evidence-backed decision to proceed with Apple, compare Parakeet, or stop.

- [ ] **Step 1: Run all focused deterministic tests**

```bash
make radio-compile
RADIO_TEST_SELECTOR=BriefeedTests/TimedTranscriptTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/TimedTranscriptNormalizerTests make radio-unit
RADIO_TEST_SELECTOR=BriefeedTests/PodcastTranscriptionProbeTests make radio-unit
```

Record exact pass, failure, skip, or exit-75 results.

- [ ] **Step 2: Run the integration probe once**

Run `bash skills/app-testing/scripts/run-transcript-probe.sh`. Do not rerun until
it happens to pass. Preserve the first valid product result or infrastructure
status and its JSON receipt.

- [ ] **Step 3: Write the research receipt from actual evidence**

The Markdown receipt must include:

- commit SHA, Xcode build, simulator model and OS;
- fixture duration and SHA-256;
- Apple locale and asset status;
- processing duration and real-time factor;
- recognized and timed character counts, timing coverage, and fixture word error rate;
- word versus phrase unit counts and median words per unit;
- whether one-word RSVP remains technically supported by the observed runs;
- simulator limitations and the still-unrun physical memory, thermal, audio,
  interruption, and visual-drift checks;
- verdict `APPLE_PROCEED`, `PARAKEET_COMPARISON_REQUIRED`, or `INCONCLUSIVE`.

Do not claim audible synchronization or phone performance from a simulator
receipt.

- [ ] **Step 4: Update research tracking**

Link the receipt from `docs/research/2026-07-20-podcast-ad-skip-spike.md` and
comment on GitHub issue #10 with the commit and verdict. Keep ad classification
and automatic skipping out of scope.

- [ ] **Step 5: Run final repository gates**

```bash
git diff --check
make radio-compile
git status --short --branch
```

If Task 4 obtained a simulator lane, rerun the complete focused transcript test
selection once. Do not claim the broad legacy test target is green.

- [ ] **Step 6: Commit, rebase, and push**

```bash
git add docs/research
git commit -m "docs: record Apple transcript probe"
git pull --rebase
git push
git status --short --branch
```

Expected final status: clean and up to date with `origin/codex/live-radio-mvp`.

## Production Follow-Up Gate

Do not begin episode downloading, transcript persistence, or Radio UI work from
this plan. If the verdict is `APPLE_PROCEED`, write a second approved design for
the production cache/transcription coordinator and the one-word versus
two-line presentation settings. If the verdict is
`PARAKEET_COMPARISON_REQUIRED`, first create an isolated FluidAudio `0.15.5`
upgrade plan that proves PocketTTS regressions are contained.
