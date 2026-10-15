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
        let (windowID, windowTitle) = extractWindowInfo(from: element, bundleID: bundleID)
        
        // 2. 检查密码输入框 (Secure TextField)
        let isSecure = checkIsSecureField(element: element)
        
        // 3. 提取控件基础无障碍属性
        let role = copyStringAttribute(element: element, attribute: kAXRoleAttribute as CFString)
        let subrole = copyStringAttribute(element: element, attribute: kAXSubroleAttribute as CFString)
        let identifier = copyStringAttribute(element: element, attribute: kAXIdentifierAttribute as CFString)
        let description = copyStringAttribute(element: element, attribute: kAXDescriptionAttribute as CFString)
        let title = copyStringAttribute(element: element, attribute: kAXTitleAttribute as CFString)
        
        // 4. 特殊自绘型编辑器（如 Zed）：整视口视为输入区域
        let isCanvasEditor = AppConstants.CanvasEditors.knownCanvasEditorBundleIDs.contains(bundleID)
        
        // 5. 判定当前焦点是否处于可编辑输入框中
        let isInput: Bool
        if isCanvasEditor {
            isInput = true
        } else {
            isInput = determineIfInputField(element: element, role: role, subrole: subrole)
        }
        
        // 6. Zed 等自绘编辑器：生成稳定且友好的虚拟编辑区指纹
        if isCanvasEditor {
            let fieldSeed = "\(bundleID)|\(AppConstants.Accessibility.canvasEditorFieldSeed)"
            let fieldID = computeSHA256(for: fieldSeed)
            return FocusContext(
                bundleID: bundleID,
                appName: appName,
                windowID: windowID,
                windowTitle: windowTitle,
                fieldID: fieldID,
                fieldDescription: AppConstants.Accessibility.canvasEditorFieldDescription,
                role: AppConstants.Accessibility.textAreaRole,
                isSecureField: false,
                isBrowserApp: false,
                isInputField: true
            )
        }
        
        // 7. 提取输入框结构路径骨架（FINGERPRINT-V2）
        let structuralPath = extractStructuralPath(from: element)
        
        // 过滤易变的临时标题（如打开的文件名、动态网页名等），确保相同组件哈希恒定
        let isIDE = AppConstants.IDEs.knownIDEBundleIDs.contains(bundleID)
        let normalizedDesc: String
        if isIDE {
            // IDE 中的编辑区或文本区，剥离可能包含当前文件名（含 .）的 description
            if let desc = description, !desc.contains(".") && !desc.contains("/") {
                normalizedDesc = desc
            } else {
                normalizedDesc = ""
            }
        } else {
            normalizedDesc = description ?? ""
        }
        
        // 计算稳定的指纹哈希（混合结构路径、角色、标识与稳定描述）
        let fingerprintSeed = "\(bundleID)|\(structuralPath)|\(role ?? "")|\(subrole ?? "")|\(identifier ?? "")|\(normalizedDesc)"
        let fieldID = isInput ? computeSHA256(for: fingerprintSeed) : nil
        
        // 决定友好展示名称（优先语义描述，识别 IDE 编辑器、对话框、搜索栏等）
        let fieldDisplayDesc = isInput ? determineFieldDisplayName(
            identifier: identifier,
            description: description,
            title: title,
            structuralPath: structuralPath,
            role: role,
            subrole: subrole
        ) : nil
        
        return FocusContext(
            bundleID: bundleID,
            appName: appName,
            windowID: windowID,
            windowTitle: windowTitle,
            fieldID: fieldID,
            fieldDescription: fieldDisplayDesc,
            role: role ?? (isBrowserApp ? AppConstants.Accessibility.webAreaRole : nil),
            isSecureField: isSecure,
            isBrowserApp: isBrowserApp,
            isInputField: isInput
        )
    }
    
    // MARK: - Input Field Determination
    
    /// 判定目标无障碍元素是否具备文本输入能力
    public func determineIfInputField(element: AXUIElement, role: String?, subrole: String?) -> Bool {
        // 0. 明确的非输入框角色黑名单（优先排除单选框、按钮、复选框、大纲、列表、表格等）
        if let role = role, AppConstants.Accessibility.nonInputRoles.contains(role) {
            return false
        }
        
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
        
        // 2. 明确的子角色白名单（例如富文本可编辑区、密码框、及子角色标明为输入框者）
        if let subrole = subrole {
            if subrole == AppConstants.Accessibility.contentEditableSubrole ||
               subrole == AppConstants.Accessibility.secureTextFieldRole ||
               inputRoles.contains(subrole) {
                return true
            }
        }
        
        // 3. WebKit / Chromium 专有可编辑属性检查 (如 contenteditable 元素)
        var editableRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, AppConstants.Accessibility.editableAttribute as CFString, &editableRef) == .success,
           let isEditable = editableRef as? Bool, isEditable {
            return true
        }
        
        // 4. 对于容器类角色（AXGroup, AXWebArea 等），在没有明确可编辑标记的情况下，坚决判定为非输入框
        // 避免因后方的只读通用选区或行号属性导致误判
        if let role = role, AppConstants.Accessibility.containerRoles.contains(role) {
            return false
        }
        
        // 5. 检查文本值是否允许被外部设置（可写性 Settable 检测）
        var isValueSettable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &isValueSettable) == .success,
           isValueSettable.boolValue {
            return true
        }
        
        // 6. 检查选中文本是否允许被外部替换（富文本编辑器关键特征）
        var isSelectedTextSettable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &isSelectedTextSettable) == .success,
           isSelectedTextSettable.boolValue {
            return true
        }
        
        // 7. 检查是否暴露了光标行号属性（代码编辑器与复杂文本框的关键特性）
        var insertionPointRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXInsertionPointLineNumberAttribute as CFString, &insertionPointRef) == .success {
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
            if let id = identifier, !id.isEmpty, id.count <= AppConstants.Accessibility.maxIdentifierLength, !id.contains("/") {
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
        title: String?,
        structuralPath: String,
        role: String?,
        subrole: String?
    ) -> String {
        // 1. 结构路径语义匹配（针对 VS Code / Antigravity 等 Electron IDE）
        let lowerPath = structuralPath.lowercased()
        if lowerPath.contains("parts.editor") {
            return "代码编辑区 (Editor)"
        }
        if lowerPath.contains("chat") || lowerPath.contains("auxiliarybar") {
            return "AI 对话输入 (Chat)"
        }
        if lowerPath.contains("terminal") {
            return "内置终端 (Terminal)"
        }
        if lowerPath.contains("find") {
            return "查找与替换 (Find)"
        }
        
        // 2. 显式 identifier 语义识别
        if let identifier = identifier, !identifier.isEmpty, identifier.count <= AppConstants.Accessibility.maxIdentifierLength {
            return identifier
        }
        
        // 3. description / title 识别
        if let description = description, !description.isEmpty, description.count <= AppConstants.Accessibility.maxDescriptionLength, !description.contains("\n") {
            return description
        }
        if let title = title, !title.isEmpty, title.count <= AppConstants.Accessibility.maxDescriptionLength, !title.contains("\n") {
            return title
        }
        
        // 4. 角色与子角色
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
    
    private func extractWindowInfo(from element: AXUIElement, bundleID: String? = nil) -> (windowID: String, windowTitle: String) {
        var current: AXUIElement = element
        
        // 向上深度查找 AXWindow 节点，穿透深层 DOM/SwiftUI/Electron 控件层级
        for _ in 0..<AppConstants.Accessibility.maxWindowSearchDepth {
            if let role = copyStringAttribute(element: current, attribute: kAXRoleAttribute as CFString),
               role == kAXWindowRole as String {
                let rawTitle = copyStringAttribute(element: current, attribute: kAXTitleAttribute as CFString) ?? AppConstants.Accessibility.defaultWindowPlaceholder
                let identifier = copyStringAttribute(element: current, attribute: kAXIdentifierAttribute as CFString) ?? ""
                
                // 优先读取 _AXWindowNumber 获得稳定的窗口系统级唯一标识
                var winNumberRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(current, AppConstants.Accessibility.windowNumberAttribute as CFString, &winNumberRef) == .success,
                   let winNumber = winNumberRef {
                    let winID = computeSHA256(for: "win_num_\(winNumber)")
                    return (winID, rawTitle)
                }
                
                // IDE 类应用特殊处理：提取持久稳定的工作区/项目名，剥离打开的文件名与 tab 污染
                if let bundle = bundleID, AppConstants.IDEs.knownIDEBundleIDs.contains(bundle) {
                    let workspaceName = extractWorkspaceName(from: rawTitle)
                    let winID = computeSHA256(for: "\(bundle)|workspace:\(workspaceName)")
                    return (winID, workspaceName)
                }
                
                let winID = computeSHA256(for: "\(rawTitle)|\(identifier)")
                return (winID, rawTitle)
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
            let rawTitle = copyStringAttribute(element: winElement, attribute: kAXTitleAttribute as CFString) ?? AppConstants.Accessibility.defaultWindowPlaceholder
            
            var winNumberRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(winElement, AppConstants.Accessibility.windowNumberAttribute as CFString, &winNumberRef) == .success,
               let winNumber = winNumberRef {
                let winID = computeSHA256(for: "win_num_\(winNumber)")
                return (winID, rawTitle)
            }
            
            if let bundle = bundleID, AppConstants.IDEs.knownIDEBundleIDs.contains(bundle) {
                let workspaceName = extractWorkspaceName(from: rawTitle)
                let winID = computeSHA256(for: "\(bundle)|workspace:\(workspaceName)")
                return (winID, workspaceName)
            }
            
            let winID = computeSHA256(for: rawTitle)
            return (winID, rawTitle)
        }
        
        return (AppConstants.Accessibility.unknownWindowIdentifier, AppConstants.Accessibility.defaultWindowPlaceholder)
    }
    
    /// 从多标签页 IDE 的窗口标题中提取持久的工作区/项目名（剔除当前编辑的单个文件和路径）
    private func extractWorkspaceName(from windowTitle: String) -> String {
        let trimmed = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == AppConstants.Accessibility.defaultWindowPlaceholder {
            return AppConstants.Accessibility.defaultWindowPlaceholder
        }
        
        // 匹配常见 IDE 标题分割符：
        // 模式 A: "roguexian — enemy_bosses.dart" (项目名 — 文件名)
        // 模式 B: "enemy_bosses.dart — roguexian" (文件名 — 项目名)
        // 模式 C: "Main.swift - MyProject"
        let separators = [" — ", " - ", " – "]
        for sep in separators {
            if trimmed.contains(sep) {
                let parts = trimmed.components(separatedBy: sep).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if parts.count >= 2 {
                    // 通常后缀或前缀中不包含文件扩展名（.dart, .swift, .ts 等）的一侧为工作区/工程名
                    let first = parts[0]
                    let last = parts[parts.count - 1]
                    let firstHasExt = first.contains(".")
                    let lastHasExt = last.contains(".")
                    
                    if !firstHasExt && lastHasExt {
                        return first // "roguexian — enemy_bosses.dart" -> "roguexian"
                    } else if firstHasExt && !lastHasExt {
                        return last  // "enemy_bosses.dart — roguexian" -> "roguexian"
                    } else {
                        // 若都无扩展名或都有，优先取首部作为工作区
                        return first
                    }
                }
            }
        }
        
        return trimmed
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
