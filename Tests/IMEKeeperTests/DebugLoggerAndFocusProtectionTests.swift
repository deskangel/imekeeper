import XCTest
import ApplicationServices
@testable import IMEKeeperCore

final class DebugLoggerAndFocusProtectionTests: XCTestCase {
    
    private var tempLogURL: URL!
    private var tempDefaultsSuite: String!
    private var testDefaults: UserDefaults!
    
    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        tempLogURL = tempDir.appendingPathComponent("test_imekeeper_\(UUID().uuidString).log")
        tempDefaultsSuite = "test_suite_\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: tempDefaultsSuite)!
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempLogURL)
        testDefaults.removePersistentDomain(forName: tempDefaultsSuite)
        super.tearDown()
    }
    
    // MARK: - Debug Logger Tests
    
    func testDebugLoggerDisabledByDefaultDoesNotWrite() {
        let logger = DebugLogger(userDefaults: testDefaults, logFilePath: tempLogURL.path)
        XCTAssertFalse(logger.isEnabled, "调试日志默认应为关闭状态")
        
        let dummyContext = FocusContext(
            bundleID: "com.google.Chrome",
            appName: "Google Chrome",
            windowID: "test_win_123",
            windowTitle: "Search Page",
            fieldID: "test_field_456",
            fieldDescription: "Search Input",
            role: "AXTextField",
            isInputField: true
        )
        
        logger.logFocusEvent(context: dummyContext, snapshot: nil, actionDescription: "Test Action")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempLogURL.path), "日志关闭时不应创建或写入文件")
    }
    
    func testDebugLoggerEnabledWritesFocusAndSnapshotInformation() {
        let logger = DebugLogger(userDefaults: testDefaults, logFilePath: tempLogURL.path)
        logger.isEnabled = true
        XCTAssertTrue(logger.isEnabled, "开关应当成功持久化")
        
        let dummyContext = FocusContext(
            bundleID: "com.google.Chrome",
            appName: "Google Chrome",
            windowID: "test_win_123",
            windowTitle: "Google Search",
            fieldID: "field_hash_abc",
            fieldDescription: "单行文本框 (AXTextField)",
            role: "AXTextField",
            isInputField: true
        )
        
        let snapshot = ElementAttributeSnapshot(
            role: "AXTextField",
            subrole: nil,
            roleDescription: "text field",
            title: "Search",
            descriptionText: "Search query",
            identifier: "q",
            isFocused: true,
            isEditable: true,
            selectedTextRange: CFRange(location: 2, length: 0),
            insertionPointLineNumber: 0,
            valuePreview: "nihao",
            parentRole: "AXWebArea"
        )
        
        logger.logFocusEvent(
            context: dummyContext,
            snapshot: snapshot,
            actionDescription: "Switched to Chinese"
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempLogURL.path), "启用日志后应成功生成日志文件")
        
        guard let content = try? String(contentsOf: tempLogURL, encoding: .utf8) else {
            XCTFail("无法读取生成的日志文件")
            return
        }
        
        XCTAssertTrue(content.contains("App: Google Chrome (com.google.Chrome)"))
        XCTAssertTrue(content.contains("Window: Google Search"))
        XCTAssertTrue(content.contains("Field: 单行文本框 (AXTextField)"))
        XCTAssertTrue(content.contains("Role: AXTextField"))
        XCTAssertTrue(content.contains("AXFocused: true"))
        XCTAssertTrue(content.contains("SelectedTextRange: loc=2, len=0"))
        XCTAssertTrue(content.contains("Value: \"nihao\""))
        XCTAssertTrue(content.contains("Action/Decision: Switched to Chinese"))
    }
    
    // MARK: - Transient Container Fallback Protection Logic Tests
    
    func testTransientContainerFallbackLogic() {
        let prevContext = FocusContext(
            bundleID: "com.google.Chrome",
            appName: "Google Chrome",
            windowID: "win_search_1",
            windowTitle: "Google",
            fieldID: "field_search_input",
            fieldDescription: "单行文本框 (AXTextField)",
            role: "AXTextField",
            isInputField: true
        )
        
        // 场景 1：在相同 App、相同窗口内，焦点降级为 AXApplication（例如浏览器下拉建议或输入法候选词浮窗导致无障碍焦点丢失）
        let fallbackToApp = FocusContext(
            bundleID: "com.google.Chrome",
            appName: "Google Chrome",
            windowID: "win_search_1",
            windowTitle: "Google",
            fieldID: nil,
            fieldDescription: nil,
            role: "AXApplication",
            isInputField: false
        )
        
        let isFallbackApp = prevContext.isInputField &&
            prevContext.bundleID == fallbackToApp.bundleID &&
            prevContext.windowID == fallbackToApp.windowID &&
            (fallbackToApp.role == "AXApplication" || fallbackToApp.role == "AXWindow" || fallbackToApp.role == AppConstants.Accessibility.webAreaRole)
        
        XCTAssertTrue(isFallbackApp, "同窗口同应用下退回 AXApplication 应当被识别为瞬态容器回退")
        
        // 场景 2：用户明确切换了应用（bundleID 变更）
        let switchedApp = FocusContext(
            bundleID: "com.apple.finder",
            appName: "Finder",
            windowID: "win_finder_1",
            windowTitle: "Downloads",
            fieldID: nil,
            fieldDescription: nil,
            role: "AXApplication",
            isInputField: false
        )
        
        let isFallbackSwitched = prevContext.isInputField &&
            prevContext.bundleID == switchedApp.bundleID &&
            prevContext.windowID == switchedApp.windowID &&
            (switchedApp.role == "AXApplication" || switchedApp.role == "AXWindow" || switchedApp.role == AppConstants.Accessibility.webAreaRole)
        
        XCTAssertFalse(isFallbackSwitched, "跨应用切换不属于同窗口瞬态容器回退")
        
        // 场景 3：用户明确点击了非输入控件（如按钮 AXButton）
        let clickedButton = FocusContext(
            bundleID: "com.google.Chrome",
            appName: "Google Chrome",
            windowID: "win_search_1",
            windowTitle: "Google",
            fieldID: nil,
            fieldDescription: nil,
            role: "AXButton",
            isInputField: false
        )
        
        let isFallbackButton = prevContext.isInputField &&
            prevContext.bundleID == clickedButton.bundleID &&
            prevContext.windowID == clickedButton.windowID &&
            (clickedButton.role == "AXApplication" || clickedButton.role == "AXWindow" || clickedButton.role == AppConstants.Accessibility.webAreaRole)
        
        XCTAssertFalse(isFallbackButton, "用户明确聚焦在具体按钮上时不属于容器回退，应正常执行非输入策略")
    }
}
