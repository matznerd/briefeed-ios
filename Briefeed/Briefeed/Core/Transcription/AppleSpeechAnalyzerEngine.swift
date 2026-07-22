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
                        snapshots.append(
                            TranscriptAttributedRun(
                                text: text,
                                startSeconds: nil,
                                endSeconds: nil,
                                confidence: run.transcriptionConfidence
                            )
                        )
                        continue
                    }

                    snapshots.append(
                        TranscriptAttributedRun(
                            text: text,
                            startSeconds: CMTimeGetSeconds(audioRange.start),
                            endSeconds: CMTimeGetSeconds(CMTimeRangeGetEnd(audioRange)),
                            confidence: run.transcriptionConfidence
                        )
                    )
                }
            }

            let recognizedText = recognizedParts
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let units = try TimedTranscriptNormalizer.normalize(runs: snapshots)
            guard !recognizedText.isEmpty, !units.isEmpty else {
                throw TimedTranscriptEngineError.emptyTranscript
            }
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
