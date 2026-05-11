//
//  AccessibilityIdentifiers.swift
//  Briefeed
//
//  Centralized accessibility identifiers for UI testing and axe interaction
//

import Foundation

enum AccessibilityID {
    enum Tab {
        static let feed = "tab.feed"
        static let brief = "tab.brief"
        static let liveNews = "tab.liveNews"
        static let settings = "tab.settings"
    }

    enum Feed {
        static let addFeed = "feed.addFeed"
        static let refreshButton = "feed.refresh"
        static func selector(_ name: String) -> String { "feed.selector.\(name)" }
    }

    enum ArticleRow {
        static func row(_ id: String) -> String { "articleRow.\(id)" }
        static let playNow = "articleRow.playNow"
        static let playNext = "articleRow.playNext"
        static let save = "articleRow.save"
        static let queue = "articleRow.queue"
    }

    enum Article {
        static let play = "article.play"
        static let save = "article.save"
        static let share = "article.share"
        static let readerSettings = "article.readerSettings"
        static let generateSummary = "article.generateSummary"
        static let fetchArticle = "article.fetchArticle"
    }

    enum MiniPlayer {
        static let container = "miniPlayer.container"
        static let title = "miniPlayer.title"
        static let previous = "miniPlayer.previous"
        static let rewind = "miniPlayer.rewind"
        static let playPause = "miniPlayer.playPause"
        static let forward = "miniPlayer.forward"
        static let next = "miniPlayer.next"
    }

    enum ExpandedPlayer {
        static let dismiss = "expandedPlayer.dismiss"
        static let queue = "expandedPlayer.queue"
        static let skipBackward = "expandedPlayer.skipBackward"
        static let previous = "expandedPlayer.previous"
        static let playPause = "expandedPlayer.playPause"
        static let next = "expandedPlayer.next"
        static let skipForward = "expandedPlayer.skipForward"
        static let speed = "expandedPlayer.speed"
        static let progress = "expandedPlayer.progress"
    }

    enum Brief {
        static let filterPicker = "brief.filterPicker"
        static let playAll = "brief.playAll"
        static let clearQueue = "brief.clearQueue"
        static let editButton = "brief.editButton"
        static func queueRow(_ id: String) -> String { "brief.queueRow.\(id)" }
    }

    enum LiveNews {
        static let playAll = "liveNews.playAll"
        static let addFeed = "liveNews.addFeed"
        static func feedRow(_ name: String) -> String { "liveNews.feedRow.\(name)" }
    }

    enum Settings {
        static let darkMode = "settings.darkMode"
        static let textSize = "settings.textSize"
        static let summaryLength = "settings.summaryLength"
        static let audioEnabled = "settings.audioEnabled"
        static let speechRate = "settings.speechRate"
        static let clearCache = "settings.clearCache"
        static let resetSettings = "settings.resetSettings"
        static let downloadOnDeviceModels = "settings.downloadOnDeviceModels"
        static let preferOnDeviceTTS = "settings.preferOnDeviceTTS"
    }

    enum AddFeed {
        static let nameField = "addFeed.nameField"
        static let cancel = "addFeed.cancel"
        static let add = "addFeed.add"
    }

    enum TranscriptReader {
        static let container = "transcriptReader.container"
        static let title = "transcriptReader.title"
        static let source = "transcriptReader.source"
        static let quickFacts = "transcriptReader.quickFacts"
        static let storyText = "transcriptReader.storyText"
        static let dismiss = "transcriptReader.dismiss"
    }

    enum AddRSSFeed {
        static let urlField = "addRSSFeed.urlField"
        static let cancel = "addRSSFeed.cancel"
        static let add = "addRSSFeed.add"
    }
}
