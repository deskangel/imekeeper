import AppKit
import Combine
import IMEKeeperCore

/// 应用程序生命周期与全局核心管道代理
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    
    private let permissionManager = AccessibilityPermissionManager()
    private let inputSourceManager = CarbonInputSourceManager()
    private let granularityManager = GranularityManager()
    private let profileStore = HierarchicalProfileStore()
    private let focusObserver = FocusObserver()
    private let autoStartManager = AutoStartManager()
    
    private var settingsViewModel: HierarchySettingsViewModel!
    private var settingsWindowController: SettingsWindowController!
    private var menuBarController: MenuBarController!
    
    private var currentFocusContext: FocusContext?
    private var isEnabled: Bool = true
    private var cancellables = Set<AnyCancellable>()
    
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
            inputSourceManager: inputSourceManager,
            autoStartManager: autoStartManager
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
            onToggleAutoStart: { [weak self] in
                guard let self = self else { return }
                let target = !self.autoStartManager.isAutoStartEnabled
                self.settingsViewModel.setAutoStartEnabled(target)
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
        
        // 3. 监听多语言切换事件，动态刷新菜单与窗口标题
        LocalizationManager.shared.$currentLanguage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.menuBarController.refreshMenu()
                self.updateStatusItemState()
                self.settingsWindowController.updateTitle()
            }
            .store(in: &cancellables)
            
        // 4. 监听开机自启状态变化，同步刷新状态栏菜单勾选状态
        settingsViewModel.$isAutoStartEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemState()
            }
            .store(in: &cancellables)
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
        
        // 关键前置判断：非输入框焦点行为策略判定
        if !context.isInputField {
            let policy = granularityManager.effectiveNonInputPolicy(for: context.bundleID)
            switch policy {
            case .exempt:
                // 豁免（如终端软件或用户指定豁免）：不强切英文，也不记录脏数据，保持用户当前输入法
                break
            case .alwaysEnglish, .followGlobal:
                // 性能极致优化：当前如果已经是英文模式，直接短路返回，零系统调用开销
                if inputSourceManager.currentSource.id != AppConstants.InputSource.defaultAsciiSourceID {
                    inputSourceManager.selectSource(id: AppConstants.InputSource.defaultAsciiSourceID)
                }
                return
            }
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
        
        let isExemptApp = granularityManager.effectiveNonInputPolicy(for: context.bundleID) == .exempt
        // 非输入框且非豁免应用：不将临时手动切换污染写入记忆库
        guard context.isInputField || isExemptApp else { return }
        
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
        menuBarController.updateState(
            isEnabled: isEnabled,
            currentSourceName: currentName,
            isLocked: isLocked,
            isAutoStartEnabled: autoStartManager.isAutoStartEnabled
        )
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
            alert.messageText = L10n.permissionGrantedTitle
            alert.informativeText = L10n.permissionGrantedMessage
            alert.alertStyle = .informational
            alert.runModal()
        } else {
            let alert = NSAlert()
            alert.messageText = L10n.permissionNeededTitle
            alert.informativeText = L10n.permissionNeededMessage
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.openSystemSettingsButton)
            alert.addButton(withTitle: L10n.laterButton)
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                permissionManager.openSystemSettingsAccessibilityPage()
            }
        }
    }
}
