import Foundation
import ServiceManagement
import os.log

/// 开机自启服务管理协议
public protocol AutoStartManagerProtocol: AnyObject, Sendable {
    /// 当前是否已启用开机自启
    var isAutoStartEnabled: Bool { get }
    
    /// 是否需要用户在系统设置中手动批准
    var requiresApproval: Bool { get }
    
    /// 设置开机自启状态
    /// - Parameter enabled: true 为开启，false 为关闭
    /// - Returns: 操作是否成功
    @discardableResult
    func setAutoStartEnabled(_ enabled: Bool) -> Bool
    
    /// 打开 macOS 登录项系统设置面板
    func openLoginItemsSettings()
}

/// 基于 macOS 13+ SMAppService 的开机自启管理器
public final class AutoStartManager: AutoStartManagerProtocol, @unchecked Sendable {
    private let logger = Logger(
        subsystem: AppConstants.AutoStart.subsystem,
        category: AppConstants.AutoStart.category
    )
    
    public init() {}
    
    public var isAutoStartEnabled: Bool {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            return status == .enabled
        }
        return false
    }
    
    public var requiresApproval: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .requiresApproval
        }
        return false
    }
    
    @discardableResult
    public func setAutoStartEnabled(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                        logger.info("Successfully registered SMAppService.mainApp for launch at login.")
                    }
                } else {
                    if SMAppService.mainApp.status != .notRegistered {
                        try SMAppService.mainApp.unregister()
                        logger.info("Successfully unregistered SMAppService.mainApp from launch at login.")
                    }
                }
                return true
            } catch {
                logger.error("Failed to update SMAppService status: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        return false
    }
    
    public func openLoginItemsSettings() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}

/// 用于单元测试和 UI Preview 的 Mock 开机自启管理器
public final class MockAutoStartManager: AutoStartManagerProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _isEnabled: Bool
    private var _requiresApproval: Bool
    
    public init(initialEnabled: Bool = false, requiresApproval: Bool = false) {
        self._isEnabled = initialEnabled
        self._requiresApproval = requiresApproval
    }
    
    public var isAutoStartEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isEnabled
    }
    
    public var requiresApproval: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _requiresApproval
    }
    
    @discardableResult
    public func setAutoStartEnabled(_ enabled: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        _isEnabled = enabled
        return true
    }
    
    public func openLoginItemsSettings() {
        // Mock 实现无需真实打开系统面板
    }
}
