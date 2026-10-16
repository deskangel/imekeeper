import Foundation
import ApplicationServices

/// 控件无障碍属性快照结构体
public struct ElementAttributeSnapshot: Sendable {
    public let role: String?
    public let subrole: String?
    public let roleDescription: String?
    public let title: String?
    public let descriptionText: String?
    public let identifier: String?
    public let isFocused: Bool?
    public let isEditable: Bool?
    public let selectedTextRange: CFRange?
    public let insertionPointLineNumber: Int?
    public let valuePreview: String?
    public let parentRole: String?
    
    public init(
        role: String? = nil,
        subrole: String? = nil,
        roleDescription: String? = nil,
        title: String? = nil,
        descriptionText: String? = nil,
        identifier: String? = nil,
        isFocused: Bool? = nil,
        isEditable: Bool? = nil,
        selectedTextRange: CFRange? = nil,
        insertionPointLineNumber: Int? = nil,
        valuePreview: String? = nil,
        parentRole: String? = nil
    ) {
        self.role = role
        self.subrole = subrole
        self.roleDescription = roleDescription
        self.title = title
        self.descriptionText = descriptionText
        self.identifier = identifier
        self.isFocused = isFocused
        self.isEditable = isEditable
        self.selectedTextRange = selectedTextRange
        self.insertionPointLineNumber = insertionPointLineNumber
        self.valuePreview = valuePreview
        self.parentRole = parentRole
    }
    
    /// 从 AXUIElement 现场提取完整快照
    public static func capture(from element: AXUIElement) -> ElementAttributeSnapshot {
        let role = copyString(element: element, attribute: kAXRoleAttribute as CFString)
        let subrole = copyString(element: element, attribute: kAXSubroleAttribute as CFString)
        let roleDesc = copyString(element: element, attribute: kAXRoleDescriptionAttribute as CFString)
        let title = copyString(element: element, attribute: kAXTitleAttribute as CFString)
        let descriptionText = copyString(element: element, attribute: kAXDescriptionAttribute as CFString)
        let identifier = copyString(element: element, attribute: kAXIdentifierAttribute as CFString)
        
        var isFocused: Bool?
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &focusedRef) == .success,
           let val = focusedRef as? Bool {
            isFocused = val
        }
        
