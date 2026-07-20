import Testing
@testable import Briefeed

@Suite("Radio home presentation")
struct RadioHomePresentationTests {
    @Test(arguments: [
        RadioSessionState.readyPaused,
        .loading,
        .playing,
        .pausedByUser
    ])
    func degradedBannerAppearsOnlyForPlayableCurrentStates(state: RadioSessionState) {
        #expect(RadioHomePresentation.showsDegradedBanner(
            state: state,
            activeMode: .radio,
            hasCurrentEpisode: true,
            sourceFailureCount: 1
        ))
    }

    @Test(arguments: [
        RadioSessionState.noSources,
        .exhausted,
        .failed(.allSourcesUnavailable),
        .waitingForNetwork,
        .refreshing
    ])
    func degradedBannerIsHiddenForTerminalAndUnplayableStates(state: RadioSessionState) {
        #expect(!RadioHomePresentation.showsDegradedBanner(
            state: state,
            activeMode: .radio,
            hasCurrentEpisode: true,
            sourceFailureCount: 1
        ))
    }

    @Test func degradedBannerNeedsBothCurrentEpisodeAndFailures() {
        #expect(!RadioHomePresentation.showsDegradedBanner(
            state: .playing,
            activeMode: .radio,
            hasCurrentEpisode: false,
            sourceFailureCount: 1
        ))
        #expect(!RadioHomePresentation.showsDegradedBanner(
            state: .playing,
            activeMode: .radio,
            hasCurrentEpisode: true,
            sourceFailureCount: 0
        ))
        #expect(!RadioHomePresentation.showsDegradedBanner(
            state: .playing,
            activeMode: .brief,
            hasCurrentEpisode: true,
            sourceFailureCount: 1
        ))
    }

    @Test func currentControlLabelMatchesRadioActivePlaybackPredicate() {
        #expect(RadioHomePresentation.currentControlLabel(activeMode: .radio, isPlaying: true) == "Pause Radio")
        #expect(RadioHomePresentation.currentControlLabel(activeMode: .brief, isPlaying: true) == "Play Radio")
        #expect(RadioHomePresentation.currentControlLabel(activeMode: .radio, isPlaying: false) == "Play Radio")
    }

    @Test func allSourceFailureRefreshesSourcesWhileTransportFailuresRetryPlayback() {
        #expect(RadioHomePresentation.failureRecovery(for: .allSourcesUnavailable) == .refreshSources)
        #expect(RadioHomePresentation.failureRecovery(for: .playback("failed")) == .retryPlayback)
        #expect(RadioHomePresentation.failureRecovery(for: .persistence("failed")) == .retryPlayback)
    }
}
