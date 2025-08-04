//
//  AudioCacheManager.swift
//  Briefeed
//
//  Created by Briefeed Team on 1/8/25.
//

import Foundation
import AVFoundation

final class AudioCacheManager {
    static let shared = AudioCacheManager()
    
    // Cache configuration
    private let maxCacheSize: Int64 = 500 * 1024 * 1024 // 500MB
    private let cacheExpirationDays: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    
    // Cache directories
    private lazy var cacheDirectory: URL = {
        let cachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachePath.appendingPathComponent("Briefeed/Audio", isDirectory: true)
    }()
    
    private lazy var ttsDirectory: URL = {
        return cacheDirectory.appendingPathComponent("tts", isDirectory: true)
    }()
    
    private lazy var tempDirectory: URL = {
        return cacheDirectory.appendingPathComponent("temp/generating", isDirectory: true)
    }()
    
    private lazy var metadataURL: URL = {
        return ttsDirectory.appendingPathComponent("metadata.json")
    }()
    
    // Metadata tracking
    private var cacheMetadata: CacheMetadata = CacheMetadata()
    private let metadataQueue = DispatchQueue(label: "com.briefeed.audiocache.metadata")
    
    private init() {
        setupDirectories()
        loadMetadata()
        performInitialCleanup()
    }
    
    // MARK: - Setup
    
