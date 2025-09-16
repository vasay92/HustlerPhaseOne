// RateLimiter.swift
// Thread-safe rate limiting for API requests

import Foundation

// MARK: - Rate Limiter
class RateLimiter {
    static let shared = RateLimiter()
    
    private var requestCounts: [String: [Date]] = [:]
    private let queue = DispatchQueue(label: "com.claudehustler.ratelimiter", attributes: .concurrent)
    private var limitConfigurations: [String: LimitConfiguration] = [:]
    
    // Default configurations for different features
    private let defaultConfigurations: [String: LimitConfiguration] = [
        "api_request": LimitConfiguration(limit: 60, window: 60), // 60 per minute
        "image_upload": LimitConfiguration(limit: 10, window: 60), // 10 per minute
        "message_send": LimitConfiguration(limit: 30, window: 60), // 30 per minute
        "post_create": LimitConfiguration(limit: 5, window: 60), // 5 per minute
        "review_create": LimitConfiguration(limit: 3, window: 60), // 3 per minute
        "search": LimitConfiguration(limit: 20, window: 60), // 20 per minute
        "login_attempt": LimitConfiguration(limit: 5, window: 300), // 5 per 5 minutes
        "password_reset": LimitConfiguration(limit: 3, window: 3600), // 3 per hour
        "report": LimitConfiguration(limit: 5, window: 3600), // 5 per hour
        "follow": LimitConfiguration(limit: 20, window: 60), // 20 per minute
        "like": LimitConfiguration(limit: 60, window: 60), // 60 per minute
        "comment": LimitConfiguration(limit: 10, window: 60), // 10 per minute
        "profile_update": LimitConfiguration(limit: 10, window: 300), // 10 per 5 minutes
        "data_export": LimitConfiguration(limit: 2, window: 86400), // 2 per day
    ]
    
    // Bucket configurations for token bucket algorithm
    private var tokenBuckets: [String: TokenBucket] = [:]
    
    struct LimitConfiguration {
        let limit: Int
        let window: TimeInterval
        var penalty: TimeInterval? // Additional wait time for violations
        
        init(limit: Int, window: TimeInterval, penalty: TimeInterval? = nil) {
            self.limit = limit
            self.window = window
            self.penalty = penalty
        }
    }
    
    // MARK: - Initialization
    private init() {
        // Initialize with default configurations
        limitConfigurations = defaultConfigurations
        
        // Start cleanup timer
        startCleanupTimer()
    }
    
    // MARK: - Public Methods
    
    /// Check if an action is rate limited
    func checkLimit(for key: String, limit: Int? = nil, window: TimeInterval? = nil) throws {
        let configuration = getConfiguration(for: key, customLimit: limit, customWindow: window)
        
        try queue.sync(flags: .barrier) {
            // Clean old entries
            cleanOldEntries(for: key, window: configuration.window)
            
            // Get current count
            let currentCount = requestCounts[key]?.count ?? 0
            
            if currentCount >= configuration.limit {
                // Calculate retry after time
                if let firstRequest = requestCounts[key]?.first {
                    let retryAfter = Int(configuration.window - Date().timeIntervalSince(firstRequest))
                    throw RateLimitError.rateLimited(
                        key: key,
                        limit: configuration.limit,
                        retryAfter: max(1, retryAfter)
                    )
                }
            }
            
            // Add new request
            if requestCounts[key] == nil {
                requestCounts[key] = []
            }
            requestCounts[key]?.append(Date())
        }
    }
    
    /// Check limit with custom identifier (e.g., per user)
    func checkLimit(for key: String, identifier: String, limit: Int? = nil, window: TimeInterval? = nil) throws {
        let combinedKey = "\(key)_\(identifier)"
        try checkLimit(for: combinedKey, limit: limit, window: window)
    }
    
    /// Reset rate limit for a specific key
    func reset(for key: String) {
        queue.async(flags: .barrier) {
            self.requestCounts[key] = nil
            self.tokenBuckets[key] = nil
        }
    }
    
    /// Reset all rate limits
    func resetAll() {
        queue.async(flags: .barrier) {
            self.requestCounts.removeAll()
            self.tokenBuckets.removeAll()
        }
    }
    
    /// Get remaining requests for a key
    func getRemainingRequests(for key: String) -> Int {
        let configuration = getConfiguration(for: key)
        
        return queue.sync {
            cleanOldEntries(for: key, window: configuration.window)
            let currentCount = requestCounts[key]?.count ?? 0
            return max(0, configuration.limit - currentCount)
        }
    }
    
