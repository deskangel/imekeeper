import Foundation

/// 系统全局常量定义，遵循严禁魔法数字与硬编码规范
public enum AppConstants {

    /// 防抖与时序控制参数
    public enum Timing {
        /// 焦点切换防抖延迟（毫秒）：避免快速拖拽或瞬时失焦引起的频繁切换
        public static let focusDebounceMilliseconds: Int = 35

        /// 程序化切换输入法后的状态抑制窗口（秒）：用于忽略系统自广播的 kTISNotifySelectedKeyboardInputSourceChanged 通知
        public static let antiLoopSuppressionTimeoutSeconds: TimeInterval = 0.45

        /// 用户手动切换输入法后的保护冷静期（秒）：在此窗口期内抑制伴随焦点事件的纠偏与非输入区切英，确保手动操作最高优先级
        public static let manualSwitchGracePeriodSeconds: TimeInterval = 0.45

        /// 轮询或检查权限时的间隔（秒）
        public static let permissionCheckIntervalSeconds: TimeInterval = 1.0
    }

    /// 诊断与调试日志配置
    public enum Logging {
        /// 调试日志输出文件路径
        public static let debugLogFilePath = "/private/tmp/imekeeper.log"

        /// 调试日志开关持久化 Key
        public static let isDebugLoggingEnabledStorageKey = "imekeeper_is_debug_logging_enabled"

        /// 最大单次记录的文本值截断长度（保护隐私与防止日志体积膨胀）
        public static let maxValueSnapshotLength: Int = 64
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

    /// 终端应用 Bundle ID 集合（内置豁免非输入框切英，整视口作为输入环境）
    public enum Terminals {
        public static let knownTerminalBundleIDs: Set<String> = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.mitchellh.ghostty",
            "org.alacritty",
            "com.alacritty",
            "net.kovidgoyal.kitty",
            "com.github.wez.wezterm",
            "dev.warp.Warp-Stable",
            "co.zeit.hyper"
        ]
    }

    /// 纯 GPU 自绘型编辑器应用集合（如 Zed，整视口作为输入环境）
    public enum CanvasEditors {
        public static let knownCanvasEditorBundleIDs: Set<String> = [
            "dev.zed.Zed"
        ]
    }

    /// 常见 IDE 与代码编辑器集合（需要剔除标签页文件名污染，按工作区识别物理窗口）
    public enum IDEs {
        public static let knownIDEBundleIDs: Set<String> = [
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.google.antigravity-ide",
            "com.google.antigravity",
            "com.todesktop.230313mzl4w4u92", // Cursor
            "com.vscodium",
            "com.sublimetext.4",
            "com.jetbrains.intellij",
            "com.jetbrains.pycharm",
            "com.jetbrains.webstorm"
        ]
    }

    /// 浏览器应用 Bundle ID 集合（对于这些应用，默认跟随限制至 Window 级别）
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

        /// 输入框角色与子角色标识
        public static let secureTextFieldRole = "AXSecureTextField"
        public static let textFieldRole = "AXTextField"
        public static let textAreaRole = "AXTextArea"
        public static let searchFieldRole = "AXSearchField"
        public static let comboBoxRole = "AXComboBox"
        public static let contentEditableSubrole = "AXContentEditable"
        public static let webAreaRole = "AXWebArea"
        public static let groupRole = "AXGroup"
        public static let radioButtonRole = "AXRadioButton"
        public static let checkBoxRole = "AXCheckBox"
        public static let popUpButtonRole = "AXPopUpButton"
        public static let menuButtonRole = "AXMenuButton"
        public static let tabRole = "AXTab"
        public static let sliderRole = "AXSlider"
        public static let colorWellRole = "AXColorWell"
        public static let progressIndicatorRole = "AXProgressIndicator"
        public static let levelIndicatorRole = "AXLevelIndicator"
        public static let radioGroupRole = "AXRadioGroup"
        public static let disclosureTriangleRole = "AXDisclosureTriangle"
        public static let splitterRole = "AXSplitter"

