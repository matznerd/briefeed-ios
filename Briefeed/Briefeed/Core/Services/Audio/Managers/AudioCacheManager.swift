//
//  AudioCacheManager.swift
//  Briefeed
//
//  TTS Audio Cache Management
//  Handles file storage, size limits, and cleanup
//

import Foundation
import CoreData

/// Manages cached TTS audio files with size limits and auto-cleanup
final class AudioCacheManager {
    
    // MARK: - Constants
    
    private enum Constants {
        static let cacheDirectoryName = "AudioCache" // Match GeminiTTS directory
        static let maxCacheSize: Int64 = 500 * 1024 * 1024 // 500MB
        static let cleanupAgeDays = 5
        static let minFreeSpace: Int64 = 100 * 1024 * 1024 // Keep 100MB free
    }
    
    // MARK: - Properties
    
    /// Shared instance
    static let shared = AudioCacheManager()
    
    /// Cache directory URL
    let cacheDirectory: URL
    
    /// Current cache size in bytes
    var currentCacheSize: Int64 {
        calculateCacheSize()
    }
    
    // MARK: - Initialization
    
    init() {
        // Create cache directory in Library/Caches
        let cachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachePath.appendingPathComponent(Constants.cacheDirectoryName, isDirectory: true)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Perform initial cleanup
        Task {
            await performMaintenance()
        }
    }
    
    // MARK: - Public Methods
    
    /// Generate cache key for text content
    func cacheKey(for text: String, voice: String? = nil) -> String {
        let combined = text + (voice ?? "default")
        let data = combined.data(using: .utf8) ?? Data()
        
        // Use SHA256 for consistent hashing
        let hash = data.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        
        // Take first 32 characters for reasonable filename length
        let prefix = String(hash.prefix(32))
        
        if let voice = voice {
            return "\(prefix)_\(voice)"
        }
        return prefix
    }
    
    /// Get cached audio file URL if it exists
    func getCachedAudioURL(for text: String, voice: String? = nil) -> URL? {
        let key = cacheKey(for: text, voice: voice)
        
        // Check for both .wav and .mp3 files
        let extensions = ["wav", "mp3"]
        
        for ext in extensions {
            let fileURL = cacheDirectory
                .appendingPathComponent(key)
                .appendingPathExtension(ext)
            
            if FileManager.default.fileExists(atPath: fileURL.path) {
                // Update last accessed time
                try? FileManager.default.setAttributes(
                    [.modificationDate: Date()],
                    ofItemAtPath: fileURL.path
                )
                return fileURL
            }
        }
        
        return nil
    }
    
    /// Save audio data to cache
    func saveAudioToCache(_ data: Data, for text: String, voice: String? = nil) throws -> URL {
        // Check if we need to make space
        ensureCacheSize()
        
        let key = cacheKey(for: text, voice: voice)
        let fileURL = cacheDirectory
            .appendingPathComponent(key)
            .appendingPathExtension("mp3")
        
        try data.write(to: fileURL)
        
        print("[AudioCache] Saved file: \(key).mp3 (\(data.count) bytes)")
        
        return fileURL
    }
    
    /// Save audio from URL to cache
    func saveAudioToCache(from sourceURL: URL, for text: String, voice: String? = nil) throws -> URL {
        let data = try Data(contentsOf: sourceURL)
        return try saveAudioToCache(data, for: text, voice: voice)
    }
    
    /// Clear entire cache
    func clearCache() throws {
        let files = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        
        for file in files {
            try FileManager.default.removeItem(at: file)
        }
        
        print("[AudioCache] Cleared \(files.count) cached files")
    }
    
    /// Clean up old files
    func cleanupOldFiles(olderThan days: Int = Constants.cleanupAgeDays) throws {
        let cutoffDate = Date().addingTimeInterval(-Double(days * 24 * 60 * 60))
        let files = try FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        )
        
        var removedCount = 0
        var removedSize: Int64 = 0
        
        for file in files {
            let attributes = try file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            
            if let modDate = attributes.contentModificationDate,
               modDate < cutoffDate {
                let size = Int64(attributes.fileSize ?? 0)
                try FileManager.default.removeItem(at: file)
                removedCount += 1
                removedSize += size
            }
        }
        
        if removedCount > 0 {
            print("[AudioCache] Removed \(removedCount) old files (\(formatBytes(removedSize)))")
        }
    }
    
    // MARK: - Private Methods
    
    /// Calculate total cache size
    private func calculateCacheSize() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        
        for file in files {
            if let attributes = try? file.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = attributes.fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize
    }
    
    /// Ensure cache doesn't exceed size limit
    private func ensureCacheSize() {
        let currentSize = calculateCacheSize()
        
        if currentSize > Constants.maxCacheSize {
            evictLRU(toSize: Constants.maxCacheSize - Constants.minFreeSpace)
        }
    }
    
    /// Evict least recently used files
    private func evictLRU(toSize targetSize: Int64) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else {
            return
        }
        
        // Sort by modification date (oldest first)
        let sortedFiles = files.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            return date1 < date2
        }
        
        var currentSize = calculateCacheSize()
        var removedCount = 0
        
        for file in sortedFiles {
            if currentSize <= targetSize {
                break
            }
            
            if let attributes = try? file.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = attributes.fileSize {
                try? FileManager.default.removeItem(at: file)
                currentSize -= Int64(fileSize)
                removedCount += 1
            }
        }
        
        if removedCount > 0 {
            print("[AudioCache] Evicted \(removedCount) files to maintain cache size")
        }
    }
    
    /// Perform routine maintenance
    private func performMaintenance() async {
        // Run on background queue
        await Task.detached(priority: .background) {
            // Clean old files
            try? self.cleanupOldFiles()
            
            // Ensure size limit
            self.ensureCacheSize()
            
            // Log current status
            let size = self.currentCacheSize
            let fileCount = (try? FileManager.default.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: nil))?.count ?? 0
            
            print("[AudioCache] Maintenance complete: \(fileCount) files, \(self.formatBytes(size))")
        }.value
    }
    
    /// Format bytes for display
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Core Data Integration

extension AudioCacheManager {
    
    /// Track cached audio in Core Data
    func trackInCoreData(
        fileURL: URL,
        text: String,
        articleID: UUID?,
        voice: String?,
        context: NSManagedObjectContext
    ) {
        // This will be implemented when CachedAudio entity is added
        // For now, just log
        print("[AudioCache] Would track in Core Data: \(fileURL.lastPathComponent)")
    }
    
    /// Check if audio is already tracked in Core Data
    func isTrackedInCoreData(
        articleID: UUID,
        context: NSManagedObjectContext
    ) -> URL? {
        // This will be implemented when CachedAudio entity is added
        // For now, return nil
        return nil
    }
}

// MARK: - Pre-generation Support

extension AudioCacheManager {
    
    /// Get list of items that need pre-generation
    func itemsNeedingGeneration(from queue: [Any]) -> [Any] {
        // Filter items that don't have cached audio
        return queue.filter { item in
            // Check if we have cached audio for this item
            // This will be implemented based on item type
            return true // Placeholder
        }
    }
    
    /// Priority for pre-generation based on queue position
    func preGenerationPriority(for index: Int) -> TaskPriority {
        switch index {
        case 0: return .high      // Current item
        case 1: return .medium    // Next item
        case 2: return .low       // Second next
        default: return .background
        }
    }
}