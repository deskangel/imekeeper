import Foundation

/// 浏览器应用检测器：用于判定目标 App 是否应限制在 Window 级，避免深入 Web DOM
public struct BrowserAppDetector: Sendable {
    
    public init() {}
    
    /// 检查指定 Bundle ID 是否属于已知浏览器
    public func isBrowser(bundleID: String) -> Bool {
        return AppConstants.Browsers.knownBrowserBundleIDs.contains(bundleID)
    }
}
