import Foundation

/// 记忆与自动切换的粒度控制级别
public enum GranularityLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    /// 仅记住整个 App 的输入法（该应用所有窗口与输入框共用一个输入法）
    case app = "app"
    
    /// 记住该 App 下不同 Window 的输入法（同一窗口内的所有输入框共用，不同窗口独立）
    case window = "window"
    
    /// 深度记住同一窗口下不同 Field（输入框）的输入法
    case field = "field"
    
    public var id: String { rawValue }
    
    /// 用户界面展示标签
    public var localizedName: String {
        switch self {
        case .app:
            return "应用级 (App)"
        case .window:
            return "窗口级 (Window)"
        case .field:
            return "输入框级 (Field)"
        }
    }
    
    /// 详细说明描述
    public var detailDescription: String {
        switch self {
        case .app:
            return "该 App 内所有窗口和输入框统一使用同一个输入法"
        case .window:
            return "按窗口分别记忆，同一窗口内的不同输入框共享"
        case .field:
            return "精细记忆同窗口内的各个输入框，按控件独立切换"
        }
    }
    
    /// SF Symbols 图标名
    public var iconName: String {
        switch self {
        case .app:
            return "app.badge.checkmark"
        case .window:
            return "macwindow"
        case .field:
            return "character.cursor.ibeam"
        }
    }
}