    private func setupDirectories() {
        do {
            try FileManager.default.createDirectory(at: ttsDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        } catch {
            print("❌ Failed to create cache directories: \(error)")
        }
    }
    
    // MARK: - Cache Operations
    
    /// Generate a cache key for an article
    func cacheKey(for articleID: UUID, content: String) -> String {
        // Create hash from content to detect changes
        let contentHash = content.data(using: .utf8)?.hashValue ?? 0
        return "\(articleID.uuidString)-\(contentHash)"
    }
    
    /// Get cached audio URL if exists
    func getCachedAudioURL(for key: String) -> URL? {
        let fileURL = ttsDirectory.appendingPathComponent("\(key).m4a")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        // Update last accessed time
        metadataQueue.async {
            self.updateLastAccessed(for: key)
        }
        
        return fileURL
    }
    
    /// Save audio file to cache
    func cacheAudioFile(from sourceURL: URL, key: String) throws -> URL {
        let destinationURL = ttsDirectory.appendingPathComponent("\(key).m4a")
        
        // Remove existing file if present
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        // Copy to cache
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        
        // Update metadata
        metadataQueue.async {
            self.addCacheEntry(key: key, fileURL: destinationURL)
        }
        
        return destinationURL
    }
    
    /// Get temporary file URL for TTS generation
    func getTemporaryFileURL() -> URL {
        let fileName = "\(UUID().uuidString).m4a"
        return tempDirectory.appendingPathComponent(fileName)
    }
    
    /// Move temporary file to cache
    func moveToCache(from tempURL: URL, key: String) throws -> URL {
        let destinationURL = ttsDirectory.appendingPathComponent("\(key).m4a")
        
        // Remove existing file if present
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        // Move to cache
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        
        // Update metadata
        metadataQueue.async {
            self.addCacheEntry(key: key, fileURL: destinationURL)
        }
        
        return destinationURL
    }
    
    /// Clean up temporary files
    func cleanupTemporaryFiles() {
        do {
            let tempFiles = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            for file in tempFiles {
                try? FileManager.default.removeItem(at: file)
            }
        } catch {
            print("⚠️ Failed to cleanup temp files: \(error)")
        }
    }
    
    // MARK: - Cache Management
    
    private func performInitialCleanup() {
        metadataQueue.async {
            self.removeExpiredEntries()
            self.enforceMaxCacheSize()
        }
    }
    
    func performCacheMaintenance() {
        metadataQueue.async {
            self.removeExpiredEntries()
            self.enforceMaxCacheSize()
            self.cleanupOrphanedFiles()
        }
    }
    
    private func removeExpiredEntries() {
        let expirationDate = Date().addingTimeInterval(-cacheExpirationDays)
        var entriesToRemove: [String] = []
        
        for (key, entry) in cacheMetadata.entries {
            if entry.lastAccessed < expirationDate {
                entriesToRemove.append(key)
            }
        }
        
        for key in entriesToRemove {
            if let entry = cacheMetadata.entries[key] {
                try? FileManager.default.removeItem(at: entry.fileURL)
                cacheMetadata.entries.removeValue(forKey: key)
            }
        }
        
        if !entriesToRemove.isEmpty {
            saveMetadata()
            print("🧹 Removed \(entriesToRemove.count) expired audio files")
        }
    }
    
    private func enforceMaxCacheSize() {
        let totalSize = cacheMetadata.entries.values.reduce(0) { $0 + $1.fileSize }
        
        guard totalSize > maxCacheSize else { return }
        
        // Sort by last accessed date (oldest first)
        let sortedEntries = cacheMetadata.entries.sorted { $0.value.lastAccessed < $1.value.lastAccessed }
        
        var currentSize = totalSize
        var entriesToRemove: [String] = []
        
        for (key, entry) in sortedEntries {
            if currentSize <= maxCacheSize { break }
            
            entriesToRemove.append(key)
            currentSize -= entry.fileSize
        }
        
        for key in entriesToRemove {
            if let entry = cacheMetadata.entries[key] {
                try? FileManager.default.removeItem(at: entry.fileURL)
                cacheMetadata.entries.removeValue(forKey: key)
            }
        }
        
        if !entriesToRemove.isEmpty {
            saveMetadata()
            print("🧹 Removed \(entriesToRemove.count) files to enforce cache size limit")
        }
    }
    
    private func cleanupOrphanedFiles() {
        do {
            let allFiles = try FileManager.default.contentsOfDirectory(at: ttsDirectory, includingPropertiesForKeys: nil)
            let metadataURLs = Set(cacheMetadata.entries.values.map { $0.fileURL })
            
            for fileURL in allFiles {
                if fileURL.lastPathComponent != "metadata.json" && !metadataURLs.contains(fileURL) {
                    try? FileManager.default.removeItem(at: fileURL)
                    print("🧹 Removed orphaned file: \(fileURL.lastPathComponent)")
                }
            }
        } catch {
            print("⚠️ Failed to cleanup orphaned files: \(error)")
        }
    }
    
    // MARK: - Metadata Management
    
    private func loadMetadata() {
        metadataQueue.sync {
            guard FileManager.default.fileExists(atPath: metadataURL.path) else { return }
            
            do {
                let data = try Data(contentsOf: metadataURL)
                cacheMetadata = try JSONDecoder().decode(CacheMetadata.self, from: data)
            } catch {
                print("⚠️ Failed to load cache metadata: \(error)")
                cacheMetadata = CacheMetadata()
            }
        }
    }
    
    private func saveMetadata() {
        do {
            let data = try JSONEncoder().encode(cacheMetadata)
            try data.write(to: metadataURL)
        } catch {
            print("❌ Failed to save cache metadata: \(error)")
        }
    }
    
    private func addCacheEntry(key: String, fileURL: URL) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            let entry = CacheEntry(
                fileURL: fileURL,
                createdDate: Date(),
                lastAccessed: Date(),
                fileSize: fileSize
            )
            
            cacheMetadata.entries[key] = entry
            saveMetadata()
        } catch {
            print("⚠️ Failed to add cache entry: \(error)")
        }
    }
    
    private func updateLastAccessed(for key: String) {
        if var entry = cacheMetadata.entries[key] {
            entry.lastAccessed = Date()
            cacheMetadata.entries[key] = entry
            saveMetadata()
        }
    }
    
    // MARK: - Cache Info
    
    func getCacheInfo() -> (fileCount: Int, totalSize: Int64) {
        return metadataQueue.sync {
            let fileCount = cacheMetadata.entries.count
            let totalSize = cacheMetadata.entries.values.reduce(0) { $0 + $1.fileSize }
            return (fileCount, totalSize)
        }
    }
    
    func clearCache() {
        metadataQueue.async {
            // Remove all cached files
            for entry in self.cacheMetadata.entries.values {
                try? FileManager.default.removeItem(at: entry.fileURL)
            }
            
            // Clear metadata
            self.cacheMetadata.entries.removeAll()
            self.saveMetadata()
            
            // Clean temp directory
            self.cleanupTemporaryFiles()
            
            print("🧹 Cache cleared successfully")
        }
    }
}

// MARK: - Cache Models

private struct CacheMetadata: Codable {
    var entries: [String: CacheEntry] = [:]
}

private struct CacheEntry: Codable {
    let fileURL: URL
    let createdDate: Date
    var lastAccessed: Date
    let fileSize: Int64
}