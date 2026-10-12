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
        
        // 3. 浏览器场景决策：用户指定不深入网页内部，直接生成 Window 级上下文
        if isBrowserApp {
            return FocusContext(
                bundleID: bundleID,
                appName: appName,
                windowID: windowID,
                windowTitle: windowTitle,
                fieldID: nil,
                fieldDescription: nil,
                role: AppConstants.Accessibility.webAreaRole,
                isSecureField: isSecure,
                isBrowserApp: true
            )
        }
        
        // 4. 原生 App 场景：提取输入框复合指纹
        let role = copyStringAttribute(element: element, attribute: kAXRoleAttribute as CFString)
        let subrole = copyStringAttribute(element: element, attribute: kAXSubroleAttribute as CFString)
        let identifier = copyStringAttribute(element: element, attribute: kAXIdentifierAttribute as CFString)
        let description = copyStringAttribute(element: element, attribute: kAXDescriptionAttribute as CFString)
        let title = copyStringAttribute(element: element, attribute: kAXTitleAttribute as CFString)
        
        // 计算指纹哈希
        let fingerprintSeed = "\(bundleID)|\(windowID)|\(role ?? "")|\(subrole ?? "")|\(identifier ?? "")|\(description ?? "")|\(title ?? "")"
        let fieldID = computeSHA256(for: fingerprintSeed)
        
        // 决定友好展示名称
        let fieldDisplayDesc = identifier ?? description ?? title ?? role ?? AppConstants.Accessibility.unknownFieldIdentifier
        
        return FocusContext(
            bundleID: bundleID,
            appName: appName,
            windowID: windowID,
            windowTitle: windowTitle,
            fieldID: fieldID,
            fieldDescription: fieldDisplayDesc,
            role: role,
            isSecureField: isSecure,
            isBrowserApp: false
        )
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
