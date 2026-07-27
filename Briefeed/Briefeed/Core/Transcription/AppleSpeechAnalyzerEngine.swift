import AVFoundation
import CoreMedia
import Foundation
import Speech

@available(iOS 26.0, *)
actor AppleSpeechAnalyzerEngine: TimedTranscriptEngine {
    func transcribe(
        fileURL: URL,
        assetFingerprint: String,
        locale: Locale,
        assetPolicy: SpeechAssetPolicy
    ) async throws -> TimedTranscript {
        try await transcribe(
            fileURL: fileURL,
            assetFingerprint: assetFingerprint,
            locale: locale,
            assetPolicy: assetPolicy,
            onProgress: { _ in }
        )
    }

    func transcribe(
        fileURL: URL,
        assetFingerprint: String,
        locale: Locale,
        assetPolicy: SpeechAssetPolicy,
        onProgress: @escaping TimedTranscriptProgressHandler
    ) async throws -> TimedTranscript {
        try Task.checkCancellation()
        guard SpeechTranscriber.isAvailable else {
            throw TimedTranscriptEngineError.engineUnavailable
        }
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
        guard sampleRate > 0 else {
            throw TimedTranscriptEngineError.invalidAudio
        }
        let duration = TimeInterval(audioFile.length) / sampleRate
        let started = ProcessInfo.processInfo.systemUptime
        let analyzer = SpeechAnalyzer(modules: modules)
        let engineVersion =
            ProcessInfo.processInfo.operatingSystemVersionString
        let resultTask = Task<AppleTranscriptAccumulator, Error> {
            var accumulator = AppleTranscriptAccumulator()
            for try await result in transcriber.results where result.isFinal {
                accumulator.append(
                    text: result.text,
                    finalizedThroughSeconds:
                        CMTimeGetSeconds(result.resultsFinalizationTime)
                )
                if let progress = try accumulator.progress(
                    assetFingerprint: assetFingerprint,
                    engineVersion: engineVersion,
                    localeIdentifier: supportedLocale.identifier,
                    audioDurationSeconds: duration,
                    processingDurationSeconds:
                        ProcessInfo.processInfo.systemUptime - started
                ) {
                    await onProgress(progress)
                }
            }
            return accumulator
        }

        do {
            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            try Task.checkCancellation()

            let accumulator = try await resultTask.value
            guard let transcript = try accumulator.transcript(
                assetFingerprint: assetFingerprint,
                engineVersion: engineVersion,
                localeIdentifier: supportedLocale.identifier,
                audioDurationSeconds: duration,
                processingDurationSeconds:
                    ProcessInfo.processInfo.systemUptime - started
            ) else {
                throw TimedTranscriptEngineError.emptyTranscript
            }
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

@available(iOS 26.0, *)
private struct AppleTranscriptAccumulator: Sendable {
    private(set) var recognizedParts: [String] = []
    private(set) var runs: [TranscriptAttributedRun] = []
    private(set) var finalizedThroughSeconds: TimeInterval = 0

    mutating func append(
        text attributed: AttributedString,
        finalizedThroughSeconds: TimeInterval
    ) {
        recognizedParts.append(String(attributed.characters))
        if finalizedThroughSeconds.isFinite {
            self.finalizedThroughSeconds = max(
                self.finalizedThroughSeconds,
                finalizedThroughSeconds
            )
        }
        for run in attributed.runs {
            let text = String(attributed[run.range].characters)
            let audioRange = run.audioTimeRange
            runs.append(
                TranscriptAttributedRun(
                    text: text,
                    startSeconds: audioRange.map {
                        CMTimeGetSeconds($0.start)
                    },
                    endSeconds: audioRange.map {
                        CMTimeGetSeconds(CMTimeRangeGetEnd($0))
                    },
                    confidence: run.transcriptionConfidence
                )
            )
        }
    }

    func progress(
        assetFingerprint: String,
        engineVersion: String,
        localeIdentifier: String,
        audioDurationSeconds: TimeInterval,
        processingDurationSeconds: TimeInterval
    ) throws -> TimedTranscriptProgress? {
        guard let transcript = try transcript(
            assetFingerprint: assetFingerprint,
            engineVersion: engineVersion,
            localeIdentifier: localeIdentifier,
            audioDurationSeconds: audioDurationSeconds,
            processingDurationSeconds: processingDurationSeconds
        ) else {
            return nil
        }
        return TimedTranscriptProgress(
            transcript: transcript,
            finalizedThroughSeconds: finalizedThroughSeconds
        )
    }

    func transcript(
        assetFingerprint: String,
        engineVersion: String,
        localeIdentifier: String,
        audioDurationSeconds: TimeInterval,
        processingDurationSeconds: TimeInterval
    ) throws -> TimedTranscript? {
        let recognizedText = recognizedParts
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let units = try TimedTranscriptNormalizer.normalize(runs: runs)
        guard !recognizedText.isEmpty, !units.isEmpty else { return nil }
        return try TimedTranscript(
            assetFingerprint: assetFingerprint,
            engineIdentifier: "apple-speech-analyzer",
            engineVersion: engineVersion,
            localeIdentifier: localeIdentifier,
            recognizedText: recognizedText,
            audioDurationSeconds: audioDurationSeconds,
            processingDurationSeconds: processingDurationSeconds,
            units: units
        )
    }
}
