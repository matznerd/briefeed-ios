import Foundation

enum AppTab: Hashable, CaseIterable {
    case radio
    case brief
    case feed

    var title: String {
        switch self {
        case .radio: "Radio"
        case .brief: "Brief"
        case .feed: "Feed"
        }
    }

    var systemImage: String {
        switch self {
        case .radio: "dot.radiowaves.left.and.right"
        case .brief: "text.page"
        case .feed: "newspaper"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .radio: AccessibilityID.Tab.radio
        case .brief: AccessibilityID.Tab.brief
        case .feed: AccessibilityID.Tab.feed
        }
    }
}
