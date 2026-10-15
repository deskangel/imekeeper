import Foundation

/// 记忆与自动切换的粒度控制级别
public enum GranularityLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    /// 仅记住整个 App 的输入法（该应用所有输入框共用一个输入法）
    case app = "app"
    
    /// 深度记住应用内不同 Field（输入框）的输入法
    case field = "field"
    
    public var id: String { rawValue }
    
    /// 用户界面展示标签
    public var localizedName: String {
        L10n.granularityName(for: self)
    }
    
    /// 详细说明描述
    public var detailDescription: String {
        L10n.granularityDetail(for: self)
    }
    
    /// SF Symbols 图标名
    public var iconName: String {
        switch self {
        case .app:
            return "app.badge.checkmark"
        case .field:
            return "character.cursor.ibeam"
        }
    }
}
