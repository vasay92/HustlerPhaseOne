// NetworkMonitor.swift
// Real-time network connectivity monitoring

import Foundation
import Network
import Combine

// MARK: - Network Monitor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.claudehustler.networkmonitor")
    
    @Published var isConnected = true
    @Published var isExpensive = false
    @Published var connectionType: NWInterface.InterfaceType?
    @Published var connectionStatus: ConnectionStatus = .connected
    @Published var connectionQuality: ConnectionQuality = .good
    
    // Network metrics
    @Published var latency: TimeInterval = 0
    @Published var bandwidth: Double = 0 // Mbps
    @Published var packetLoss: Double = 0 // Percentage
    
    private var cancellables = Set<AnyCancellable>()
    private var statusHistory: [ConnectionStatus] = []
    private var reconnectTimer: Timer?
    private var lastConnectedTime: Date?
    private var disconnectStartTime: Date?
    
    // Callbacks
    var onConnectionLost: (() -> Void)?
    var onConnectionRestored: ((TimeInterval) -> Void)?
    
    enum ConnectionStatus: String {
        case connected = "Connected"
        case connecting = "Connecting"
        case disconnected = "Disconnected"
        case checking = "Checking"
        
        var color: String {
            switch self {
            case .connected: return "green"
            case .connecting: return "orange"
            case .disconnected: return "red"
            case .checking: return "yellow"
            }
        }
        
        var icon: String {
            switch self {
            case .connected: return "wifi"
            case .connecting: return "wifi.slash"
            case .disconnected: return "wifi.exclamationmark"
            case .checking: return "arrow.triangle.2.circlepath"
            }
        }
    }
    
    enum ConnectionQuality: String {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"
        
        var minBandwidth: Double {
            switch self {
            case .excellent: return 50
            case .good: return 10
            case .fair: return 2
            case .poor: return 0
            }
        }
        
        var maxLatency: TimeInterval {
            switch self {
            case .excellent: return 0.02 // 20ms
            case .good: return 0.1 // 100ms
            case .fair: return 0.3 // 300ms
            case .poor: return .infinity
            }
        }
    }
    
    // MARK: - Initialization
    private init() {
        startMonitoring()
        setupMetricsMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updateConnectionStatus(path)
            }
        }
        
        monitor.start(queue: queue)
        
        // Initial check
        performConnectivityCheck()
    }
    
    func stopMonitoring() {
        monitor.cancel()
        reconnectTimer?.invalidate()
        cancellables.removeAll()
    }
    
    func performConnectivityCheck() {
        connectionStatus = .checking
        
        Task {
            let isReachable = await checkInternetConnectivity()
            await MainActor.run {
                if isReachable {
                    connectionStatus = .connected
                } else {
                    connectionStatus = .disconnected
                }
            }
        }
    }
    
    func checkInternetConnectivity() async -> Bool {
        // Try to reach multiple reliable endpoints
        let endpoints = [
            "https://www.google.com",
            "https://www.apple.com",
            "https://www.cloudflare.com"
        ]
        
        for endpoint in endpoints {
            if await canReachEndpoint(endpoint) {
                return true
            }
        }
        
        return false
    }
    
    func waitForConnection() async {
        guard !isConnected else { return }
        
        return await withCheckedContinuation { continuation in
            var observer: AnyCancellable?
            
            observer = $isConnected
                .filter { $0 }
                .first()
                .sink { _ in
                    observer?.cancel()
                    continuation.resume()
                }
        }
    }
    
    // MARK: - Network Quality Metrics
    
    func measureLatency(to host: String = "google.com") async -> TimeInterval {
        let startTime = Date()
        
        guard let url = URL(string: "https://\(host)") else {
            return 0
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        
        do {
            _ = try await URLSession.shared.data(for: request)
            let latency = Date().timeIntervalSince(startTime)
            
            await MainActor.run {
                self.latency = latency
                self.updateConnectionQuality()
            }
            
            return latency
        } catch {
            return 5.0 // Timeout
        }
    }
    
    func estimateBandwidth() async {
        // Download a small test file
        guard let url = URL(string: "https://www.google.com/images/branding/googlelogo/1x/googlelogo_color_272x92dp.png") else {
            return
        }
        
        let startTime = Date()
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let duration = Date().timeIntervalSince(startTime)
            let bytes = Double(data.count)
            let megabits = (bytes * 8) / 1_000_000
            let bandwidth = megabits / duration
            
            await MainActor.run {
                self.bandwidth = bandwidth
                self.updateConnectionQuality()
            }
        } catch {
            await MainActor.run {
                self.bandwidth = 0
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func updateConnectionStatus(_ path: NWPath) {
        let wasConnected = isConnected
        
        isConnected = path.status == .satisfied
        isExpensive = path.isExpensive
        
        // Determine connection type
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .wiredEthernet
        } else {
            connectionType = nil
        }
        
        // Update connection status
        if isConnected {
            connectionStatus = .connected
            
            if !wasConnected {
                // Connection restored
                if let disconnectStart = disconnectStartTime {
                    let downtime = Date().timeIntervalSince(disconnectStart)
                    onConnectionRestored?(downtime)
                    disconnectStartTime = nil
                }
                lastConnectedTime = Date()
                
                // Measure quality after reconnection
                Task {
                    await measureLatency()
                    await estimateBandwidth()
                }
            }
        } else {
            connectionStatus = .disconnected
            
            if wasConnected {
                // Connection lost
                disconnectStartTime = Date()
                onConnectionLost?()
                scheduleReconnectCheck()
            }
        }
        
        // Update history
        statusHistory.append(connectionStatus)
        if statusHistory.count > 100 {
            statusHistory.removeFirst()
        }
    }
    
    private func updateConnectionQuality() {
        if bandwidth >= ConnectionQuality.excellent.minBandwidth &&
           latency <= ConnectionQuality.excellent.maxLatency {
            connectionQuality = .excellent
        } else if bandwidth >= ConnectionQuality.good.minBandwidth &&
                  latency <= ConnectionQuality.good.maxLatency {
            connectionQuality = .good
        } else if bandwidth >= ConnectionQuality.fair.minBandwidth &&
                  latency <= ConnectionQuality.fair.maxLatency {
            connectionQuality = .fair
        } else {
            connectionQuality = .poor
        }
    }
    
    private func setupMetricsMonitoring() {
        // Periodically check network quality when connected
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.isConnected else { return }
                
                Task {
                    await self.measureLatency()
                    await self.estimateBandwidth()
                }
            }
            .store(in: &cancellables)
    }
    
    private func scheduleReconnectCheck() {
        reconnectTimer?.invalidate()
        
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.performConnectivityCheck()
        }
    }
    
    private func canReachEndpoint(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return (200...299).contains(httpResponse.statusCode)
            }
            return false
        } catch {
            return false
        }
    }
    
    // MARK: - Public Properties
    
    var isWiFi: Bool {
        connectionType == .wifi
    }
    
    var isCellular: Bool {
        connectionType == .cellular
    }
    
    var connectionDescription: String {
        guard isConnected else {
            return "No Connection"
        }
        
        var description = ""
        
        switch connectionType {
        case .wifi:
            description = "Wi-Fi"
        case .cellular:
            description = "Cellular"
        case .wiredEthernet:
            description = "Ethernet"
        default:
            description = "Unknown"
        }
        
        if isExpensive {
            description += " (Limited)"
        }
        
        return description
    }
    
    var shouldUseLowDataMode: Bool {
        isExpensive || connectionQuality == .poor
    }
    
    var canStreamVideo: Bool {
        isConnected && !isExpensive && (connectionQuality == .good || connectionQuality == .excellent)
    }
    
    var recommendedImageQuality: CGFloat {
        switch connectionQuality {
        case .excellent:
            return 1.0
        case .good:
            return 0.8
        case .fair:
            return 0.6
        case .poor:
            return 0.4
        }
    }
    
    // MARK: - Statistics
    
    func getConnectionStatistics() -> ConnectionStatistics {
        let uptime = lastConnectedTime.map { Date().timeIntervalSince($0) } ?? 0
        let recentDisconnects = statusHistory.filter { $0 == .disconnected }.count
        
        return ConnectionStatistics(
            currentStatus: connectionStatus,
            connectionType: connectionType,
            quality: connectionQuality,
            uptime: uptime,
            latency: latency,
            bandwidth: bandwidth,
            packetLoss: packetLoss,
            isExpensive: isExpensive,
            recentDisconnects: recentDisconnects
        )
    }
    
    struct ConnectionStatistics {
        let currentStatus: ConnectionStatus
        let connectionType: NWInterface.InterfaceType?
        let quality: ConnectionQuality
        let uptime: TimeInterval
        let latency: TimeInterval
        let bandwidth: Double
        let packetLoss: Double
        let isExpensive: Bool
        let recentDisconnects: Int
        
        var uptimeString: String {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .abbreviated
            return formatter.string(from: uptime) ?? "0m"
        }
        
        var latencyString: String {
            if latency < 1 {
                return "\(Int(latency * 1000))ms"
            } else {
                return String(format: "%.1fs", latency)
            }
        }
        
        var bandwidthString: String {
            if bandwidth < 1 {
                return String(format: "%.0f Kbps", bandwidth * 1000)
            } else {
                return String(format: "%.1f Mbps", bandwidth)
            }
        }
    }
}

