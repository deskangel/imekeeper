import Foundation

/// 输入框级别记忆实体
public struct FieldProfile: Codable, Identifiable, Hashable, Sendable {
    /// 唯一控件指纹哈希
    public let id: String
    
    /// 控件无障碍标识或名称
    public var fieldIdentifier: String
    
    /// 控件的角色类型（如 AXTextField, AXTextArea）
    public var role: String
    
    /// 记忆绑定的输入法 ID
    public var sourceID: String
    
    /// 是否锁定输入法（锁定后临时切换不更新设置）
    public var isLocked: Bool
    
    /// 最后更新时间
    public var lastUpdated: Date
    
    public init(
        id: String,
        fieldIdentifier: String,
        role: String,
        sourceID: String,
        isLocked: Bool = false,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.fieldIdentifier = fieldIdentifier
        self.role = role
        self.sourceID = sourceID
        self.isLocked = isLocked
        self.lastUpdated = lastUpdated
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, fieldIdentifier, role, sourceID, isLocked, lastUpdated
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.fieldIdentifier = try container.decode(String.self, forKey: .fieldIdentifier)
        self.role = try container.decode(String.self, forKey: .role)
        self.sourceID = try container.decode(String.self, forKey: .sourceID)
        self.isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        self.lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date()
    }
}

/// 窗口级别记忆实体
public struct WindowProfile: Codable, Identifiable, Hashable, Sendable {
    /// 窗口唯一标识指纹
    public let id: String
    
    /// 窗口标题
    public var windowTitle: String
    
    /// 该窗口最后使用的输入法 ID（作为新建输入框的默认继承基准）
    public var lastSourceID: String
    
    /// 该窗口内记录的各输入框字典（key 为 fieldID）
    public var fields: [String: FieldProfile]
    
    /// 是否锁定输入法（锁定后该窗口临时切换不更新设置）
    public var isLocked: Bool
    
    /// 最后更新时间
    public var lastUpdated: Date
    
    public init(
        id: String,
        windowTitle: String,
        lastSourceID: String,
        fields: [String: FieldProfile] = [:],
        isLocked: Bool = false,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.windowTitle = windowTitle
        self.lastSourceID = lastSourceID
        self.fields = fields
        self.isLocked = isLocked
        self.lastUpdated = lastUpdated
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, windowTitle, lastSourceID, fields, isLocked, lastUpdated
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.windowTitle = try container.decode(String.self, forKey: .windowTitle)
        self.lastSourceID = try container.decode(String.self, forKey: .lastSourceID)
        self.fields = try container.decodeIfPresent([String: FieldProfile].self, forKey: .fields) ?? [:]
        self.isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        self.lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date()
    }
}

/// 应用级别记忆实体
public struct AppProfile: Codable, Identifiable, Hashable, Sendable {
    /// 应用程序 Bundle Identifier (如 "com.apple.dt.Xcode")
    public let id: String
    
    /// 应用程序名称 (如 "Xcode")
    public var appName: String
    
    /// 用户为该应用指定的生效追踪粒度（未单独设置时继承全局默认值）
    public var configuredGranularity: GranularityLevel?
    
    /// 该应用最后使用的输入法 ID
    public var lastSourceID: String
    
    /// 该应用内记录的窗口字典（key 为 windowID）
    public var windows: [String: WindowProfile]
    
    /// 是否锁定输入法（锁定后该应用内所有窗口和输入框临时切换均不更新设置）
    public var isLocked: Bool
    
    /// 最后更新时间
    public var lastUpdated: Date
    
    public init(
        id: String,
        appName: String,
        configuredGranularity: GranularityLevel? = nil,
        lastSourceID: String,
        windows: [String: WindowProfile] = [:],
        isLocked: Bool = false,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.appName = appName
        self.configuredGranularity = configuredGranularity
        self.lastSourceID = lastSourceID
        self.windows = windows
        self.isLocked = isLocked
        self.lastUpdated = lastUpdated
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, appName, configuredGranularity, lastSourceID, windows, isLocked, lastUpdated
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.appName = try container.decode(String.self, forKey: .appName)
        self.configuredGranularity = try container.decodeIfPresent(GranularityLevel.self, forKey: .configuredGranularity)
        self.lastSourceID = try container.decode(String.self, forKey: .lastSourceID)
        self.windows = try container.decodeIfPresent([String: WindowProfile].self, forKey: .windows) ?? [:]
        self.isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        self.lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date()
    }
}

/// 用于在 SwiftUI 设置界面树状列表中展示的通用层级项节点
public struct HierarchyItem: Identifiable, Hashable, Sendable {
    public enum ItemType: Hashable, Sendable {
        case app(bundleID: String, granularity: GranularityLevel, nonInputPolicy: NonInputPolicy)
        case window(bundleID: String, windowID: String)
        case field(bundleID: String, windowID: String, fieldID: String)
    }
    
    /// 区分三个不同层次的锁定状态与继承保护
    public enum LockStatus: Hashable, Sendable {
        case unlocked
        case locked(level: GranularityLevel)
        case inherited(from: GranularityLevel)
        
        public var isProtected: Bool {
            switch self {
            case .unlocked:
                return false
            case .locked, .inherited:
                return true
            }
        }
    }
    
    public let id: String
    public let title: String
    public let subtitle: String?
    public let itemType: ItemType
    public var currentSourceID: String
    public var isLocked: Bool
    public var lockStatus: LockStatus
    public var children: [HierarchyItem]?
    
    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        itemType: ItemType,
        currentSourceID: String,
        isLocked: Bool = false,
        lockStatus: LockStatus = .unlocked,
        children: [HierarchyItem]? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.itemType = itemType
        self.currentSourceID = currentSourceID
        self.isLocked = isLocked
        self.lockStatus = lockStatus
        self.children = children
    }
}
