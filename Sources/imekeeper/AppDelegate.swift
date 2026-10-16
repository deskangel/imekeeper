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
    
    /// 用户手动切换记录：用于在冷静保护期内抑制伴随焦点事件的错误纠偏与非输入区切英
    private var lastManualSwitchTimestamp: Date?
    private var lastManualSwitchBundleID: String?
    private var lastManualSwitchSourceID: String?
    
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
        // 1. 注册系统焦点变化事件流（主线程直接同步进入 MainActor，避免 Task 额外调度延迟）
        focusObserver.startObserving { [weak self] context in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.handleFocusChanged(context)
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.handleFocusChanged(context)
                }
            }
        }
        
        // 2. 注册用户手动按键切换输入法事件流（主线程直接同步进入 MainActor）
        inputSourceManager.setOnUserChangedSourceHandler { [weak self] newSource in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.handleUserManualSwitchedSource(newSource)
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.handleUserManualSwitchedSource(newSource)
                }
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
        
        guard isEnabled else {
            settingsViewModel.handleFocusChanged(context)
            return
        }
        
        // 遇到密码输入框：静默保护，切为 ASCII 并不记录敏感上下文
        if context.isSecureField {
            let targetAsciiID = inputSourceManager.defaultAsciiSourceID
            if inputSourceManager.currentSource.id != targetAsciiID {
                inputSourceManager.selectSource(id: targetAsciiID)
            }
            settingsViewModel.handleFocusChanged(context)
            return
        }
        
        // 关键防回弹判定：检查是否处于该应用的手动切换保护冷静期内
        let now = Date()
        let isWithinManualGracePeriod: Bool
        if let lastTime = lastManualSwitchTimestamp,
           let lastBundle = lastManualSwitchBundleID,
           lastBundle == context.bundleID,
           now.timeIntervalSince(lastTime) <= AppConstants.Timing.manualSwitchGracePeriodSeconds {
            isWithinManualGracePeriod = true
        } else {
            isWithinManualGracePeriod = false
        }
        
        // 解析该应用的有效生效粒度
        let effectiveGranularity = granularityManager.effectiveGranularity(
            for: context.bundleID,
            isBrowser: context.isBrowserApp
        )
        
        // 关键前置判断：非输入框焦点行为策略判定
        if !context.isInputField {
            // 用户在保护冷静期内刚手动切换过输入法，豁免非输入区切英，绝对尊重用户刚指定的输入法
            if isWithinManualGracePeriod {
                settingsViewModel.handleFocusChanged(context)
                return
            }
            
            let policy = granularityManager.effectiveNonInputPolicy(for: context.bundleID)
            switch policy {
            case .exempt:
                // 豁免（如终端软件或用户指定豁免）：不强切英文，按层级配置回退
                break
            case .alwaysEnglish:
                // 明确针对该 App 配置了非输入区切英（或全局默认切英）：
                // 若该 App 在应用级别配置或记忆了有效的 ASCII 输入法（例如用户设置为了“美国”），优先切换至该偏好；
                // 否则切换至系统默认的 ASCII 输入法
                let appPreferredID = profileStore.queryPreferredSource(for: context, effectiveGranularity: effectiveGranularity)
                let targetID: String
                if let appID = appPreferredID,
                   inputSourceManager.availableSources.first(where: { $0.id == appID })?.isAsciiCapable == true {
                    targetID = appID
                } else {
                    targetID = inputSourceManager.defaultAsciiSourceID
                }
                
                if inputSourceManager.currentSource.id != targetID {
                    inputSourceManager.selectSource(id: targetID)
                }
                settingsViewModel.handleFocusChanged(context)
                return
            case .followGlobal:
                // 在 field 粒度下，回退并尊重该 App 在设置面板中配置的输入法偏好；
                // 仅在 app 粒度下由全局默认策略保障切英
                if effectiveGranularity == .field {
                    break
                }
                let targetID = inputSourceManager.defaultAsciiSourceID
                if inputSourceManager.currentSource.id != targetID {
                    inputSourceManager.selectSource(id: targetID)
                }
                settingsViewModel.handleFocusChanged(context)
                return
            }
        }
        
        // 处于保护冷静期内：
        // 若当前实际输入法与用户手动切换的目标一致，阻断时序竞态引起的旧记忆回滚；若未锁定则同步刷新偏好
        if isWithinManualGracePeriod,
           let manualSourceID = lastManualSwitchSourceID,
           inputSourceManager.currentSource.id == manualSourceID {
            if !profileStore.isContextLocked(for: context, effectiveGranularity: effectiveGranularity) {
                profileStore.record(
                    context: context,
                    sourceID: manualSourceID,
                    effectiveGranularity: effectiveGranularity
                )
                settingsViewModel.refreshTree()
            }
            settingsViewModel.handleFocusChanged(context)
            return
        }
        
        // 查询该上下文应使用的输入法偏好
        if let targetSourceID = profileStore.queryPreferredSource(for: context, effectiveGranularity: effectiveGranularity) {
            if targetSourceID != inputSourceManager.currentSource.id {
                inputSourceManager.selectSource(id: targetSourceID)
            }
            
            // 若当前生效粒度要求追踪窗口或输入框，且当前具体层级尚未记录，则继承父级偏好并收录该节点
            if profileStore.shouldAutoRecordContext(context, effectiveGranularity: effectiveGranularity) {
                profileStore.record(
                    context: context,
                    sourceID: targetSourceID,
                    effectiveGranularity: effectiveGranularity
                )
                settingsViewModel.refreshTree()
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
        
        settingsViewModel.handleFocusChanged(context)
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
        
        // 记录用户手动切换的时间与上下文信息，开启保护冷静期
        lastManualSwitchTimestamp = Date()
        lastManualSwitchBundleID = context.bundleID
        lastManualSwitchSourceID = newSource.id
        
        let effectiveGranularity = granularityManager.effectiveGranularity(
            for: context.bundleID,
            isBrowser: context.isBrowserApp
        )
        
        // 关键防护：如果当前上下文（或所属层级）已处于锁定状态，临时手动切换输入法不更新设置
        if profileStore.isContextLocked(for: context, effectiveGranularity: effectiveGranularity) {
            return
        }
        
        // 确定记录层级：
        // 1. 若当前在输入框内（或应用为终端豁免），按当前有效粒度完整记录
        // 2. 若当前在非输入框内，不写入可能含随机指纹的 field 级，直接记录到 app 级基准
        let isExemptApp = granularityManager.effectiveNonInputPolicy(for: context.bundleID) == .exempt
        let recordGranularity: GranularityLevel
        if context.isInputField || isExemptApp {
            recordGranularity = effectiveGranularity
        } else {
            recordGranularity = .app
        }
        
        profileStore.record(
            context: context,
            sourceID: newSource.id,
            effectiveGranularity: recordGranularity
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
