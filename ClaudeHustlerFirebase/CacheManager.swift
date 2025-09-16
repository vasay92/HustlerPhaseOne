// CacheManager.swift
// Thread-safe caching system with memory and disk storage

import Foundation
import UIKit

// MARK: - Cache Manager
actor CacheManager {
    static let shared = CacheManager()
    
    private let memoryCache = NSCache<NSString, CacheEntry>()
    private let diskCacheURL: URL
    private let imageCache = NSCache<NSString, UIImage>()
    private let cacheQueue = DispatchQueue(label: "com.claudehustler.cache", attributes: .concurrent)
    private let maxMemoryCacheSize = 50 * 1024 * 1024 // 50MB
    private let maxDiskCacheSize = 200 * 1024 * 1024 // 200MB
    private let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    
    private var memoryWarningObserver: NSObjectProtocol?
    
    // MARK: - Initialization
    private init() {
        // Setup disk cache directory
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheURL = cacheDirectory.appendingPathComponent("com.claudehustler.cache")
        
        // Create cache directory if needed
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        
        // Configure memory cache
        memoryCache.totalCostLimit = maxMemoryCacheSize
        memoryCache.countLimit = 100
        
        // Configure image cache
        imageCache.totalCostLimit = 30 * 1024 * 1024 // 30MB for images
        imageCache.countLimit = 50
        
        // Setup memory warning observer
        Task {
            await setupMemoryWarningObserver()
        }
        
        // Clean expired cache on init
        Task {
            await cleanExpiredCache()
        }
    }
    
    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Cache Entry
    private class CacheEntry: NSObject {
        let data: Data
        let expiry: Date
        let cost: Int
        
        init(data: Data, expiry: Date) {
            self.data = data
            self.expiry = expiry
            self.cost = data.count
            super.init()
        }
        
        var isExpired: Bool {
            Date() > expiry
        }
    }
    
    // MARK: - Public Methods - Generic Cache
    
    func set<T: Codable>(_ object: T, for key: String, duration: TimeInterval = 300) async {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(object)
            
            let expiry = Date().addingTimeInterval(duration)
            let entry = CacheEntry(data: data, expiry: expiry)
            
            // Store in memory cache
            await setMemoryCache(entry, for: key)
            
            // Store on disk
            await setDiskCache(data, for: key, expiry: expiry)
            
        } catch {
            print("Cache encoding error: \(error)")
        }
    }
    
    func get<T: Codable>(_ type: T.Type, for key: String) async -> T? {
        // Check memory cache first
        if let entry = await getMemoryCache(for: key), !entry.isExpired {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(type, from: entry.data)
            } catch {
                print("Cache decoding error: \(error)")
            }
        }
        
        // Check disk cache
        if let data = await getDiskCache(for: key) {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let object = try decoder.decode(type, from: data)
                
                // Update memory cache
                let entry = CacheEntry(data: data, expiry: Date().addingTimeInterval(300))
                await setMemoryCache(entry, for: key)
                
                return object
            } catch {
                print("Disk cache decoding error: \(error)")
            }
        }
        
        return nil
    }
    
    func remove(for key: String) async {
        await removeMemoryCache(for: key)
        await removeDiskCache(for: key)
    }
    
    func removeExpired() async {
        await cleanExpiredCache()
    }
    
    func clear() async {
        await clearMemoryCache()
        await clearDiskCache()
    }
    
    // MARK: - Image Cache Methods
    
    func cacheImage(_ data: Data, for url: String) async {
        guard let image = UIImage(data: data) else { return }
        
        // Cache image in memory
        let key = NSString(string: url)
        imageCache.setObject(image, forKey: key, cost: data.count)
        
        // Cache data on disk
        await setDiskCache(data, for: "image_\(url)", expiry: Date().addingTimeInterval(maxCacheAge))
    }
    
    func getCachedImage(for url: String) async -> Data? {
        let key = NSString(string: url)
        
        // Check memory cache
        if let image = imageCache.object(forKey: key) {
            return image.jpegData(compressionQuality: 0.8)
        }
        
        // Check disk cache
        if let data = await getDiskCache(for: "image_\(url)"),
           let image = UIImage(data: data) {
            // Update memory cache
            imageCache.setObject(image, forKey: key, cost: data.count)
            return data
        }
        
        return nil
    }
    
    func getCachedUIImage(for url: String) -> UIImage? {
        let key = NSString(string: url)
        return imageCache.object(forKey: key)
    }
    
    // MARK: - Batch Operations
    
    func setBatch<T: Codable>(_ items: [(key: String, value: T)], duration: TimeInterval = 300) async {
        for item in items {
            await set(item.value, for: item.key, duration: duration)
        }
    }
    
    func getBatch<T: Codable>(_ type: T.Type, keys: [String]) async -> [String: T] {
        var results: [String: T] = [:]
        
        for key in keys {
            if let value = await get(type, for: key) {
                results[key] = value
            }
        }
        
        return results
    }
    
    // MARK: - Cache Statistics
    
    func getCacheSize() async -> (memory: Int, disk: Int) {
        let memorySize = await getMemoryCacheSize()
        let diskSize = await getDiskCacheSize()
        return (memorySize, diskSize)
    }
    
    func getCacheInfo() async -> CacheInfo {
        let size = await getCacheSize()
        let fileCount = await getDiskCacheFileCount()
        
        return CacheInfo(
            memorySizeBytes: size.memory,
            diskSizeBytes: size.disk,
            fileCount: fileCount,
            maxMemorySize: maxMemoryCacheSize,
            maxDiskSize: maxDiskCacheSize
        )
    }
    
    struct CacheInfo {
        let memorySizeBytes: Int
        let diskSizeBytes: Int
        let fileCount: Int
        let maxMemorySize: Int
        let maxDiskSize: Int
        
        var memorySizeMB: Double {
            Double(memorySizeBytes) / (1024 * 1024)
        }
        
        var diskSizeMB: Double {
            Double(diskSizeBytes) / (1024 * 1024)
        }
    }
    
    // MARK: - Private Methods - Memory Cache
    
    private func setMemoryCache(_ entry: CacheEntry, for key: String) {
        memoryCache.setObject(entry, forKey: NSString(string: key), cost: entry.cost)
    }
    
    private func getMemoryCache(for key: String) -> CacheEntry? {
        return memoryCache.object(forKey: NSString(string: key))
    }
    
    private func removeMemoryCache(for key: String) {
        memoryCache.removeObject(forKey: NSString(string: key))
    }
    
    private func clearMemoryCache() {
        memoryCache.removeAllObjects()
        imageCache.removeAllObjects()
    }
    
    private func getMemoryCacheSize() -> Int {
        // Approximate size based on cost
        var totalSize = 0
        // Note: NSCache doesn't provide direct access to all objects
        // This is an approximation
        return totalSize
    }
    
    // MARK: - Private Methods - Disk Cache
    
    private func setDiskCache(_ data: Data, for key: String, expiry: Date) async {
        let fileURL = diskCacheURL.appendingPathComponent(key.sanitizedForFilename())
        
        do {
            // Create metadata
            let metadata = CacheMetadata(expiry: expiry, size: data.count)
            let metadataData = try JSONEncoder().encode(metadata)
            
            // Combine metadata and data
            var combinedData = Data()
            combinedData.append(contentsOf: withUnsafeBytes(of: Int32(metadataData.count)) { Data($0) })
            combinedData.append(metadataData)
            combinedData.append(data)
            
            // Write to disk
            try combinedData.write(to: fileURL)
            
            // Check disk size and clean if needed
            await cleanDiskCacheIfNeeded()
            
        } catch {
            print("Disk cache write error: \(error)")
        }
    }
    
    private func getDiskCache(for key: String) -> Data? {
        let fileURL = diskCacheURL.appendingPathComponent(key.sanitizedForFilename())
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        do {
            let combinedData = try Data(contentsOf: fileURL)
            
            // Extract metadata size
            guard combinedData.count > 4 else { return nil }
            let metadataSize = combinedData.withUnsafeBytes { $0.load(as: Int32.self) }
            
            guard combinedData.count > 4 + Int(metadataSize) else { return nil }
            
            // Extract metadata
            let metadataData = combinedData[4..<(4 + Int(metadataSize))]
            let metadata = try JSONDecoder().decode(CacheMetadata.self, from: metadataData)
            
            // Check expiry
            if Date() > metadata.expiry {
                try FileManager.default.removeItem(at: fileURL)
                return nil
            }
            
            // Extract actual data
            let data = combinedData[(4 + Int(metadataSize))...]
            
            return Data(data)
            
        } catch {
            print("Disk cache read error: \(error)")
            return nil
        }
    }
    
    private func removeDiskCache(for key: String) {
        let fileURL = diskCacheURL.appendingPathComponent(key.sanitizedForFilename())
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    private func clearDiskCache() {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: nil)
            for file in files {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            print("Clear disk cache error: \(error)")
        }
    }
    
    private func getDiskCacheSize() -> Int {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.fileSizeKey])
            
            return files.reduce(0) { total, file in
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return total + size
            }
        } catch {
            return 0
        }
    }
    
    private func getDiskCacheFileCount() -> Int {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: nil)
            return files.count
        } catch {
            return 0
        }
    }
    
    private func cleanDiskCacheIfNeeded() {
        let currentSize = getDiskCacheSize()
        
        if currentSize > maxDiskCacheSize {
            // Remove oldest files until under limit
            do {
                let files = try FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
                
                // Sort by modification date
                let sortedFiles = files.sorted { file1, file2 in
                    let date1 = (try? file1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    let date2 = (try? file2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    return date1 < date2
                }
                
                var totalSize = currentSize
                for file in sortedFiles {
                    if totalSize <= maxDiskCacheSize * 3/4 { // Clean to 75% of max
                        break
                    }
                    
                    let fileSize = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    try FileManager.default.removeItem(at: file)
                    totalSize -= fileSize
                }
            } catch {
                print("Clean disk cache error: \(error)")
            }
        }
    }
    
    private func cleanExpiredCache() {
        // Clean memory cache
        // NSCache handles this automatically
        
        // Clean disk cache
        do {
            let files = try FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.contentModificationDateKey])
            
            for file in files {
                // Check if file is expired
                if let data = getDiskCache(for: file.lastPathComponent) {
                    // If getDiskCache returns nil for expired files, they're already removed
                    continue
                } else {
                    // Remove orphaned files
                    try? FileManager.default.removeItem(at: file)
                }
            }
        } catch {
            print("Clean expired cache error: \(error)")
        }
    }
    
    // MARK: - Memory Warning
    
    private func setupMemoryWarningObserver() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak memoryCache, weak imageCache] _ in
            memoryCache?.removeAllObjects()
            imageCache?.removeAllObjects()
            print("Cache cleared due to memory warning")
        }
    }
    
    // MARK: - Helper Structures
    
    private struct CacheMetadata: Codable {
        let expiry: Date
        let size: Int
    }
}

// MARK: - String Extension for Filename Sanitization
private extension String {
    func sanitizedForFilename() -> String {
        // Replace invalid characters with underscore
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let sanitized = self.components(separatedBy: invalidCharacters).joined(separator: "_")
        
        // Limit length
        let maxLength = 255
        if sanitized.count > maxLength {
            let index = sanitized.index(sanitized.startIndex, offsetBy: maxLength)
            return String(sanitized[..<index])
        }
        
        return sanitized
    }
}

// MARK: - Cache Prefetching
extension CacheManager {
    func prefetchImages(urls: [String]) async {
        for url in urls {
            if await getCachedImage(for: url) == nil {
                // Image not in cache, it will be downloaded when needed
                // This is just to check cache status
                continue
            }
        }
    }
    
    func warmCache<T: Codable>(keys: [String], fetcher: (String) async throws -> T?, duration: TimeInterval = 300) async {
        for key in keys {
            if await get(T.self, for: key) == nil {
                if let value = try? await fetcher(key) {
                    await set(value, for: key, duration: duration)
                }
            }
        }
    }
}