        var isEditable: Bool?
        var editableRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, AppConstants.Accessibility.editableAttribute as CFString, &editableRef) == .success,
           let val = editableRef as? Bool {
            isEditable = val
        }
        
        var selectedRange: CFRange?
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeValue = rangeRef {
            var range = CFRange(location: 0, length: 0)
            if CFGetTypeID(rangeValue) == AXValueGetTypeID() {
                let axVal = rangeValue as! AXValue
                if AXValueGetType(axVal) == .cfRange {
                    AXValueGetValue(axVal, .cfRange, &range)
                    selectedRange = range
                }
            }
        }
        
        var lineNum: Int?
        var lineRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXInsertionPointLineNumberAttribute as CFString, &lineRef) == .success,
           let num = lineRef as? Int {
            lineNum = num
        }
        
        var valuePreview: String?
        if let rawVal = copyString(element: element, attribute: kAXValueAttribute as CFString) {
            let maxLen = AppConstants.Logging.maxValueSnapshotLength
            if rawVal.count > maxLen {
                valuePreview = "\(rawVal.prefix(maxLen))... [len=\(rawVal.count)]"
            } else {
                valuePreview = rawVal
            }
        }
        
        var parentRole: String?
        var parentRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success,
           let parent = parentRef {
            parentRole = copyString(element: (parent as! AXUIElement), attribute: kAXRoleAttribute as CFString)
        }
        
        return ElementAttributeSnapshot(
            role: role,
            subrole: subrole,
            roleDescription: roleDesc,
            title: title,
            descriptionText: descriptionText,
            identifier: identifier,
            isFocused: isFocused,
            isEditable: isEditable,
            selectedTextRange: selectedRange,
            insertionPointLineNumber: lineNum,
            valuePreview: valuePreview,
            parentRole: parentRole
        )
    }
    
    private static func copyString(element: AXUIElement, attribute: CFString) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &valueRef) == .success,
              let value = valueRef as? String else {
            return nil
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 集中式焦点诊断与文件日志管理器
public final class DebugLogger: @unchecked Sendable {
    public static let shared = DebugLogger()
    
    private let lock = NSLock()
    private let userDefaults: UserDefaults
    private let logFilePath: String
    private let dateFormatter: DateFormatter
    
    public init(
        userDefaults: UserDefaults = .standard,
        logFilePath: String = AppConstants.Logging.debugLogFilePath
    ) {
        self.userDefaults = userDefaults
        self.logFilePath = logFilePath
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }
    
    /// 日志开关是否处于启用状态
    public var isEnabled: Bool {
        get {
            userDefaults.bool(forKey: AppConstants.Logging.isDebugLoggingEnabledStorageKey)
        }
        set {
            userDefaults.set(newValue, forKey: AppConstants.Logging.isDebugLoggingEnabledStorageKey)
        }
    }
    
    /// 记录单次焦点流转与控件属性快照
    public func logFocusEvent(
        context: FocusContext,
        snapshot: ElementAttributeSnapshot? = nil,
        actionDescription: String? = nil
    ) {
        guard isEnabled else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        let timestamp = dateFormatter.string(from: Date())
        var lines: [String] = []
        
        lines.append("--------------------------------------------------------------------------------")
        lines.append("[\(timestamp)] Focus Changed Event:")
        lines.append("  App: \(context.appName) (\(context.bundleID))")
        lines.append("  Window: \(context.windowTitle) (ID: \(context.windowID.prefix(12))...)")
        lines.append("  Context Info: isInput=\(context.isInputField), isSecure=\(context.isSecureField), isBrowser=\(context.isBrowserApp)")
        lines.append("  Field: \(context.fieldDescription ?? "None") (ID: \(context.fieldID?.prefix(12) ?? "None"))")
        lines.append("  Context Role: \(context.role ?? "None")")
        
        if let s = snapshot {
            lines.append("  [AX Element Snapshot]:")
            lines.append("    Role: \(s.role ?? "nil"), Subrole: \(s.subrole ?? "nil"), RoleDesc: \(s.roleDescription ?? "nil")")
            lines.append("    ParentRole: \(s.parentRole ?? "nil")")
            lines.append("    Identifier: \(s.identifier ?? "nil"), Title: \(s.title ?? "nil"), Desc: \(s.descriptionText ?? "nil")")
            lines.append("    AXFocused: \(s.isFocused.map { String($0) } ?? "nil"), AXEditable: \(s.isEditable.map { String($0) } ?? "nil")")
            if let range = s.selectedTextRange {
                lines.append("    SelectedTextRange: loc=\(range.location), len=\(range.length)")
            } else {
                lines.append("    SelectedTextRange: nil")
            }
            lines.append("    InsertionPointLine: \(s.insertionPointLineNumber.map { String($0) } ?? "nil")")
            if let val = s.valuePreview {
                lines.append("    Value: \"\(val)\"")
            }
        }
        
        if let action = actionDescription {
            lines.append("  Action/Decision: \(action)")
        }
        
        let fullText = lines.joined(separator: "\n") + "\n"
        appendToFile(text: fullText)
    }
    
    private func appendToFile(text: String) {
        guard let data = text.data(using: .utf8) else { return }
        let fileURL = URL(fileURLWithPath: logFilePath)
        
        if !FileManager.default.fileExists(atPath: logFilePath) {
            FileManager.default.createFile(atPath: logFilePath, contents: nil, attributes: nil)
        }
        
        if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            try? fileHandle.close()
        }
    }
}
