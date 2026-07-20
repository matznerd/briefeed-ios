import Foundation
import Testing
@testable import Briefeed

@Suite("Radio empty-state precedence")
@MainActor
struct RadioEmptyStateTests {
    @Test func allSourcesFailedIsNotCaughtUp() async {
        let coordinator = makeCoordinator(candidates: [], online: .online)
        _ = await coordinator.restore(autoplayEnabled: true)
        coordinator.refreshStarted(enabledSourceCount: 2)
        coordinator.applyRefresh(.init(results: [.init(feedID: "npr", outcome: .failed(message: "503")), .init(feedID: "bbc", outcome: .failed(message: "timeout"))]))
        #expect(coordinator.state == .failed(.allSourcesUnavailable))
        #expect(coordinator.state != .exhausted)
    }

    @Test func oneFailedSourceDoesNotMakeSeveralSourcesUnavailable() async {
        let coordinator = makeCoordinator(candidates: [], online: .online)
        _ = await coordinator.restore(autoplayEnabled: false)
        coordinator.refreshStarted(enabledSourceCount: 2)
        coordinator.applyRefresh(.init(results: [.init(feedID: "npr", outcome: .failed(message: "503"))]))
        #expect(coordinator.state == .refreshing)
    }

    @Test func emptyStateUsesExactPrecedenceAndSkippedFreshCountsAsSuccess() async {
        let noSources = makeCoordinator(candidates: [], online: .online)
        _ = await noSources.restore(autoplayEnabled: false)
        noSources.refreshStarted(enabledSourceCount: 0)
        #expect(noSources.state == .noSources)

        let offline = makeCoordinator(candidates: [], online: .offline)
        _ = await offline.restore(autoplayEnabled: false)
        offline.refreshStarted(enabledSourceCount: 2)
        #expect(offline.state == .waitingForNetwork)

        let unknown = makeCoordinator(candidates: [], online: .unknown)
        _ = await unknown.restore(autoplayEnabled: false)
        unknown.refreshStarted(enabledSourceCount: 2)
        unknown.applyRefresh(.init(results: [.init(feedID: "npr", outcome: .skippedFresh(lastSuccessfulRefresh: Date()))]))
        #expect(unknown.state == .refreshing)

        let exhausted = makeCoordinator(candidates: [], online: .online)
        _ = await exhausted.restore(autoplayEnabled: false)
        exhausted.refreshStarted(enabledSourceCount: 2)
        exhausted.applyRefresh(.init(results: [.init(feedID: "npr", outcome: .skippedFresh(lastSuccessfulRefresh: Date()))]))
        #expect(exhausted.state == .exhausted)
    }

    @Test func failuresAreDegradedEvidenceButDoNotReplaceActivePlayback() async {
        let candidate = RadioEpisodeCandidate(key: .init(feedID: "npr", episodeID: "one"), originalPlaybackURL: URL(string: "https://example.com/one.mp3")!, canonicalEnclosureURL: "https://example.com/one.mp3", title: "one", sourceName: "NPR", publicationDate: Date(), durationSeconds: 60, normalizedCoreDataProgress: 0, isCompleted: false, sourcePriority: 0, sourceFrequency: .hourly)
        let coordinator = makeCoordinator(candidates: [candidate], online: .online)
        _ = await coordinator.restore(autoplayEnabled: false)
        #expect(coordinator.beginCurrent() != nil)
        coordinator.refreshStarted(enabledSourceCount: 1)
        coordinator.applyRefresh(.init(results: [.init(feedID: "npr", outcome: .failed(message: "503"))]))
        #expect(coordinator.state == .loading)
        #expect(coordinator.sourceFailures == ["npr": "503"])
    }

    private func makeCoordinator(candidates: [RadioEpisodeCandidate], online: ConnectivityStatus) -> RadioSessionCoordinator {
        RadioSessionCoordinator(store: FakeRadioSessionStore(), repository: FakeRadioEpisodeRepository(candidates: candidates), now: Date.init, connectivityStatus: { online })
    }
}
