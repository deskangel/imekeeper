import AppKit

/// 应用程序图标缓存与获取管理器
public final class AppIconProvider: @unchecked Sendable {
    public static let shared = AppIconProvider()
    
    private let cache = NSCache<NSString, NSImage>()
    
    public init() {
        cache.countLimit = AppConstants.Storage.maxAppEntriesCount
    }
    
    /// 根据 Bundle Identifier 获取应用程序图标
    /// - Parameter bundleID: 目标应用程序的 Bundle Identifier（例如 "com.apple.dt.Xcode"）
    /// - Returns: 解析到的 NSImage，若应用未安装或未找到则返回 nil
    public func icon(for bundleID: String) -> NSImage? {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let cacheKey = trimmed as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        
        // 1. 若应用处于运行状态，直接获取运行中实例的图标
        if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: trimmed).first,
           let runningIcon = runningApp.icon {
            cache.setObject(runningIcon, forKey: cacheKey)
            return runningIcon
        }
        
        // 2. 若未运行，尝试通过 NSWorkspace 解析本地应用程序安装路径
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed) {
            let fileIcon = NSWorkspace.shared.icon(forFile: appURL.path)
            cache.setObject(fileIcon, forKey: cacheKey)
            return fileIcon
        }
        
        return nil
    }
    
    /// 清除内存中的图标缓存
    public func clearCache() {
        cache.removeAllObjects()
    }
}
