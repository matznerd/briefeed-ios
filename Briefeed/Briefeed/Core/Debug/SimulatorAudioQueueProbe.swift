//
//  SimulatorAudioQueueProbe.swift
//  Briefeed
//
//  DEBUG-only simulator proof hook for exercising the unified audio queue.
//

#if DEBUG
import AVFoundation
import CoreData
import Foundation

@MainActor
enum SimulatorAudioQueueProbe {
    private static let envKey = "BRIEFEED_SIM_PROBE"
    private static let launchArg = "--briefeed-sim-probe"
    private static let mode = "audio-queue"
    private static let logPrefix = "[BriefeedSimProbe]"

    static func runIfRequested(audioPlayerViewModel: AudioPlayerViewModelV2) async {
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        let requestedMode = environment[envKey]

        guard requestedMode == mode || arguments.contains(launchArg) else {
            return
        }

        do {
            print("\(logPrefix) START mode=\(requestedMode ?? launchArg)")

            let context = PersistenceController.shared.container.viewContext
            let audioURL = try makeProofAudioFile()
            let episode = try makeProofEpisode(audioURL: audioURL, context: context)

            await audioPlayerViewModel.clearQueue()
            await audioPlayerViewModel.addToQueue(episode, playNow: true)

            try? await Task.sleep(for: .milliseconds(1200))

            let queueTitles = audioPlayerViewModel.queueItems.map(\.title)
            print("\(logPrefix) QUEUE count=\(audioPlayerViewModel.queueItems.count) titles=\(queueTitles)")
            print("\(logPrefix) PLAYER title=\(audioPlayerViewModel.currentTitle ?? "nil") isPlaying=\(audioPlayerViewModel.isPlaying) duration=\(audioPlayerViewModel.duration) speed=\(audioPlayerViewModel.playbackSpeed)")
            print("\(logPrefix) COMPLETE")
        } catch {
            print("\(logPrefix) FAILED \(error.localizedDescription)")
        }
    }

    private static func makeProofEpisode(audioURL: URL, context: NSManagedObjectContext) throws -> RSSEpisode {
        let feedID = "debug-simulator-audio-feed"
        let episodeID = "debug-simulator-audio-episode"

        let feedFetch: NSFetchRequest<RSSFeed> = RSSFeed.fetchRequest()
        feedFetch.predicate = NSPredicate(format: "id == %@", feedID)
        feedFetch.fetchLimit = 1

        let feed = try context.fetch(feedFetch).first ?? RSSFeed(context: context)
        feed.id = feedID
        feed.url = "file://debug-simulator-audio-feed"
        feed.displayName = "Simulator Proof Audio"
        feed.updateFrequency = "manual"
        feed.priority = 0
        feed.isEnabled = true
        feed.createdDate = Date()

        let episodeFetch: NSFetchRequest<RSSEpisode> = RSSEpisode.fetchRequest()
        episodeFetch.predicate = NSPredicate(format: "id == %@", episodeID)
        episodeFetch.fetchLimit = 1

        let episode = try context.fetch(episodeFetch).first ?? RSSEpisode(context: context)
        episode.id = episodeID
        episode.feedId = feedID
        episode.title = "Simulator Proof Audio Episode"
        episode.audioUrl = audioURL.absoluteString
        episode.pubDate = Date()
        episode.duration = 12
        episode.episodeDescription = "Local generated audio used to prove the unified player path in simulator."
        episode.isListened = false
        episode.listenedDate = nil
        episode.lastPosition = 0
        episode.hasBeenQueued = false
        episode.downloadedFilePath = audioURL.path
        episode.feed = feed

        if context.hasChanges {
            try context.save()
        }

        return episode
    }

    private static func makeProofAudioFile() throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("briefeed-simulator-proof-audio")
            .appendingPathExtension("caf")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let sampleRate = 44_100.0
        let duration = 12.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(sampleRate * duration)
              ),
              let channelData = buffer.floatChannelData?.pointee else {
            throw ProbeError.audioBufferSetupFailed
        }

        buffer.frameLength = buffer.frameCapacity

        for frame in 0..<Int(buffer.frameLength) {
            let seconds = Double(frame) / sampleRate
            let envelope = min(1.0, seconds / 0.15, (duration - seconds) / 0.15)
            channelData[frame] = Float(sin(2.0 * .pi * 440.0 * seconds) * 0.04 * max(0.0, envelope))
        }

        let audioFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
        try audioFile.write(from: buffer)
        return outputURL
    }

    private enum ProbeError: LocalizedError {
        case audioBufferSetupFailed

        var errorDescription: String? {
            "Unable to create simulator proof audio buffer"
        }
    }
}
#endif