        /// WebKit / Chromium 专有无障碍可编辑属性
        public static let editableAttribute = "AXEditable"

        /// 容器类角色集合（默认不是输入框，除非明确携带可编辑标记）
        public static let containerRoles: Set<String> = [
            groupRole,
            webAreaRole
        ]

        /// 明确排除的非输入框角色集合（防止容器、列表、大纲、单选框、按钮等被误判为输入框）
        public static let nonInputRoles: Set<String> = [
            "AXOutline",
            "AXTable",
            "AXList",
            "AXButton",
            radioButtonRole,
            checkBoxRole,
            popUpButtonRole,
            menuButtonRole,
            tabRole,
            sliderRole,
            colorWellRole,
            progressIndicatorRole,
            levelIndicatorRole,
            radioGroupRole,
            disclosureTriangleRole,
            "AXScrollArea",
            "AXScrollBar",
            "AXSplitGroup",
            splitterRole,
            "AXTabGroup",
            "AXToolbar",
            "AXMenuBar",
            "AXMenu",
            "AXMenuItem",
            "AXImage",
            "AXStaticText",
            "AXHeading",
            "AXLink",
            "AXWindow",
            "AXApplication"
        ]

        /// 窗口底层固定编号属性（私有但广泛支持，确保浏览器/文档窗口哈希稳定）
        public static let windowNumberAttribute = "_AXWindowNumber"

        /// 自绘编辑器（如 Zed）的虚拟指纹标识与显示名
        public static let canvasEditorFieldSeed = "CanvasMainEditorArea"
        public static let canvasEditorFieldDescription = "代码编辑区 (Editor)"

        /// 结构指纹向上追溯最大深度（深入识别 Electron/IDE 工作区容器组件）
        public static let maxHierarchyDepth: Int = 16

        /// 针对 Electron / Chromium 及 WebKit 应用强制开启无障碍树的属性
        public static let manualAccessibilityAttribute = "AXManualAccessibility"
        public static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface"

        /// IDE 内置终端归一化指纹标识与显示名
        public static let ideTerminalFieldSeed = "IDECanonicalTerminal"
        public static let ideTerminalFieldDescription = "内置终端 (Terminal)"

        /// 向上查找 AXWindow 节点的最大深度
        public static let maxWindowSearchDepth: Int = 32

        /// 控件标识符与描述文本的最大长度限制
        public static let maxIdentifierLength: Int = 64
        public static let maxDescriptionLength: Int = 48

