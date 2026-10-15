import Foundation

/// 应用在焦点处于非输入框时的行为策略
public enum NonInputPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    /// 遵循全局默认规则（全局默认：非输入区自动切为英文）
    case followGlobal = "followGlobal"
    
    /// 强制开启：只要失焦或离开输入框，立即切换为英文模式
    case alwaysEnglish = "alwaysEnglish"
    
    /// 豁免保护：非输入区不切换英文，保持当前输入法（适合终端、游戏、快捷键画布类软件）
    case exempt = "exempt"
    
    public var id: String { rawValue }
    
    /// 用户界面展示标签
    public var localizedName: String {
        let isZh = LocalizationManager.shared.currentEffectiveLanguage == .zhHans
        switch self {
        case .followGlobal:
            return isZh ? "跟随全局默认" : "Follow Global"
        case .alwaysEnglish:
            return isZh ? "非输入框切英文" : "Switch to English"
        case .exempt:
            return isZh ? "豁免 (保持当前)" : "Exempt (Keep Current)"
        }
    }
    
    /// 详细说明描述
    public var detailDescription: String {
        let isZh = LocalizationManager.shared.currentEffectiveLanguage == .zhHans
        switch self {
        case .followGlobal:
            return isZh ? "遵循全局配置，非输入框时自动切为英文模式" : "Follow global settings to switch to English in non-input fields"
        case .alwaysEnglish:
            return isZh ? "当前应用在焦点离开输入框时始终自动切换为英文模式" : "Always switch to English when focus is outside text input fields"
        case .exempt:
            return isZh ? "当前应用不执行非输入框切英，避免打断终端或画布操作" : "Do not auto-switch to English for this app, preserving terminal or canvas flow"
        }
    }
}
