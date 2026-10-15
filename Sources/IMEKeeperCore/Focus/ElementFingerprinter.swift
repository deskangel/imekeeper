import Foundation
import AppKit
import ApplicationServices
import CryptoKit

/// 控件多维复合指纹与上下文解析器
public struct ElementFingerprinter: Sendable {
    
    public init() {}
    
    /// 从获取焦点的 AXUIElement 中提取纯数据 FocusContext
    /// - Parameters:
    ///   - element: 当前聚焦元素
    ///   - runningApp: 当前前台运行的应用
    ///   - isBrowserApp: 是否为浏览器
    /// - Returns: 解析出的焦点上下文
    public func resolveFocusContext(
        from element: AXUIElement,
        runningApp: NSRunningApplication,
        isBrowserApp: Bool
    ) -> FocusContext {
        let bundleID = runningApp.bundleIdentifier ?? "unknown.bundle"
        let appName = runningApp.localizedName ?? bundleID
        
        // 1. 提取所属窗口上下文
        let (windowID, windowTitle) = extractWindowInfo(from: element)
        
        // 2. 检查密码输入框 (Secure TextField)
        let isSecure = checkIsSecureField(element: element)
        
        // 3. 提取控件基础无障碍属性
        let role = copyStringAttribute(element: element, attribute: kAXRoleAttribute as CFString)
        let subrole = copyStringAttribute(element: element, attribute: kAXSubroleAttribute as CFString)
        let identifier = copyStringAttribute(element: element, attribute: kAXIdentifierAttribute as CFString)
        let description = copyStringAttribute(element: element, attribute: kAXDescriptionAttribute as CFString)
        
        // 4. 判定当前焦点是否处于可编辑输入框中
        let isInput = determineIfInputField(element: element, role: role, subrole: subrole)
        
        // 5. 浏览器场景决策：用户指定不深入网页内部，保留 Window 级，但在 isInputField 标明真实状态
        if isBrowserApp {
            return FocusContext(
                bundleID: bundleID,
                appName: appName,
                windowID: windowID,
                windowTitle: windowTitle,
                fieldID: nil,
                fieldDescription: nil,
                role: role ?? AppConstants.Accessibility.webAreaRole,
                isSecureField: isSecure,
                isBrowserApp: true,
                isInputField: isInput
            )
        }
        
        // 6. 原生 App 场景：提取输入框结构路径骨架（FINGERPRINT-V2）
        let structuralPath = extractStructuralPath(from: element)
        
        // 计算稳定的指纹哈希（彻底剥离易变的文档/工程动态标题污染）
        let fingerprintSeed = "\(bundleID)|\(structuralPath)|\(role ?? "")|\(subrole ?? "")|\(identifier ?? "")"
        let fieldID = computeSHA256(for: fingerprintSeed)
        
        // 决定友好展示名称（优先语义描述，避免将打开的临时文件当成输入框名）
        let fieldDisplayDesc = determineFieldDisplayName(
            identifier: identifier,
            description: description,
            role: role,
            subrole: subrole
        )
        
        return FocusContext(
            bundleID: bundleID,
            appName: appName,
            windowID: windowID,
            windowTitle: windowTitle,
            fieldID: fieldID,
            fieldDescription: fieldDisplayDesc,
            role: role,
            isSecureField: isSecure,
            isBrowserApp: false,
            isInputField: isInput
        )
    }
    
    // MARK: - Input Field Determination
    
    /// 判定目标无障碍元素是否具备文本输入能力
    public func determineIfInputField(element: AXUIElement, role: String?, subrole: String?) -> Bool {
        // 1. 明确的输入框角色白名单
        let inputRoles: Set<String> = [
            AppConstants.Accessibility.textFieldRole,
            AppConstants.Accessibility.textAreaRole,
            AppConstants.Accessibility.searchFieldRole,
            AppConstants.Accessibility.comboBoxRole,
            AppConstants.Accessibility.secureTextFieldRole
        ]
        if let role = role, inputRoles.contains(role) {
            return true
        }
        
        // 2. 明确的子角色白名单（例如富文本可编辑区、密码框）
        if let subrole = subrole {
            if subrole == AppConstants.Accessibility.contentEditableSubrole ||
               subrole == AppConstants.Accessibility.secureTextFieldRole {
                return true
            }
        }
        
        // 3. 动态属性能力探测：检查 kAXValueAttribute 是否可写入
        var isSettable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &isSettable) == .success,
           isSettable.boolValue {
            return true
        }
        
