import Foundation
import SwiftAudioEx
import Testing
@testable import Briefeed

@Suite("Audio completion routing")
@MainActor
struct AudioCompletionRoutingTests {
    @Test func naturalEndEmitsExactlyOneIdentityBoundCompletion() {
        let service = SwiftAudioExService(systemIntegrationEnabled: false)
        let delegate = CompletionDelegateSpy()
        let id = TransportPlaybackID()
        service.delegate = delegate

        service.receivePlaybackEnd(id: id, reason: .playedUntilEnd)
        service.receivePlaybackEnd(id: id, reason: .playedUntilEnd)

        #expect(delegate.completions.count == 1)
        #expect(delegate.completions.first?.0 == id)
        #expect(delegate.completions.first?.1 == true)
    }

    @Test func failureConsumesLaterNaturalEndEvenWhenDeliveredOffMain() async {
        let service = SwiftAudioExService(systemIntegrationEnabled: false)
        let delegate = CompletionDelegateSpy()
        let id = TransportPlaybackID()
        service.delegate = delegate

        await Task.detached {
            await service.receiveFailure(id: id, error: CompletionTestError.failed)
            await service.receivePlaybackEnd(id: id, reason: .playedUntilEnd)
        }.value

        #expect(delegate.completions.count == 1)
        #expect(delegate.completions.first?.0 == id)
        #expect(delegate.completions.first?.1 == false)
    }

    @Test func expectedReplacementStopSuppressesEveryLaterTerminalCallback() {
        let service = SwiftAudioExService(systemIntegrationEnabled: false)
        let delegate = CompletionDelegateSpy()
        let id = TransportPlaybackID()
        service.delegate = delegate
        service.recordExpectedStop(id: id)

        service.receiveFailure(id: id, error: CompletionTestError.failed)
        service.receivePlaybackEnd(id: id, reason: .playedUntilEnd)

        #expect(delegate.completions.isEmpty)
    }
}

private enum CompletionTestError: Error { case failed }

@MainActor
private final class CompletionDelegateSpy: SwiftAudioExServiceDelegate {
    var completions: [(TransportPlaybackID, Bool)] = []
    func audioItemReady(id: TransportPlaybackID, duration: TimeInterval) {}
    func audioStateChanged(id: TransportPlaybackID, to newState: SwiftAudioPlayerState, from oldState: SwiftAudioPlayerState) {}
    func audioProgressUpdated(id: TransportPlaybackID, progress: Float, currentTime: TimeInterval, duration: TimeInterval) {}
    func audioDidFinishPlaying(id: TransportPlaybackID, successfully: Bool) { completions.append((id, successfully)) }
    func audioInterruptionBegan(id: TransportPlaybackID?) {}
    func audioInterruptionEnded(id: TransportPlaybackID?, shouldResume: Bool) {}
    func audioRouteWasRemoved(id: TransportPlaybackID?) {}
    func audioRequestPlay() {}
    func audioRequestPause() {}
    func audioRequestSeek(to seconds: TimeInterval) {}
    func audioRequestSkipBackward(seconds: TimeInterval) {}
    func audioRequestSkipForward(seconds: TimeInterval) {}
    func audioRequestNextTrack() {}
    func audioRequestRate(_ rate: Float) {}
}