    /// Get rate limit status
    func getStatus(for key: String) -> RateLimitStatus {
        let configuration = getConfiguration(for: key)
        
        return queue.sync {
            cleanOldEntries(for: key, window: configuration.window)
            
            let currentCount = requestCounts[key]?.count ?? 0
            let remaining = max(0, configuration.limit - currentCount)
            
            var resetTime: Date?
            if let firstRequest = requestCounts[key]?.first {
                resetTime = firstRequest.addingTimeInterval(configuration.window)
            }
            
            return RateLimitStatus(
                key: key,
                limit: configuration.limit,
                remaining: remaining,
                used: currentCount,
                resetTime: resetTime,
                window: configuration.window
            )
        }
    }
    
    /// Configure custom limits for specific keys
    func configureLimit(for key: String, limit: Int, window: TimeInterval, penalty: TimeInterval? = nil) {
        queue.async(flags: .barrier) {
            self.limitConfigurations[key] = LimitConfiguration(
                limit: limit,
                window: window,
                penalty: penalty
            )
        }
    }
    
    // MARK: - Token Bucket Algorithm
    
    /// Use token bucket for smoother rate limiting
    func consumeToken(for key: String, tokens: Int = 1) throws {
        let configuration = getConfiguration(for: key)
        
        try queue.sync(flags: .barrier) {
            // Get or create bucket
            if tokenBuckets[key] == nil {
                tokenBuckets[key] = TokenBucket(
                    capacity: configuration.limit,
                    refillRate: Double(configuration.limit) / configuration.window
                )
            }
            
            guard let bucket = tokenBuckets[key] else {
                throw RateLimitError.configurationError
            }
            
            // Try to consume tokens
            if !bucket.consume(tokens: tokens) {
                let retryAfter = bucket.timeUntilTokensAvailable(tokens: tokens)
                throw RateLimitError.rateLimited(
                    key: key,
                    limit: configuration.limit,
                    retryAfter: Int(ceil(retryAfter))
                )
            }
        }
    }
    
    // MARK: - Debouncing
    
    private var debouncers: [String: DispatchWorkItem] = [:]
    
    func debounce(
        key: String,
        delay: TimeInterval,
        action: @escaping () -> Void
    ) {
        queue.async(flags: .barrier) {
            // Cancel previous debouncer
            self.debouncers[key]?.cancel()
            
            // Create new work item
            let workItem = DispatchWorkItem {
                action()
                self.queue.async(flags: .barrier) {
                    self.debouncers[key] = nil
                }
            }
            
            self.debouncers[key] = workItem
            
            // Schedule execution
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }
    
    // MARK: - Throttling
    
    private var throttleTimestamps: [String: Date] = [:]
    
    func throttle(
        key: String,
        interval: TimeInterval,
        action: @escaping () -> Void
    ) -> Bool {
        return queue.sync(flags: .barrier) {
            let now = Date()
            
            if let lastExecution = throttleTimestamps[key] {
                if now.timeIntervalSince(lastExecution) < interval {
                    return false // Throttled
                }
            }
            
            throttleTimestamps[key] = now
            action()
            return true
        }
    }
    
    // MARK: - Private Methods
    
    private func getConfiguration(
        for key: String,
        customLimit: Int? = nil,
        customWindow: TimeInterval? = nil
    ) -> LimitConfiguration {
        if let custom = limitConfigurations[key] {
            return LimitConfiguration(
                limit: customLimit ?? custom.limit,
                window: customWindow ?? custom.window,
                penalty: custom.penalty
            )
        }
        
        // Default fallback
        return LimitConfiguration(
            limit: customLimit ?? 10,
            window: customWindow ?? 60
        )
    }
    
    private func cleanOldEntries(for key: String, window: TimeInterval) {
        let cutoffDate = Date().addingTimeInterval(-window)
        requestCounts[key]?.removeAll { $0 < cutoffDate }
        
        if requestCounts[key]?.isEmpty == true {
            requestCounts[key] = nil
        }
    }
    
    private func startCleanupTimer() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.cleanupAllOldEntries()
        }
    }
    
    private func cleanupAllOldEntries() {
        queue.async(flags: .barrier) {
            for (key, _) in self.requestCounts {
                let configuration = self.getConfiguration(for: key)
                self.cleanOldEntries(for: key, window: configuration.window)
            }
            
            // Clean old throttle timestamps
            let cutoff = Date().addingTimeInterval(-3600) // 1 hour
            self.throttleTimestamps = self.throttleTimestamps.filter { $0.value > cutoff }
        }
    }
}

// MARK: - Rate Limit Error
enum RateLimitError: LocalizedError {
    case rateLimited(key: String, limit: Int, retryAfter: Int)
    case configurationError
    
    var errorDescription: String? {
        switch self {
        case .rateLimited(let key, let limit, let retryAfter):
            return "Rate limit exceeded for \(key). Limit: \(limit). Try again in \(retryAfter) seconds."
        case .configurationError:
            return "Rate limiter configuration error"
        }
    }
    
