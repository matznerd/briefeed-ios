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

    @Test func invalidLocalReplacementDetachesOldPlayerBeforeThrowing() async throws {
        let service = SwiftAudioExService(systemIntegrationEnabled: false)
        let delegate = CompletionDelegateSpy()
        let oldID = TransportPlaybackID()
        service.delegate = delegate
        service.installActivePlaybackForTesting(id: oldID)
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        await #expect(throws: Error.self) {
            try await service.play(id: TransportPlaybackID(), url: missing, title: nil, artist: nil)
        }
        service.receivePlaybackEnd(id: oldID, reason: .playedUntilEnd)

        #expect(delegate.completions.isEmpty)
    }

    @Test func offMainInterruptionAndRouteDeliveryHopToMainActor() async {
        let service = SwiftAudioExService(systemIntegrationEnabled: false)
        let delegate = CompletionDelegateSpy()
        service.delegate = delegate

        await Task.detached {
            service.deliverInterruptionForTesting(began: true, shouldResume: false)
            service.deliverRouteRemovalForTesting()
        }.value
        for _ in 0..<4 { await Task.yield() }

        #expect(delegate.interruptionBeganCount == 1)
        #expect(delegate.routeRemovalCount == 1)
    }
}

private enum CompletionTestError: Error { case failed }

@MainActor
private final class CompletionDelegateSpy: SwiftAudioExServiceDelegate {
    var completions: [(TransportPlaybackID, Bool)] = []
    var interruptionBeganCount = 0
    var routeRemovalCount = 0
    func audioItemReady(id: TransportPlaybackID, duration: TimeInterval) {}
    func audioStateChanged(id: TransportPlaybackID, to newState: SwiftAudioPlayerState, from oldState: SwiftAudioPlayerState) {}
    func audioProgressUpdated(id: TransportPlaybackID, progress: Float, currentTime: TimeInterval, duration: TimeInterval) {}
    func audioDidFinishPlaying(id: TransportPlaybackID, successfully: Bool) { completions.append((id, successfully)) }
    func audioInterruptionBegan(id: TransportPlaybackID?) { interruptionBeganCount += 1 }
    func audioInterruptionEnded(id: TransportPlaybackID?, shouldResume: Bool) {}
    func audioRouteWasRemoved(id: TransportPlaybackID?) { routeRemovalCount += 1 }
    func audioRequestPlay() {}
    func audioRequestPause() {}
    func audioRequestSeek(to seconds: TimeInterval) {}
    func audioRequestSkipBackward(seconds: TimeInterval) {}
    func audioRequestSkipForward(seconds: TimeInterval) {}
    func audioRequestNextTrack() {}
    func audioRequestRate(_ rate: Float) {}
}
