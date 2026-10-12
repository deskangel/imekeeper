import Foundation

/// 追踪粒度策略管理器：负责全局默认粒度与单应用粒度配置的读取与持久化
public final class GranularityManager: @unchecked Sendable {
    
    private let lock = NSLock()
    private var appGranularities: [String: GranularityLevel] = [:]
    private var globalDefault: GranularityLevel = .field
    private let storageURL: URL
    
    public init(customStorageURL: URL? = nil) {
        if let customURL = customStorageURL {
            self.storageURL = customURL
        } else {
            let fileManager = FileManager.default
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let folderURL = appSupport.appendingPathComponent(AppConstants.Storage.appSupportFolderName, isDirectory: true)
            try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            self.storageURL = folderURL.appendingPathComponent(AppConstants.Storage.granularityStorageFileName)
        }
        loadFromDisk()
    }
    
    /// 获取指定 Bundle ID 应用的实际生效粒度
    /// - Parameters:
    ///   - bundleID: 目标应用 ID
    ///   - isBrowser: 该应用是否为已知 Web 浏览器（若为浏览器，强制截断至不超过 .window 级）
    public func effectiveGranularity(for bundleID: String, isBrowser: Bool = false) -> GranularityLevel {
        lock.lock()
        defer { lock.unlock() }
        
        let configured = appGranularities[bundleID] ?? globalDefault
        
        // 浏览器特殊约束：不深入 Web 内部，最高允许到 .window 级
        if isBrowser {
            if configured == .field {
                return .window
            }
        }
        return configured
    }
    
    /// 获取指定 App 是否有独立配置过粒度（否则为 nil，代表跟随默认）
    public func configuredGranularity(for bundleID: String) -> GranularityLevel? {
        lock.lock()
        defer { lock.unlock() }
        return appGranularities[bundleID]
    }
    
    /// 设置某个 App 的生效粒度
    public func setGranularity(for bundleID: String, level: GranularityLevel?) {
        lock.lock()
        if let level = level {
            appGranularities[bundleID] = level
        } else {
            appGranularities.removeValue(forKey: bundleID)
        }
        lock.unlock()
        saveToDisk()
    }
    
    /// 获取全局默认粒度
    public func getGlobalDefault() -> GranularityLevel {
        lock.lock()
        defer { lock.unlock() }
        return globalDefault
    }
    
    /// 设置全局默认粒度
    public func setGlobalDefault(_ level: GranularityLevel) {
        lock.lock()
        globalDefault = level
        lock.unlock()
        saveToDisk()
    }
    
    /// 获取当前所有已自定义粒度的应用字典快照
    public func getAllConfiguredGranularities() -> [String: GranularityLevel] {
        lock.lock()
        defer { lock.unlock() }
        return appGranularities
    }
    
    // MARK: - Persistence
    
    private struct PersistedGranularityData: Codable {
        let globalDefault: GranularityLevel
        let appGranularities: [String: GranularityLevel]
    }
    
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode(PersistedGranularityData.self, from: data) else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        self.globalDefault = decoded.globalDefault
        self.appGranularities = decoded.appGranularities
    }
    
    private func saveToDisk() {
        lock.lock()
        let dataToSave = PersistedGranularityData(
            globalDefault: globalDefault,
            appGranularities: appGranularities
        )
        lock.unlock()
        
        guard let encoded = try? JSONEncoder().encode(dataToSave) else { return }
        try? encoded.write(to: storageURL, options: .atomic)
    }
}
