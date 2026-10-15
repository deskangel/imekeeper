import Foundation

/// 聚焦元素上下文：从底层 Accessibility 树中提取的轻量纯数据实体
public struct FocusContext: Codable, Equatable, Sendable {
    /// 目标应用 Bundle Identifier（如 "com.apple.dt.Xcode"）
    public let bundleID: String
    
    /// 目标应用显示名称（如 "Xcode"）
    public let appName: String
    
    /// 所属窗口唯一指纹标识（如 "Window:MainWindow:2819"）
    public let windowID: String
    
    /// 窗口标题（如 "Project.swift"）
    public let windowTitle: String
    
    /// 输入框唯一指纹标识（若仅在窗口级则为 nil）
    public let fieldID: String?
    
    /// 输入框描述或占位符提示（如 "搜索控制台", "代码编辑区"）
    public let fieldDescription: String?
    
    /// 控件无障碍角色（如 "AXTextField", "AXTextArea"）
    public let role: String?
    
    /// 是否为密码输入框（AXSecureTextField）
    public let isSecureField: Bool
    
    /// 是否为已知 Web 浏览器环境
    public let isBrowserApp: Bool
    
    /// 当前聚焦元素是否为文本输入控件（若为按钮、列表、窗口空白等非输入控件则为 false）
    public let isInputField: Bool
    
    public init(
        bundleID: String,
        appName: String,
        windowID: String,
        windowTitle: String,
        fieldID: String? = nil,
        fieldDescription: String? = nil,
        role: String? = nil,
        isSecureField: Bool = false,
        isBrowserApp: Bool = false,
        isInputField: Bool = true
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.windowID = windowID
        self.windowTitle = windowTitle
        self.fieldID = fieldID
        self.fieldDescription = fieldDescription
        self.role = role
        self.isSecureField = isSecureField
        self.isBrowserApp = isBrowserApp
        self.isInputField = isInputField
    }
}