// MARK: - Reachability Helper
extension NetworkMonitor {
    
    enum NetworkError: LocalizedError {
        case noConnection
        case poorConnection
        case timeout
        
        var errorDescription: String? {
            switch self {
            case .noConnection:
                return "No internet connection available"
            case .poorConnection:
                return "Poor network connection. Please try again later"
            case .timeout:
                return "Network request timed out"
            }
        }
    }
    
    func throwIfNotConnected() throws {
        guard isConnected else {
            throw NetworkError.noConnection
        }
    }
    
    func throwIfPoorConnection() throws {
        guard isConnected else {
            throw NetworkError.noConnection
        }
        
        guard connectionQuality != .poor else {
            throw NetworkError.poorConnection
        }
    }
}

// MARK: - Network-Aware Operations
extension NetworkMonitor {
    
    func performNetworkOperation<T>(
        requiresGoodConnection: Bool = false,
        operation: () async throws -> T
    ) async throws -> T {
        // Wait for connection if needed
        if !isConnected {
            await waitForConnection()
        }
        
        // Check connection quality if required
        if requiresGoodConnection && connectionQuality == .poor {
            throw NetworkError.poorConnection
        }
        
        return try await operation()
    }
    
    func downloadWithRetry<T>(
        operation: () async throws -> T,
        maxRetries: Int = 3,
        delay: TimeInterval = 1.0
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            // Wait for connection
            if !isConnected {
                await waitForConnection()
            }
            
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // Don't retry if it's not a network error
                if !(error is URLError) && !(error is NetworkError) {
                    throw error
                }
                
                // Wait before retry
                if attempt < maxRetries - 1 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * TimeInterval(attempt + 1) * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? NetworkError.noConnection
    }
}
