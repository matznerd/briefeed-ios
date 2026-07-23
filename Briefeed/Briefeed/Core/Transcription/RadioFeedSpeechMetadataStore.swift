import Foundation

enum RadioFeedSpeechMetadataSource: String, Codable, Equatable, Sendable {
    case fallback
    case seed
    case publisher

    fileprivate var priority: Int {
        switch self {
        case .fallback: 0
        case .seed: 1
        case .publisher: 2
        }
    }
}

struct RadioFeedSpeechMetadata: Codable, Equatable, Sendable {
    let languageTag: String
    let source: RadioFeedSpeechMetadataSource

    static let fallback = RadioFeedSpeechMetadata(
        languageTag: "en-US",
        source: .fallback
    )

    static func normalizedLanguageTag(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-", omittingEmptySubsequences: false)
            .map(String.init)
        guard let language = parts.first,
              (2...3).contains(language.count),
              language.allSatisfy(\.isLetter) else {
            return nil
        }

        var normalized = [language.lowercased()]
        for part in parts.dropFirst() {
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isLetter || $0.isNumber }) else {
                return nil
            }
            switch part.count {
            case 2 where part.allSatisfy(\.isLetter):
                normalized.append(part.uppercased())
            case 3 where part.allSatisfy(\.isNumber):
                normalized.append(part)
            case 4 where part.allSatisfy(\.isLetter):
                normalized.append(
                    part.prefix(1).uppercased() + part.dropFirst().lowercased()
                )
            case 5...8:
                normalized.append(part.lowercased())
            default:
                return nil
            }
        }
        return normalized.joined(separator: "-")
    }
}

protocol RadioFeedSpeechMetadataStoring: Sendable {
    func metadata(for feedID: String) async -> RadioFeedSpeechMetadata
    func setLanguageTag(
        _ languageTag: String?,
        source: RadioFeedSpeechMetadataSource,
        for feedID: String
    ) async throws
}

actor InMemoryRadioFeedSpeechMetadataStore: RadioFeedSpeechMetadataStoring {
    private var values: [String: RadioFeedSpeechMetadata]

    init(values: [String: RadioFeedSpeechMetadata] = [:]) {
        self.values = values
    }

    func metadata(for feedID: String) -> RadioFeedSpeechMetadata {
        values[feedID] ?? .fallback
    }

    func setLanguageTag(
        _ languageTag: String?,
        source: RadioFeedSpeechMetadataSource,
        for feedID: String
    ) {
        let value = Self.resolvedMetadata(languageTag: languageTag, source: source)
        if let existing = values[feedID], existing.source.priority > value.source.priority {
            return
        }
        values[feedID] = value
    }

    fileprivate static func resolvedMetadata(
        languageTag: String?,
        source: RadioFeedSpeechMetadataSource
    ) -> RadioFeedSpeechMetadata {
        guard let normalized = RadioFeedSpeechMetadata.normalizedLanguageTag(languageTag) else {
            return .fallback
        }
        return RadioFeedSpeechMetadata(languageTag: normalized, source: source)
    }
}

actor RadioFeedSpeechMetadataStore: RadioFeedSpeechMetadataStoring {
    private struct FileEnvelope: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        var values: [String: RadioFeedSpeechMetadata]
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var loadedValues: [String: RadioFeedSpeechMetadata]?

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.fileURL = applicationSupport
                .appendingPathComponent("Briefeed", isDirectory: true)
                .appendingPathComponent("radio-feed-speech-v1.json")
        }
        try fileManager.createDirectory(
            at: self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func metadata(for feedID: String) -> RadioFeedSpeechMetadata {
        loadValues()[feedID] ?? .fallback
    }

    func setLanguageTag(
        _ languageTag: String?,
        source: RadioFeedSpeechMetadataSource,
        for feedID: String
    ) throws {
        var values = loadValues()
        let value = InMemoryRadioFeedSpeechMetadataStore.resolvedMetadata(
            languageTag: languageTag,
            source: source
        )
        if let existing = values[feedID], existing.source.priority > value.source.priority {
            return
        }
        values[feedID] = value
        let envelope = FileEnvelope(
            schemaVersion: FileEnvelope.currentSchemaVersion,
            values: values
        )
        try encoder.encode(envelope).write(to: fileURL, options: .atomic)
        var mutableURL = fileURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? mutableURL.setResourceValues(resourceValues)
        loadedValues = values
    }

    private func loadValues() -> [String: RadioFeedSpeechMetadata] {
        if let loadedValues { return loadedValues }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            loadedValues = [:]
            return [:]
        }
        do {
            let envelope = try decoder.decode(
                FileEnvelope.self,
                from: Data(contentsOf: fileURL)
            )
            guard envelope.schemaVersion == FileEnvelope.currentSchemaVersion else {
                throw CocoaError(.coderReadCorrupt)
            }
            loadedValues = envelope.values
            return envelope.values
        } catch {
            loadedValues = [:]
            return [:]
        }
    }
}
