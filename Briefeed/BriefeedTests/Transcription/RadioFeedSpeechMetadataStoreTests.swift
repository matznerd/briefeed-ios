import Foundation
import Testing
@testable import Briefeed

@Suite("Radio feed speech metadata store")
struct RadioFeedSpeechMetadataStoreTests {
    @Test func normalizesPublisherLanguageAndPersistsAcrossRelaunch() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try RadioFeedSpeechMetadataStore(fileURL: root.appendingPathComponent("speech.json"))

        try await writer.setLanguageTag("pt_BR", source: .publisher, for: "feed")

        let reader = try RadioFeedSpeechMetadataStore(fileURL: root.appendingPathComponent("speech.json"))
        #expect(await reader.metadata(for: "feed") == .init(
            languageTag: "pt-BR",
            source: .publisher
        ))
    }

    @Test func publisherMetadataCannotBeReplacedByASeedOrFallback() async throws {
        let store = InMemoryRadioFeedSpeechMetadataStore()

        try await store.setLanguageTag("fr_CA", source: .publisher, for: "feed")
        try await store.setLanguageTag("en-US", source: .seed, for: "feed")
        try await store.setLanguageTag(nil, source: .fallback, for: "feed")

        #expect(await store.metadata(for: "feed") == .init(
            languageTag: "fr-CA",
            source: .publisher
        ))
    }

    @Test func absentAndInvalidMetadataUseDeterministicEnglishFallback() async throws {
        let store = InMemoryRadioFeedSpeechMetadataStore()
        try await store.setLanguageTag("not_a_locale!", source: .publisher, for: "invalid")

        #expect(await store.metadata(for: "missing") == .init(
            languageTag: "en-US",
            source: .fallback
        ))
        #expect(await store.metadata(for: "invalid") == .init(
            languageTag: "en-US",
            source: .fallback
        ))
    }

    @Test func corruptFileFallsBackWithoutAffectingOtherAppState() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("speech.json")
        try Data("bad-json".utf8).write(to: fileURL)

        let store = try RadioFeedSpeechMetadataStore(fileURL: fileURL)

        #expect(await store.metadata(for: "feed") == .init(
            languageTag: "en-US",
            source: .fallback
        ))
    }

    @Test(arguments: [
        ("en_US", "en-US"),
        ("PT-br", "pt-BR"),
        ("zh_hant_tw", "zh-Hant-TW"),
        ("es-419", "es-419")
    ])
    func normalizationProducesStableBCP47(raw: String, expected: String) {
        #expect(RadioFeedSpeechMetadata.normalizedLanguageTag(raw) == expected)
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RadioFeedSpeechMetadataStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
