import Foundation
import AppKit
import ApplicationServices

/// 辅助功能权限 (TCC Accessibility) 管理器
public final class AccessibilityPermissionManager: @unchecked Sendable {
    
    public init() {}
    
    /// 检查当前进程是否已获得辅助功能授权
    public var isGranted: Bool {
        return AXIsProcessTrusted()
    }
    
    /// 向系统申请辅助功能权限（若未授权将弹出系统授权引导弹窗）
    @discardableResult
    public func requestPermission() -> Bool {
        let key = AppConstants.Accessibility.trustedCheckOptionPromptKey as CFString
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    /// 直接打开 macOS 系统设置的辅助功能授权页面
    public func openSystemSettingsAccessibilityPage() {
        let path = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: path) {
            NSWorkspace.shared.open(url)
        }
    }
}
