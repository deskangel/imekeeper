import AppKit
import IMEKeeperCore

/// 状态栏常驻图标控制器
@MainActor
public final class MenuBarController: NSObject {
    
    private var statusItem: NSStatusItem?
    private let onOpenSettings: () -> Void
    private let onToggleEnabled: () -> Void
    private let onCheckPermission: () -> Void
    private var isEnabled: Bool = true
    private var currentSourceName: String = "未获取"
    
    public init(
        onOpenSettings: @escaping () -> Void,
        onToggleEnabled: @escaping () -> Void,
        onCheckPermission: @escaping () -> Void
    ) {
        self.onOpenSettings = onOpenSettings
        self.onToggleEnabled = onToggleEnabled
        self.onCheckPermission = onCheckPermission
        super.init()
        setupStatusItem()
    }
    
    public func updateState(isEnabled: Bool, currentSourceName: String) {
        self.isEnabled = isEnabled
        self.currentSourceName = currentSourceName
        rebuildMenu()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        
        let config = NSImage.SymbolConfiguration(pointSize: AppConstants.UI.statusItemIconSize, weight: .regular)
        if let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "IME Keeper")?.withSymbolConfiguration(config) {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "IME"
        }
        
        rebuildMenu()
    }
    
    private func rebuildMenu() {
        let menu = NSMenu()
        
        // 标题与状态
        let statusTitle = isEnabled ? "IME Keeper: 运行中" : "IME Keeper: 已暂停"
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        
        let currentSourceItem = NSMenuItem(title: "当前输入法: \(currentSourceName)", action: nil, keyEquivalent: "")
        currentSourceItem.isEnabled = false
        menu.addItem(currentSourceItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 偏好设置
        let settingsItem = NSMenuItem(title: "偏好设置与层级记忆...", action: #selector(handleOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        // 快捷暂停/继续
        let toggleTitle = isEnabled ? "暂停自动切换" : "恢复自动切换"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(handleToggleEnabled), keyEquivalent: "p")
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        // 权限检查
        let permItem = NSMenuItem(title: "检查辅助功能权限...", action: #selector(handleCheckPermission), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 退出
        let quitItem = NSMenuItem(title: "退出 IME Keeper", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        self.statusItem?.menu = menu
    }
    
    @objc private func handleOpenSettings() {
        onOpenSettings()
    }
    
    @objc private func handleToggleEnabled() {
        onToggleEnabled()
    }
    
    @objc private func handleCheckPermission() {
        onCheckPermission()
    }
    
    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }
}
