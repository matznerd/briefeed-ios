//
//  AudioPlayerModels.swift
//  Briefeed
//
//  Common models for audio playback
//

import Foundation

// MARK: - Audio Service Error
public enum AudioServiceError: LocalizedError {
    case invalidURL
    case synthesisError(String)
    case fileNotFound
    case networkError(String)
    case unauthorized
    case unknown(String)
    case noTextToSpeak
    case speechSynthesizerUnavailable
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL provided"
        case .synthesisError(let message):
            return "Speech synthesis error: \(message)"
        case .fileNotFound:
            return "File not found"
        case .networkError(let message):
            return "Network error: \(message)"
        case .unauthorized:
            return "Unauthorized access"
        case .unknown(let message):
            return "Unknown error: \(message)"
        case .noTextToSpeak:
            return "No text available to speak"
        case .speechSynthesizerUnavailable:
            return "Speech synthesizer is not available"
        }
    }
}

// MARK: - Audio Player State
public enum AudioPlayerState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case error(String)
    
    public static func == (lhs: AudioPlayerState, rhs: AudioPlayerState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.loading, .loading),
             (.playing, .playing),
             (.paused, .paused),
             (.stopped, .stopped):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}