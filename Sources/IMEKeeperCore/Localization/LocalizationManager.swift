import Foundation
import Combine

/// 应用程序支持的界面显示语言
public enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    /// 遵循 macOS 系统语言设置（若首选语言为中文则显示中文，否则默认英文）
    case system = "system"
    /// 简体中文
    case zhHans = "zh-Hans"
    /// English
    case en = "en"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .system:
            return LocalizationManager.shared.currentEffectiveLanguage == .zhHans ? "跟随系统 (System)" : "Follow System (System)"
        case .zhHans:
            return "简体中文"
        case .en:
            return "English"
        }
    }
}

/// 全局多语言本地化调度中枢
public final class LocalizationManager: ObservableObject, @unchecked Sendable {
    public static let shared = LocalizationManager()
    
    private let userDefaults: UserDefaults
    private let lock = NSLock()
    
    @Published public private(set) var currentLanguage: AppLanguage {
        didSet {
            userDefaults.set(currentLanguage.rawValue, forKey: AppConstants.Storage.appLanguageStorageKey)
        }
    }
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let savedRaw = userDefaults.string(forKey: AppConstants.Storage.appLanguageStorageKey)
        let initialLang = savedRaw.flatMap { AppLanguage(rawValue: $0) } ?? .system
        self.currentLanguage = initialLang
    }
    
    /// 获取当前计算生效的实际语言（将 system 解析为 zh-Hans 或 en）
    public var currentEffectiveLanguage: AppLanguage {
        lock.lock()
        defer { lock.unlock() }
        if currentLanguage != .system {
            return currentLanguage
        }
        
        // 优先检查 macOS 系统全局首选项中的语言设置，确保与系统实际运行环境 100% 同步
        let globalDefaults = UserDefaults(suiteName: ".GlobalPreferences")
        let globalLangs = globalDefaults?.stringArray(forKey: "AppleLanguages")
        let preferred = globalLangs?.first?.lowercased() ?? Locale.preferredLanguages.first?.lowercased() ?? "en"
        
        if preferred.hasPrefix("zh") {
            return .zhHans
        } else {
            return .en
        }
    }
    
    /// 设置应用程序语言并通知订阅者
    public func setLanguage(_ language: AppLanguage) {
        lock.lock()
        defer { lock.unlock() }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentLanguage = language
        }
    }
}

/// 集中式、强类型本地化文案字典 (无魔法字符串)
public enum L10n {
    
    private static var isChinese: Bool {
        LocalizationManager.shared.currentEffectiveLanguage == .zhHans
    }
    
    // MARK: - Menu Bar
    public static var menuStatusRunning: String {
        isChinese ? "IME Keeper: 运行中" : "IME Keeper: Running"
    }
    
    public static var menuStatusPaused: String {
        isChinese ? "IME Keeper: 已暂停" : "IME Keeper: Paused"
    }
    
    public static func menuCurrentSource(name: String, isLocked: Bool) -> String {
        let suffix = isLocked ? (isChinese ? " (已锁定)" : " (Locked)") : ""
        return isChinese ? "当前输入法: \(name)\(suffix)" : "Current Input Source: \(name)\(suffix)"
    }
    
    public static var menuPreferences: String {
        isChinese ? "偏好设置与层级记忆..." : "Preferences & Hierarchy Memory..."
    }
    
    public static var menuPauseAutoSwitch: String {
        isChinese ? "暂停自动切换" : "Pause Auto Switching"
    }
    
    public static var menuResumeAutoSwitch: String {
        isChinese ? "恢复自动切换" : "Resume Auto Switching"
    }
    
    public static var menuCheckPermission: String {
        isChinese ? "检查辅助功能权限..." : "Check Accessibility Permission..."
    }
    
    public static var menuAutoStart: String {
        isChinese ? "开机自动启动" : "Launch at Login"
    }
    
    public static var launchAtLoginCheckbox: String {
        isChinese ? "开机自启动" : "Launch at Login"
    }
    
    public static var launchAtLoginHelp: String {
        isChinese
            ? "系统登录时自动在后台启动 IME Keeper 并常驻菜单栏"
            : "Automatically launch IME Keeper in background upon system login"
    }
    
    public static var menuLanguage: String {
        isChinese ? "界面语言" : "Language"
    }
    
    public static var menuQuit: String {
        isChinese ? "退出 IME Keeper" : "Quit IME Keeper"
    }
    
    // MARK: - Settings Window
    public static var settingsWindowTitle: String {
        isChinese ? "IME Keeper - 层级记忆与偏好设置" : "IME Keeper - Hierarchy Memory & Preferences"
    }
    
    public static var settingsHeaderSubtitle: String {
        isChinese ? "按应用与输入框组织管理输入法记忆" : "Manage input source memory hierarchically across apps and fields"
    }
    
