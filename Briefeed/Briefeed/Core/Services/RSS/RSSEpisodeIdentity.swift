import CryptoKit
import Foundation

enum RSSEpisodeIdentity {
    enum Error: Swift.Error, Equatable {
        case missingStableIdentity
        case invalidEnclosureURL
    }

    static func episodeID(guid: String?, enclosureURL: String, publicationDate: Date?) throws -> String {
        if let guid = guid?.trimmingCharacters(in: .whitespacesAndNewlines), !guid.isEmpty {
            return guid
        }

        guard let publicationDate else { throw Error.missingStableIdentity }
        let canonicalURL = try canonicalEnclosureURL(enclosureURL)
        let input = "\(canonicalURL)|\(Int(publicationDate.timeIntervalSince1970))"
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func canonicalEnclosureURL(_ value: String) throws -> String {
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(), !host.isEmpty else {
            throw Error.invalidEnclosureURL
        }

        components.scheme = scheme
        components.host = host
        components.fragment = nil
        if (scheme == "http" && components.port == 80) || (scheme == "https" && components.port == 443) {
            components.port = nil
        }
        components.percentEncodedPath = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        if let queryItems = components.queryItems {
            components.queryItems = queryItems.sorted {
                if $0.name != $1.name { return $0.name < $1.name }
                return ($0.value ?? "") < ($1.value ?? "")
            }
        }
        guard let canonical = components.string else { throw Error.invalidEnclosureURL }
        return canonical
    }
}
