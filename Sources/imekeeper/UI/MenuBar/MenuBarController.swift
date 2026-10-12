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
    private var isLocked: Bool = false
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
    
    public func updateState(isEnabled: Bool, currentSourceName: String, isLocked: Bool = false) {
        self.isEnabled = isEnabled
        self.currentSourceName = currentSourceName
        self.isLocked = isLocked
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
    
    public func refreshMenu() {
        rebuildMenu()
    }
    
    private func rebuildMenu() {
        let menu = NSMenu()
        
        // 标题与状态
        let statusTitle = isEnabled ? L10n.menuStatusRunning : L10n.menuStatusPaused
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        
        let currentSourceItem = NSMenuItem(
            title: L10n.menuCurrentSource(name: currentSourceName, isLocked: isLocked),
            action: nil,
            keyEquivalent: ""
        )
        currentSourceItem.isEnabled = false
        menu.addItem(currentSourceItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 偏好设置
        let settingsItem = NSMenuItem(title: L10n.menuPreferences, action: #selector(handleOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        // 快捷暂停/继续
        let toggleTitle = isEnabled ? L10n.menuPauseAutoSwitch : L10n.menuResumeAutoSwitch
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(handleToggleEnabled), keyEquivalent: "p")
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        // 权限检查
        let permItem = NSMenuItem(title: L10n.menuCheckPermission, action: #selector(handleCheckPermission), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 界面语言快速切换子菜单
        let langMenuItem = NSMenuItem(title: L10n.menuLanguage, action: nil, keyEquivalent: "")
        let langSubmenu = NSMenu(title: L10n.menuLanguage)
        for lang in AppLanguage.allCases {
            let item = NSMenuItem(title: lang.displayName, action: #selector(handleSelectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang
            item.state = (LocalizationManager.shared.currentLanguage == lang) ? .on : .off
            langSubmenu.addItem(item)
        }
        langMenuItem.submenu = langSubmenu
        menu.addItem(langMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 退出
        let quitItem = NSMenuItem(title: L10n.menuQuit, action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        self.statusItem?.menu = menu
    }
    
    @objc private func handleSelectLanguage(_ sender: NSMenuItem) {
        if let lang = sender.representedObject as? AppLanguage {
            LocalizationManager.shared.setLanguage(lang)
            rebuildMenu()
        }
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
