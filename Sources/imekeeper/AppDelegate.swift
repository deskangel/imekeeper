import AppKit
import IMEKeeperCore

/// 应用程序生命周期与全局核心管道代理
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    
    private let permissionManager = AccessibilityPermissionManager()
    private let inputSourceManager = CarbonInputSourceManager()
    private let granularityManager = GranularityManager()
    private let profileStore = HierarchicalProfileStore()
    private let focusObserver = FocusObserver()
    
    private var settingsViewModel: HierarchySettingsViewModel!
    private var settingsWindowController: SettingsWindowController!
    private var menuBarController: MenuBarController!
    
    private var currentFocusContext: FocusContext?
    private var isEnabled: Bool = true
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置为主体 UI 代理，确保支持无 Dock 图标常驻
        NSApp.setActivationPolicy(.accessory)
        
        setupViewModelAndUI()
        setupEventPipelines()
        checkAccessibilityPermission()
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        focusObserver.stopObserving()
    }
    
    // MARK: - Setup
    
    private func setupViewModelAndUI() {
        self.settingsViewModel = HierarchySettingsViewModel(
            store: profileStore,
            granularityManager: granularityManager,
            inputSourceManager: inputSourceManager
        )
        
        self.settingsWindowController = SettingsWindowController(viewModel: settingsViewModel)
        
        self.menuBarController = MenuBarController(
            onOpenSettings: { [weak self] in
                self?.settingsWindowController.showWindow()
            },
            onToggleEnabled: { [weak self] in
                guard let self = self else { return }
                self.isEnabled.toggle()
                self.settingsViewModel.isEnabled = self.isEnabled
                self.updateStatusItemState()
            },
            onCheckPermission: { [weak self] in
                self?.handleCheckPermissionAction()
            }
        )
        
        updateStatusItemState()
    }
    
    private func setupEventPipelines() {
        // 1. 注册系统焦点变化事件流
        focusObserver.startObserving { [weak self] context in
            Task { @MainActor [weak self] in
                self?.handleFocusChanged(context)
            }
        }
        
        // 2. 注册用户手动按键切换输入法事件流
        inputSourceManager.setOnUserChangedSourceHandler { [weak self] newSource in
            Task { @MainActor [weak self] in
                self?.handleUserManualSwitchedSource(newSource)
            }
        }
    }
    
    // MARK: - Core Event Handlers
    
    private func handleFocusChanged(_ context: FocusContext) {
        // 关键过滤：忽略自身的焦点变化，绝不将 IME Keeper 自身加入记忆库或切换自身输入法
        guard context.bundleID != Bundle.main.bundleIdentifier,
              context.bundleID != "com.antigravity.imekeeper" else {
            return
        }
        
        self.currentFocusContext = context
        updateStatusItemState()
        settingsViewModel.handleFocusChanged(context)
        
        guard isEnabled else { return }
        
        // 遇到密码输入框：静默保护，切为 ASCII 并不记录敏感上下文
        if context.isSecureField {
            inputSourceManager.selectSource(id: AppConstants.InputSource.defaultAsciiSourceID)
            return
        }
        
        // 解析该应用的有效生效粒度（浏览器强制截断为 Window 级）
        let effectiveGranularity = granularityManager.effectiveGranularity(
            for: context.bundleID,
            isBrowser: context.isBrowserApp
        )
        
        // 查询该上下文应使用的输入法偏好
        if let targetSourceID = profileStore.queryPreferredSource(for: context, effectiveGranularity: effectiveGranularity) {
            if targetSourceID != inputSourceManager.currentSource.id {
                inputSourceManager.selectSource(id: targetSourceID)
            }
        } else {
            // 初次遇见：记录当前系统现有输入法作为基准
            let currentSourceID = inputSourceManager.currentSource.id
            profileStore.record(
                context: context,
                sourceID: currentSourceID,
                effectiveGranularity: effectiveGranularity
            )
            settingsViewModel.refreshTree()
        }
    }
    
    private func handleUserManualSwitchedSource(_ newSource: InputSourceModel) {
        updateStatusItemState()
        settingsViewModel.currentActiveSource = newSource
        
        // 如果当前前台应用为 IME Keeper 自身（例如用户在设置面板中），不覆盖记录其他应用上下文
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.processIdentifier == ProcessInfo.processInfo.processIdentifier ||
           frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }
        
        guard let context = currentFocusContext,
              !context.isSecureField,
              context.bundleID != Bundle.main.bundleIdentifier,
              context.bundleID != "com.antigravity.imekeeper" else { return }
        
        let effectiveGranularity = granularityManager.effectiveGranularity(
            for: context.bundleID,
            isBrowser: context.isBrowserApp
        )
        
        // 关键防护：如果当前上下文（或所属层级）已处于锁定状态，临时手动切换输入法不更新设置
        if profileStore.isContextLocked(for: context, effectiveGranularity: effectiveGranularity) {
            return
        }
        
        // 用户主动切换：即时更新当前层级绑定的输入法
        profileStore.record(
            context: context,
            sourceID: newSource.id,
            effectiveGranularity: effectiveGranularity
        )
        settingsViewModel.refreshTree()
    }
    
    private func updateStatusItemState() {
        let currentName = inputSourceManager.currentSource.localizedName
        let isLocked: Bool
        if let context = currentFocusContext {
            let effectiveGranularity = granularityManager.effectiveGranularity(
                for: context.bundleID,
                isBrowser: context.isBrowserApp
            )
            isLocked = profileStore.isContextLocked(for: context, effectiveGranularity: effectiveGranularity)
        } else {
            isLocked = false
        }
        menuBarController.updateState(isEnabled: isEnabled, currentSourceName: currentName, isLocked: isLocked)
    }
    
    // MARK: - Permission
    
    private func checkAccessibilityPermission() {
        if !permissionManager.isGranted {
            permissionManager.requestPermission()
        }
    }
    
    private func handleCheckPermissionAction() {
        if permissionManager.isGranted {
            let alert = NSAlert()
            alert.messageText = "辅助功能权限正常"
            alert.informativeText = "IME Keeper 已获得系统辅助功能授权，正在正常运行。"
            alert.alertStyle = .informational
            alert.runModal()
        } else {
            let alert = NSAlert()
            alert.messageText = "需要辅助功能授权"
            alert.informativeText = "IME Keeper 需要辅助功能权限以检测窗口和输入框焦点的变化。请在系统设置中启用授权。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                permissionManager.openSystemSettingsAccessibilityPage()
            }
        }
    }
}
