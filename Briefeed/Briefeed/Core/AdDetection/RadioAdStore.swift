import CryptoKit
import Foundation

actor RadioAdStore {
    enum StoreError: Error, Equatable { case staleRevision, missingRecord, missingSpan, oversizedRecord }
    private let rootDirectory: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(rootDirectory: URL) throws {
        self.rootDirectory = rootDirectory
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        var directory = rootDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

    static func makeProduction() throws -> RadioAdStore {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return try .init(rootDirectory: root.appendingPathComponent("Briefeed/AdIntelligence", isDirectory: true))
    }

    func load(for key: RadioAdCacheKey) throws -> RadioAdRecord? {
        let url = try recordURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 1024 * 1024 else { throw StoreError.oversizedRecord }
        let record = try decoder.decode(RadioAdRecord.self, from: Data(contentsOf: url))
        try record.validate()
        guard record.key == key else { throw RadioAdValidationError.invalidIdentity }
        return record
    }

    func save(_ record: RadioAdRecord) throws {
        try record.validate()
        let data = try encoder.encode(record)
        guard data.count <= 1024 * 1024 else { throw StoreError.oversizedRecord }
        let url = try recordURL(for: record.key)
        try data.write(to: url, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                              ofItemAtPath: url.path)
        #endif
    }

    func review(key: RadioAdCacheKey, spanID: UUID, expectedRevision: Int,
                kind: RadioAdKind, start: TimeInterval, end: TimeInterval,
                boundariesReviewed: Bool) throws -> RadioAdRecord {
        guard var record = try load(for: key) else { throw StoreError.missingRecord }
        guard record.revision == expectedRevision else { throw StoreError.staleRevision }
        guard let index = record.spans.firstIndex(where: { $0.id == spanID }) else { throw StoreError.missingSpan }
        record.spans[index].kind = kind
        record.spans[index].startSeconds = start
        record.spans[index].endSeconds = end
        record.spans[index].categoryReviewed = true
        record.spans[index].boundariesReviewed = boundariesReviewed
        if boundariesReviewed { record.spans[index].unresolvedGap = false }
        record.revision += 1
        try save(record)
        return record
    }

    private func recordURL(for key: RadioAdCacheKey) throws -> URL {
        let data = try encoder.encode(key)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return rootDirectory.appendingPathComponent(hash + ".json")
    }
}
