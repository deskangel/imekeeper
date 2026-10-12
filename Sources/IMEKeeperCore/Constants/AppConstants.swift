import Foundation

/// 系统全局常量定义，遵循严禁魔法数字与硬编码规范
public enum AppConstants {
    
    /// 防抖与时序控制参数
    public enum Timing {
        /// 焦点切换防抖延迟（毫秒）：避免快速拖拽或瞬时失焦引起的频繁切换
        public static let focusDebounceMilliseconds: Int = 35
        
        /// 程序化切换输入法后的状态抑制窗口（秒）：用于忽略系统自广播的 kTISNotifySelectedKeyboardInputSourceChanged 通知
        public static let antiLoopSuppressionTimeoutSeconds: TimeInterval = 0.45
        
        /// 轮询或检查权限时的间隔（秒）
        public static let permissionCheckIntervalSeconds: TimeInterval = 1.0
    }
    
    /// 存储与缓存容量配置
    public enum Storage {
        /// 持久化数据文件名
        public static let profileStorageFileName = "imekeeper_profiles.json"
        
        /// 粒度设置文件名
        public static let granularityStorageFileName = "imekeeper_granularity.json"
        
        /// 应用程序支持目录子文件夹名称
        public static let appSupportFolderName = "IMEKeeper"
        
        /// 内存中最多保留的应用层级指纹记录上限
        public static let maxAppEntriesCount: Int = 500
        
        /// 单个应用下最多保留的输入框指纹数量
        public static let maxFieldEntriesPerApp: Int = 300
        
        /// 应用程序语言偏好持久化 Key
        public static let appLanguageStorageKey = "imekeeper_selected_language"
    }
    
    /// 浏览器应用 Bundle ID 集合（对于这些应用，强制截断至 Window 级别，不解析深层 DOM 控件）
    public enum Browsers {
        public static let knownBrowserBundleIDs: Set<String> = [
            "com.apple.Safari",
            "com.apple.SafariTechnologyPreview",
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "org.mozilla.firefox",
            "org.mozilla.nightly",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "company.thebrowser.Browser", // Arc Browser
            "com.operasoftware.Opera",
            "com.vivaldi.Vivaldi",
            "com.uranus.sigmaos",
            "com.kagi.kagimacOS" // Orion Browser
        ]
    }
    
    /// 辅助功能与无障碍属性常量
    public enum Accessibility {
        /// 申请辅助功能弹窗提示选项 Key
        public static let trustedCheckOptionPromptKey = "AXTrustedCheckOptionPrompt"
        
        /// 安全输入（密码框）的角色标识
        public static let secureTextFieldRole = "AXSecureTextField"
        public static let textFieldRole = "AXTextField"
        public static let textAreaRole = "AXTextArea"
        public static let searchFieldRole = "AXSearchField"
        public static let webAreaRole = "AXWebArea"
        
        /// 未知或默认占位名
        public static let unknownWindowIdentifier = "UnknownWindow"
        public static let unknownFieldIdentifier = "UnknownField"
        public static let defaultWindowPlaceholder = "主窗口"
    }
    
    /// 默认系统输入法 ID
    public enum InputSource {
        public static let defaultAsciiSourceID = "com.apple.keylayout.ABC"
    }
    
    /// UI 布局与视图尺寸常量
    public enum UI {
        public static let settingsWindowWidth: CGFloat = 860.0
        public static let settingsWindowHeight: CGFloat = 580.0
        public static let minSettingsWindowWidth: CGFloat = 720.0
        public static let minSettingsWindowHeight: CGFloat = 460.0
        
        public static let treeRowHeight: CGFloat = 34.0
        public static let statusItemIconSize: CGFloat = 18.0
        public static let badgeCornerRadius: CGFloat = 4.0
        public static let appRowIconSize: CGFloat = 16.0
        public static let liveStatusAppIconSize: CGFloat = 12.0
        
        public static let languagePickerWidth: CGFloat = 130.0
        public static let globalGranularityPickerWidth: CGFloat = 175.0
        public static let rowGranularityPickerWidth: CGFloat = 135.0
        public static let rowInputSourcePickerWidth: CGFloat = 150.0
        public static let searchFieldWidth: CGFloat = 150.0
        public static let searchFieldCornerRadius: CGFloat = 6.0
        public static let emptyPlaceholderIconSize: CGFloat = 40.0
        public static let headerIconSize: CGFloat = 20.0
        public static let liveStatusIndicatorSize: CGFloat = 8.0
        public static let footerDividerHeight: CGFloat = 14.0
        public static let footerSpacing: CGFloat = 16.0
    }
    
    /// 系统服务与开机自启常量
    public enum AutoStart {
        public static let subsystem = "com.antigravity.imekeeper"
        public static let category = "AutoStartManager"
    }
    
    /// 锁定状态与徽标 UI 常量
    public enum LockUI {
        public static let appLockBadgeText = "应用锁定"
        public static let windowLockBadgeText = "窗口锁定"
        public static let fieldLockBadgeText = "输入框锁定"
        public static let inheritedLockBadgeTextPrefix = "继承"
        public static let lockActionText = "锁定"
        public static let unlockedActionText = "未锁定"
        
        public static let lockedIconName = "lock.fill"
        public static let unlockedIconName = "lock.open"
        public static let lockShieldIconName = "lock.shield.fill"
        
        public static let lockIconSize: CGFloat = 11.0
        public static let lockTextSize: CGFloat = 10.0
        public static let badgePaddingHorizontal: CGFloat = 6.0
        public static let badgePaddingVertical: CGFloat = 3.0
        public static let lockButtonWidth: CGFloat = 86.0
        
        public static let appLockHelpText = "应用级锁定：此应用下的输入法已被固定，临时手动切换后不会更新设置"
        public static let windowLockHelpText = "窗口级锁定：此窗口下的输入法已被固定，临时手动切换后不会更新设置"
        public static let fieldLockHelpText = "输入框级锁定：此输入框下的输入法已被固定，临时手动切换后不会更新设置"
        public static let inheritedLockHelpText = "受上级锁定保护：临时手动切换后不会更新设置"
        public static let unlockedHelpText = "点击锁定此层级输入法，临时手动切换后不改变设置"
    }
}