        // 4. 检查是否暴露了文本选区范围属性（仅光标编辑型控件响应）
        var selectedRangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef) == .success {
            return true
        }
        
        return false
    }
    
    // MARK: - Structural Path & Friendly Display
    
    private func extractStructuralPath(
        from element: AXUIElement,
        maxDepth: Int = AppConstants.Accessibility.maxHierarchyDepth
    ) -> String {
        var pathComponents: [String] = []
        var current: AXUIElement = element
        
        for _ in 0..<maxDepth {
            guard let role = copyStringAttribute(element: current, attribute: kAXRoleAttribute as CFString) else {
                break
            }
            if role == (kAXWindowRole as String) || role == (kAXApplicationRole as String) {
                pathComponents.append(role)
                break
            }
            
            let identifier = copyStringAttribute(element: current, attribute: kAXIdentifierAttribute as CFString)
            if let id = identifier, !id.isEmpty, id.count <= 64, !id.contains("/") {
                pathComponents.append("\(role)#\(id)")
            } else {
                pathComponents.append(role)
            }
            
            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
               let parent = parentRef {
                current = (parent as! AXUIElement)
            } else {
                break
            }
        }
        
        return pathComponents.reversed().joined(separator: "/")
    }
    
    private func determineFieldDisplayName(
        identifier: String?,
        description: String?,
        role: String?,
        subrole: String?
    ) -> String {
        if let identifier = identifier, !identifier.isEmpty, identifier.count <= 64 {
            return identifier
        }
        if let description = description, !description.isEmpty, description.count <= 48, !description.contains("\n") {
            return description
        }
        if let subrole = subrole, subrole == AppConstants.Accessibility.secureTextFieldRole {
            return "密码输入框 (AXSecureTextField)"
        }
        if let role = role {
            switch role {
            case AppConstants.Accessibility.textFieldRole:
                return "单行文本框 (AXTextField)"
            case AppConstants.Accessibility.textAreaRole:
                return "多行文本区 (AXTextArea)"
            case AppConstants.Accessibility.searchFieldRole:
                return "搜索输入框 (AXSearchField)"
            case AppConstants.Accessibility.comboBoxRole:
                return "下拉组合框 (AXComboBox)"
            default:
                return role
            }
        }
        return AppConstants.Accessibility.unknownFieldIdentifier
    }
    
    // MARK: - Private Attribute Extractors
    
    private func extractWindowInfo(from element: AXUIElement) -> (windowID: String, windowTitle: String) {
        var current: AXUIElement = element
        
        // 向上查找 AXWindow 节点
        for _ in 0..<8 {
            if let role = copyStringAttribute(element: current, attribute: kAXRoleAttribute as CFString),
               role == kAXWindowRole as String {
                let title = copyStringAttribute(element: current, attribute: kAXTitleAttribute as CFString) ?? AppConstants.Accessibility.defaultWindowPlaceholder
                let identifier = copyStringAttribute(element: current, attribute: kAXIdentifierAttribute as CFString) ?? ""
                let winID = computeSHA256(for: "\(title)|\(identifier)")
                return (winID, title)
            }
            
            var parentRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef)
            if result == .success, let parent = parentRef {
                current = (parent as! AXUIElement)
            } else {
                break
            }
        }
        
        // 尝试直接获取 kAXWindowAttribute
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowRef) == .success,
           let win = windowRef {
            let winElement = (win as! AXUIElement)
            let title = copyStringAttribute(element: winElement, attribute: kAXTitleAttribute as CFString) ?? AppConstants.Accessibility.defaultWindowPlaceholder
            let winID = computeSHA256(for: title)
            return (winID, title)
        }
        
        return (AppConstants.Accessibility.unknownWindowIdentifier, AppConstants.Accessibility.defaultWindowPlaceholder)
    }
    
    private func checkIsSecureField(element: AXUIElement) -> Bool {
        let role = copyStringAttribute(element: element, attribute: kAXRoleAttribute as CFString)
        let subrole = copyStringAttribute(element: element, attribute: kAXSubroleAttribute as CFString)
        return role == AppConstants.Accessibility.secureTextFieldRole || subrole == AppConstants.Accessibility.secureTextFieldRole
    }
    
    private func copyStringAttribute(element: AXUIElement, attribute: CFString) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &valueRef) == .success,
              let value = valueRef as? String else {
            return nil
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func computeSHA256(for string: String) -> String {
        let inputData = Data(string.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
