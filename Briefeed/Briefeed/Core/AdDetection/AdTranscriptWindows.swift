import Foundation

struct AdTranscriptAnchor: Equatable, Sendable {
    let index: Int
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval
    let text: String
}

enum AdTranscriptWindowError: Error {
    case invalidAnchors, invalidBudget
    case oversizedAnchor(index: Int)
}

struct AdTranscriptWindow: Equatable, Sendable {
    let anchors: [AdTranscriptAnchor]
    let encodedInput: String

    func sourceRange(firstIndex: Int, lastIndex: Int) -> Range<TimeInterval>? {
        guard let first = anchors.first(where: { $0.index == firstIndex }),
              let last = anchors.first(where: { $0.index == lastIndex }), firstIndex <= lastIndex else { return nil }
        return first.startSeconds..<last.endSeconds
    }

    func hasUnresolvedGap(firstIndex: Int, lastIndex: Int) -> Bool {
        guard sourceRange(firstIndex: firstIndex, lastIndex: lastIndex) != nil else { return true }
        let selected = anchors.filter { firstIndex <= $0.index && $0.index <= lastIndex }
        return zip(selected, selected.dropFirst()).contains { $1.startSeconds - $0.endSeconds > 1 }
    }
}

enum AdTranscriptWindows {
    private struct Input: Encodable {
        struct Unit: Encodable { let id: Int; let text: String }
        let units: [Unit]
    }

    static func make(_ anchors: [AdTranscriptAnchor], maximumUTF8Bytes: Int = 2400,
                     maximumUnits: Int = 64, overlap: Int = 4) throws -> [AdTranscriptWindow] {
        guard maximumUTF8Bytes >= 128, maximumUnits > overlap, overlap >= 0 else {
            throw AdTranscriptWindowError.invalidBudget
        }
        for (offset, anchor) in anchors.enumerated() {
            guard anchor.index >= 0, anchor.startSeconds.isFinite, anchor.endSeconds.isFinite,
                  anchor.startSeconds >= 0, anchor.endSeconds > anchor.startSeconds,
                  !anchor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AdTranscriptWindowError.invalidAnchors
            }
            if offset > 0 {
                let prior = anchors[offset - 1]
                guard anchor.index > prior.index, anchor.startSeconds >= prior.endSeconds else {
                    throw AdTranscriptWindowError.invalidAnchors
                }
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func encode(_ slice: ArraySlice<AdTranscriptAnchor>) throws -> String {
            let data = try encoder.encode(Input(units: slice.map { .init(id: $0.index, text: $0.text) }))
            return String(decoding: data, as: UTF8.self)
        }
        var result: [AdTranscriptWindow] = []
        var start = 0
        while start < anchors.count {
            var end = start
            var input = ""
            while end < anchors.count && end - start < maximumUnits {
                let candidate = try encode(anchors[start...end])
                guard candidate.utf8.count <= maximumUTF8Bytes else { break }
                input = candidate
                end += 1
            }
            guard end > start else { throw AdTranscriptWindowError.oversizedAnchor(index: anchors[start].index) }
            result.append(.init(anchors: Array(anchors[start..<end]), encodedInput: input))
            if end == anchors.count { break }
            guard end - start > overlap else { throw AdTranscriptWindowError.invalidBudget }
            start = end - overlap
        }
        return result
    }
}