    public static var searchPlaceholder: String {
        isChinese ? "搜索应用或输入框..." : "Search apps or fields..."
    }
    
    public static var defaultGranularityLabel: String {
        isChinese ? "全局默认粒度:" : "Default Granularity:"
    }
    
    public static var languagePickerLabel: String {
        isChinese ? "语言:" : "Language:"
    }
    
    public static var toggleSwitchHelp: String {
        isChinese ? "启用/暂停自动切换输入法" : "Enable/Pause automatic input source switching"
    }
    
    // MARK: - Live Status Bar
    public static var liveMonitoringFocus: String {
        isChinese ? "正在监控焦点" : "Monitoring Focus"
    }
    
    public static var liveFocusPaused: String {
        isChinese ? "已暂停" : "Paused"
    }
    
    public static var liveFocusedPrefix: String {
        isChinese ? "当前聚焦:" : "Focused:"
    }
    
    public static var liveActiveSourcePrefix: String {
        isChinese ? "活跃输入法:" : "Active Source:"
    }
    
    // MARK: - Empty State
    public static var emptyHistoryTitle: String {
        isChinese ? "暂无捕获到的输入框记忆记录" : "No Input Field Records Captured"
    }
    
    public static var emptyHistorySubtitle: String {
        isChinese
            ? "在其他应用中点击输入框或切换输入法后，将在此自动按层级记录。"
            : "Clicking input fields or switching input sources in other apps will record here automatically."
    }
    
    // MARK: - Footer Actions
    public static var clearAllHistory: String {
        isChinese ? "清空所有历史" : "Clear All History"
    }
    
    public static var reloadInputSources: String {
        isChinese ? "刷新可用输入法" : "Reload Input Sources"
    }
    
    public static var doneButton: String {
        isChinese ? "完成" : "Done"
    }
    
    public static var deleteItemHelp: String {
        isChinese ? "删除此项记忆" : "Delete this memory entry"
    }
    
    public static var cleanAppSubItemsHelp: String {
        isChinese ? "清理此应用下的输入框记录" : "Clean fields in this app"
    }
    
    public static var cleanAppFieldsHelp: String {
        isChinese ? "清理此应用下的输入框记录" : "Clean fields in this app"
    }
    
    public static var noSubItemsToCleanHelp: String {
        isChinese ? "无待清理的下级记录" : "No sub-items to clean"
    }
    
    public static var lockedAppCannotCleanHelp: String {
        isChinese
            ? "应用已锁定，下级记录受保护无法清理，请先解锁应用"
            : "App is locked; sub-items are protected and cannot be cleaned. Unlock app first"
    }
    
    public static var cleanUnlockedFieldsHelp: String {
        isChinese ? "清理此应用下未锁定的输入框记录" : "Clean unlocked fields in this app"
    }
    
    public static var noUnlockedFieldsToCleanHelp: String {
        isChinese ? "无待清理的未锁定输入框记录" : "No unlocked fields to clean"
    }
    
    public static var fieldLevelNoCleanNeededHelp: String {
        isChinese
            ? "当前为输入框级粒度，所有记录均在生效中，无需清理"
            : "Field-level granularity: all records are active, no cleanup needed"
    }
    
    public static var cleanAllRedundantButton: String {
        isChinese ? "清理冗余记录" : "Clean Redundant"
    }
    
    public static var cleanAllRedundantHelp: String {
        isChinese
            ? "根据各应用的生效粒度与锁定状态，一键清理所有可清理的输入框记录"
            : "Clean all cleanable field records according to each app's granularity and lock status"
    }
    
    public static var granularityHelp: String {
        isChinese ? "设置该应用允许生效的最大追踪粒度" : "Set the maximum effective tracking granularity for this app"
    }
    
    public static var nonInputPolicyHelp: String {
        isChinese ? "设置该应用在焦点离开输入框时的输入法行为" : "Set input source behavior when focus is outside text fields for this app"
    }
    
    public static var globalNonInputLabel: String {
        isChinese ? "非输入行为:" : "Non-Input Action:"
    }
    
    public static var globalNonInputHelp: String {
        isChinese ? "设置全局默认在非输入框时是自动切为英文还是保持当前输入法" : "Global default behavior when focus is outside text fields"
    }
    
    // MARK: - Granularity Names & Descriptions
    public static func granularityName(for level: GranularityLevel) -> String {
        switch level {
        case .app:
            return isChinese ? "应用级 (App)" : "App Level (App)"
        case .field:
            return isChinese ? "输入框级 (Field)" : "Field Level (Field)"
        }
    }
    