        /// 未知或默认占位名
        public static let unknownWindowIdentifier = "UnknownWindow"
        public static let unknownFieldIdentifier = "UnknownField"
        public static let defaultWindowPlaceholder = "主窗口"
    }

    /// 默认系统输入法 ID 与常见布局
    public enum InputSource {
        public static let primaryABCSourceID = "com.apple.keylayout.ABC"
        public static let primaryUSSourceID = "com.apple.keylayout.US"
        public static let fallbackAsciiSourceID = "com.apple.keylayout.ABC"
        public static let defaultAsciiSourceID = "com.apple.keylayout.ABC"

        /// 系统官方输入法在系统英文与系统中文环境下的标准系统显示名称映射表
        public static let systemLanguageAlignedNames: [String: (en: String, zh: String)] = [
            primaryUSSourceID: (en: "U.S.", zh: "美国"),
            primaryABCSourceID: (en: "ABC", zh: "ABC"),
            "com.apple.keylayout.USInternational-PC": (en: "U.S. International – PC", zh: "美式国际通用键盘 – PC"),
            "com.apple.keylayout.USExtended": (en: "ABC – Extended", zh: "ABC – 扩展"),
            "com.apple.keylayout.British": (en: "British", zh: "英国"),
            "com.apple.keylayout.British-PC": (en: "British – PC", zh: "英式 – PC"),
            "com.apple.keylayout.Dvorak": (en: "Dvorak", zh: "德沃夏克"),
            "com.apple.keylayout.Dvorak-Left": (en: "Dvorak – Left-Handed", zh: "德沃夏克 – 左手"),
            "com.apple.keylayout.Dvorak-Right": (en: "Dvorak – Right-Handed", zh: "德沃夏克 – 右手"),
            "com.apple.keylayout.Colemak": (en: "Colemak", zh: "科尔马克"),
            "com.apple.keylayout.Australian": (en: "Australian", zh: "澳大利亚"),
            "com.apple.keylayout.Canadian": (en: "Canadian – CSA", zh: "加拿大 – CSA"),
            "com.apple.keylayout.French": (en: "French", zh: "法国"),
            "com.apple.keylayout.German": (en: "German", zh: "德国"),
            "com.apple.keylayout.Spanish": (en: "Spanish", zh: "西班牙"),
            "com.apple.keylayout.Italian": (en: "Italian", zh: "意大利"),
            "com.apple.inputmethod.SCIM.Shuangpin": (en: "Shuangpin – Simplified", zh: "简体双拼"),
            "com.apple.inputmethod.SCIM.ITABC": (en: "Pinyin – Simplified", zh: "简体拼音")
        ]

        /// 解析输入法的系统真实显示名称：严格跟随 macOS 系统全局语言，绝对不受 App 自身语言设置干扰
        public static func resolveNameAlignedWithSystemLanguage(
            sourceID: String,
            defaultName: String,
            simulatedSystemLanguageIsChinese: Bool? = nil
        ) -> String {
            let isSystemChinese: Bool
            if let simulated = simulatedSystemLanguageIsChinese {
                isSystemChinese = simulated
            } else {
                let globalDefaults = UserDefaults(suiteName: ".GlobalPreferences")
                let systemLangs = globalDefaults?.stringArray(forKey: "AppleLanguages")
                let primary = systemLangs?.first?.lowercased() ?? Locale.preferredLanguages.first?.lowercased() ?? "en"
                isSystemChinese = primary.hasPrefix("zh")
            }

            if let pair = systemLanguageAlignedNames[sourceID] {
                return isSystemChinese ? pair.zh : pair.en
            }

            return defaultName
        }
    }

    /// UI 布局与视图尺寸常量
    public enum UI {
        public static let settingsWindowWidth: CGFloat = 1000.0
        public static let settingsWindowHeight: CGFloat = 580.0
        public static let minSettingsWindowWidth: CGFloat = 1000.0
        public static let minSettingsWindowHeight: CGFloat = 460.0

        public static let treeRowHeight: CGFloat = 34.0
        public static let fieldTreeRowHeight: CGFloat = 46.0
        public static let statusItemIconSize: CGFloat = 18.0
        public static let badgeCornerRadius: CGFloat = 4.0
        public static let appRowIconSize: CGFloat = 16.0
        public static let liveStatusAppIconSize: CGFloat = 12.0
        public static let iconThumbnailSize: CGFloat = 32.0
        public static let iconBitmapBitsPerSample: Int = 8
        public static let iconBitmapSamplesPerPixel: Int = 4

        public static let fieldHashDisplayLength: Int = 8
        public static let renameFieldCornerRadius: CGFloat = 3.0
        public static let renameFieldBorderWidth: CGFloat = 1.0

        public static let languagePickerWidth: CGFloat = 130.0
        public static let globalGranularityPickerWidth: CGFloat = 175.0
        public static let rowGranularityPickerWidth: CGFloat = 135.0
        public static let rowNonInputPolicyPickerWidth: CGFloat = 135.0
        public static let rowInputSourcePickerWidth: CGFloat = 150.0
        public static let searchFieldWidth: CGFloat = 150.0
        public static let searchFieldCornerRadius: CGFloat = 6.0
        public static let emptyPlaceholderIconSize: CGFloat = 40.0
        public static let headerIconSize: CGFloat = 20.0
        public static let liveStatusIndicatorSize: CGFloat = 8.0
        public static let footerDividerHeight: CGFloat = 14.0
        public static let footerSpacing: CGFloat = 16.0

        public static let rowSelectionCornerRadius: CGFloat = 6.0
        public static let rowSelectionIndicatorWidth: CGFloat = 3.0
        public static let rowSelectionIndicatorHeight: CGFloat = 16.0
        public static let rowSelectionIndicatorCornerRadius: CGFloat = 1.5
        public static let rowSelectionBackgroundOpacity: Double = 0.12
        public static let autoScrollAnimationDuration: Double = 0.25
        public static let autoScrollDelay: TimeInterval = 0.05

        // 行内轻量级下拉菜单与排版常量
        public static let menuControlHeight: CGFloat = 22.0
        public static let menuCornerRadius: CGFloat = 5.0
        public static let menuBorderLineWidth: CGFloat = 0.5
        public static let menuBorderOpacity: Double = 0.2
        public static let menuFontSize: CGFloat = 11.0
        public static let menuChevronFontSize: CGFloat = 8.0
        public static let menuHorizontalPadding: CGFloat = 6.0
        public static let menuVerticalPadding: CGFloat = 3.0
        public static let menuContentSpacing: CGFloat = 4.0
        public static let menuSpacerMinLength: CGFloat = 2.0
        public static let actionButtonSize: CGFloat = 26.0
        public static let actionButtonCornerRadius: CGFloat = 5.0
        public static let actionButtonFontSize: CGFloat = 13.0
        public static let deleteButtonFontSize: CGFloat = 13.0
        public static let cleanButtonFontSize: CGFloat = 13.0
        public static let cleanButtonIconName: String = "eraser"
        public static let disabledCleanButtonOpacity: Double = 0.35
        public static let actionButtonHoverBackgroundOpacity: Double = 0.12
        public static let actionButtonActiveBackgroundOpacity: Double = 0.08
        public static let cleanButtonHoverBackgroundOpacity: Double = 0.18
        public static let deleteButtonHoverBackgroundOpacity: Double = 0.18
        public static let selectedRowButtonHoverBackgroundOpacity: Double = 0.22
        public static let lockButtonActiveOpacity: Double = 0.14
        public static let lockButtonHoverOpacity: Double = 0.24
        public static let lockButtonInheritedOpacity: Double = 0.10
        public static let deleteButtonNormalOpacity: Double = 0.75
        public static let cleanButtonNormalOpacity: Double = 0.85
        public static let unlockedButtonNormalOpacity: Double = 0.75
        public static let rowTitleFontSize: CGFloat = 13.0
        public static let rowSubtitleFontSize: CGFloat = 10.0
        public static let rowHashFontSize: CGFloat = 9.5
        public static let rowContentSpacing: CGFloat = 8.0
        public static let rowTextSpacing: CGFloat = 1.0
        public static let rowHorizontalPadding: CGFloat = 4.0
    }

    /// 系统服务与开机自启常量
    public enum AutoStart {
        public static let subsystem = "com.antigravity.imekeeper"
        public static let category = "AutoStartManager"
    }

    /// 锁定状态与徽标 UI 常量
    public enum LockUI {
        public static let appLockBadgeText = "应用锁定"
        public static let fieldLockBadgeText = "输入框锁定"
        public static let inheritedLockBadgeTextPrefix = "继承"
        public static let lockActionText = "锁定"
        public static let unlockedActionText = "未锁定"

        public static let lockedIconName = "lock.fill"
        public static let unlockedIconName = "lock.open"
        public static let lockShieldIconName = "lock.shield.fill"

        public static let lockIconSize: CGFloat = 13.0
        public static let lockTextSize: CGFloat = 10.0
        public static let badgePaddingHorizontal: CGFloat = 6.0
        public static let badgePaddingVertical: CGFloat = 3.0
        public static let lockButtonWidth: CGFloat = 26.0

        public static let appLockHelpText = "应用级锁定：此应用下的输入法已被固定，临时手动切换后不会更新设置"
        public static let fieldLockHelpText = "输入框级锁定：此输入框下的输入法已被固定，临时手动切换后不会更新设置"
        public static let inheritedLockHelpText = "受上级锁定保护：临时手动切换后不会更新设置"
        public static let unlockedHelpText = "点击锁定此层级输入法，临时手动切换后不改变设置"
    }
}