    var retryAfter: Int? {
        switch self {
        case .rateLimited(_, _, let retryAfter):
            return retryAfter
        case .configurationError:
            return nil
        }
    }
}

// MARK: - Rate Limit Status
struct RateLimitStatus {
    let key: String
    let limit: Int
    let remaining: Int
    let used: Int
    let resetTime: Date?
    let window: TimeInterval
    
    var percentageUsed: Double {
        guard limit > 0 else { return 0 }
        return Double(used) / Double(limit)
    }
    
    var isNearLimit: Bool {
        percentageUsed > 0.8
    }
    
    var timeUntilReset: TimeInterval? {
        guard let reset = resetTime else { return nil }
        return reset.timeIntervalSinceNow
    }
    
    var formattedTimeUntilReset: String? {
        guard let time = timeUntilReset, time > 0 else { return nil }
        
        if time < 60 {
            return "\(Int(time))s"
        } else if time < 3600 {
            return "\(Int(time / 60))m"
        } else {
            return "\(Int(time / 3600))h"
        }
    }
}

// MARK: - Token Bucket
private class TokenBucket {
    private var tokens: Double
    private let capacity: Int
    private let refillRate: Double // Tokens per second
    private var lastRefill: Date
    
    init(capacity: Int, refillRate: Double) {
        self.capacity = capacity
        self.refillRate = refillRate
        self.tokens = Double(capacity)
        self.lastRefill = Date()
    }
    
    func consume(tokens: Int) -> Bool {
        refill()
        
        if self.tokens >= Double(tokens) {
            self.tokens -= Double(tokens)
            return true
        }
        
        return false
    }
    
    func timeUntilTokensAvailable(tokens: Int) -> TimeInterval {
        refill()
        
        if self.tokens >= Double(tokens) {
            return 0
        }
        
        let tokensNeeded = Double(tokens) - self.tokens
        return tokensNeeded / refillRate
    }
    
    private func refill() {
        let now = Date()
        let timeSinceLastRefill = now.timeIntervalSince(lastRefill)
        
        let tokensToAdd = timeSinceLastRefill * refillRate
        tokens = min(Double(capacity), tokens + tokensToAdd)
        lastRefill = now
    }
}

// MARK: - Rate Limit Middleware
extension RateLimiter {
    
    /// Middleware for automatic rate limiting
    func rateLimitedOperation<T>(
        key: String,
        limit: Int? = nil,
        window: TimeInterval? = nil,
        operation: () async throws -> T
    ) async throws -> T {
        // Check rate limit
        try checkLimit(for: key, limit: limit, window: window)
        
        // Perform operation
        do {
            return try await operation()
        } catch {
            // On failure, don't count against rate limit
            reset(for: key)
            throw error
        }
    }
    
    /// Rate limited operation with automatic retry
    func rateLimitedWithRetry<T>(
        key: String,
        maxRetries: Int = 3,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                try checkLimit(for: key)
                return try await operation()
            } catch let error as RateLimitError {
                lastError = error
                
                if let retryAfter = error.retryAfter {
                    // Wait for rate limit to reset
                    try? await Task.sleep(nanoseconds: UInt64(retryAfter) * 1_000_000_000)
                }
            } catch {
                throw error
            }
        }
        
        throw lastError ?? RateLimitError.configurationError
    }
}

// MARK: - Analytics
extension RateLimiter {
    
    struct RateLimitAnalytics {
        let totalRequests: Int
        let rateLimitHits: Int
        let topKeys: [(key: String, count: Int)]
        let averageRequestsPerMinute: Double
    }
    
    func getAnalytics() -> RateLimitAnalytics {
        return queue.sync {
            let totalRequests = requestCounts.values.reduce(0) { $0 + $1.count }
            
            // Count rate limit hits (simplified - would need proper tracking)
            let rateLimitHits = requestCounts.compactMap { key, dates in
                let config = getConfiguration(for: key)
                return dates.count >= config.limit ? 1 : 0
            }.reduce(0, +)
            
            // Get top keys by usage
            let topKeys = requestCounts.map { ($0.key, $0.value.count) }
                .sorted { $0.1 > $1.1 }
                .prefix(10)
                .map { $0 }
            
            // Calculate average requests per minute
            let now = Date()
            let totalTime: TimeInterval = requestCounts.values
                .compactMap { $0.first }
                .map { now.timeIntervalSince($0) }
                .max() ?? 60
            
            let averageRequestsPerMinute = Double(totalRequests) / (totalTime / 60)
            
            return RateLimitAnalytics(
                totalRequests: totalRequests,
                rateLimitHits: rateLimitHits,
                topKeys: Array(topKeys),
                averageRequestsPerMinute: averageRequestsPerMinute
            )
        }
    }
}
