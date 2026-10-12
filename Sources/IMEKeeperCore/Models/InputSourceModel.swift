import Foundation

/// 键盘输入法模型实体
public struct InputSourceModel: Codable, Identifiable, Hashable, Sendable {
    /// 输入法唯一标识符（如: "com.apple.keylayout.ABC", "com.apple.inputmethod.SCIM.ITABC"）
    public let id: String
    
    /// 本地化友好显示名称（如: "ABC", "简体拼音", "搜狗输入法"）
    public let localizedName: String
    
    /// 是否为 ASCII / 英文输入源
    public let isAsciiCapable: Bool
    
    /// 是否为当前处于激活状态的输入法
    public var isCurrent: Bool
    
    public init(
        id: String,
        localizedName: String,
        isAsciiCapable: Bool = false,
        isCurrent: Bool = false
    ) {
        self.id = id
        self.localizedName = localizedName
        self.isAsciiCapable = isAsciiCapable
        self.isCurrent = isCurrent
    }
    
    /// 默认未知占位输入法
    public static func unknown(id: String) -> InputSourceModel {
        InputSourceModel(
            id: id,
            localizedName: id.components(separatedBy: ".").last ?? id,
            isAsciiCapable: false,
            isCurrent: false
        )
    }
}
