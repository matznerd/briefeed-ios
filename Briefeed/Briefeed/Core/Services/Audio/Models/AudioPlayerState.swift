//
//  AudioPlayerState.swift
//  Briefeed
//
//  Audio player state enum shared across audio services
//

import Foundation

// MARK: - Audio Player State
public enum AudioPlayerState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case error(Error)
    
    public static func == (lhs: AudioPlayerState, rhs: AudioPlayerState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.playing, .playing),
             (.paused, .paused), (.stopped, .stopped):
            return true
        case (.error(_), .error(_)):
            return true // Consider all errors equal for comparison
        default:
            return false
        }
    }
}