    public static func granularityDetail(for level: GranularityLevel) -> String {
        switch level {
        case .app:
            return isChinese
                ? "该 App 内所有输入框统一使用同一个输入法"
                : "All input fields in this app share the same input source"
        case .field:
            return isChinese
                ? "精细记忆各个输入框，按控件独立切换"
                : "Precisely remember each input field and switch per control"
        }
    }
    
    // MARK: - Non-Input Policy Names & Descriptions
    public static func nonInputPolicyName(for policy: NonInputPolicy) -> String {
        switch policy {
        case .followGlobal:
            return isChinese ? "跟随全局 (Global)" : "Follow Global (Global)"
        case .alwaysEnglish:
            return isChinese ? "切为英文 (English)" : "Switch to English (English)"
        case .exempt:
            return isChinese ? "豁免保持 (Exempt)" : "Exempt (Keep Source)"
        }
    }
    
    public static func nonInputPolicyDetail(for policy: NonInputPolicy) -> String {
        switch policy {
        case .followGlobal:
            return isChinese
                ? "遵循全局默认配置（默认：非输入区自动切为英文）"
                : "Follow global default configuration (default: switch to English outside inputs)"
        case .alwaysEnglish:
            return isChinese
                ? "焦点离开输入框时立即自动切换为英文模式"
                : "Immediately switch to English mode when focus is outside text fields"
        case .exempt:
            return isChinese
                ? "豁免保护：非输入框不切英文，保护终端与绘图快捷键"
                : "Exempt protection: Do not switch to English, preserving terminal or drawing flow"
        }
    }
    
    // MARK: - Lock UI Badges & Tooltips
    public static var appLockBadge: String {
        isChinese ? "应用锁定" : "App Locked"
    }
    
    public static var fieldLockBadge: String {
        isChinese ? "输入框锁定" : "Field Locked"
    }
    
    public static var inheritedLockBadgePrefix: String {
        isChinese ? "继承" : "Inherited "
    }
    
    public static var lockActionText: String {
        isChinese ? "锁定" : "Locked"
    }
    
    public static var unlockedActionText: String {
        isChinese ? "未锁定" : "Unlocked"
    }
    
    public static var appLockHelpText: String {
        isChinese
            ? "应用级锁定：此应用下的输入法已被固定，临时手动切换后不会更新设置"
            : "App-level lock: Input source is fixed for this app; temporary manual switches will not update settings"
    }
    
    public static var fieldLockHelpText: String {
        isChinese
            ? "输入框级锁定：此输入框下的输入法已被固定，临时手动切换后不会更新设置"
            : "Field-level lock: Input source is fixed for this field; temporary manual switches will not update settings"
    }
    
    public static var inheritedLockHelpText: String {
        isChinese
            ? "受上级锁定保护：临时手动切换后不会更新设置"
            : "Protected by parent lock: Temporary manual switches will not update settings"
    }
    
    public static var unlockedHelpText: String {
        isChinese
            ? "点击锁定此层级输入法，临时手动切换后不改变设置"
            : "Click to lock input source at this level; manual switches will not update settings"
    }
    
    // MARK: - Tree Hierarchy Item Subtitles & Labels
    public static var defaultWindowPlaceholder: String {
        isChinese ? "主窗口" : "Main Window"
    }
    
    public static func fieldRoleSubtitle(role: String) -> String {
        isChinese ? "角色: \(role)" : "Role: \(role)"
    }
    
    public static func fieldHashSubtitle(hashPrefix: String) -> String {
        isChinese ? "哈希: \(hashPrefix)" : "Hash: \(hashPrefix)"
    }
    
    public static var doubleClickToRenameHelp: String {
        isChinese ? "双击以重命名输入框" : "Double-click to rename field"
    }
    
    // MARK: - Accessibility Alerts
    public static var permissionGrantedTitle: String {
        isChinese ? "辅助功能权限正常" : "Accessibility Permission Granted"
    }
    
    public static var permissionGrantedMessage: String {
        isChinese
            ? "IME Keeper 已获得系统辅助功能授权，正在正常运行。"
            : "IME Keeper has accessibility authorization and is running properly."
    }
    
    public static var permissionNeededTitle: String {
        isChinese ? "需要辅助功能授权" : "Accessibility Permission Required"
    }
    
    public static var permissionNeededMessage: String {
        isChinese
            ? "IME Keeper 需要辅助功能权限以检测窗口和输入框焦点的变化。请在系统设置中启用授权。"
            : "IME Keeper requires accessibility permission to detect focus changes across windows and input fields. Please enable it in System Settings."
    }
    
    public static var openSystemSettingsButton: String {
        isChinese ? "打开系统设置" : "Open System Settings"
    }
    
    public static var laterButton: String {
        isChinese ? "稍后" : "Later"
    }
}
