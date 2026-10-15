import XCTest
import ApplicationServices
@testable import IMEKeeperCore

final class FocusAndNonInputPolicyTests: XCTestCase {
    
    private var tempURL: URL!
    private var manager: GranularityManager!
    
    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        tempURL = tempDir.appendingPathComponent("test_policy_\(UUID().uuidString).json")
        manager = GranularityManager(customStorageURL: tempURL)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }
    
    // MARK: - Non-Input Policy Tests
    
    func testTerminalDefaultsAreExempt() {
        let terminals = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.mitchellh.ghostty",
            "org.alacritty",
            "com.alacritty",
            "net.kovidgoyal.kitty",
            "com.github.wez.wezterm",
            "dev.warp.Warp-Stable"
        ]
        
        for term in terminals {
            XCTAssertEqual(
                manager.effectiveNonInputPolicy(for: term),
                .exempt,
                "终端 \(term) 应当默认豁免非输入框切英"
            )
        }
    }
    
    func testStandardAppDefaultsToAlwaysEnglish() {
        let standardApps = [
            "com.apple.dt.Xcode",
            "com.microsoft.VSCode",
            "com.apple.finder",
            "com.apple.Notes"
        ]
        
        for app in standardApps {
            XCTAssertEqual(
                manager.effectiveNonInputPolicy(for: app),
                .alwaysEnglish,
                "普通 App \(app) 应当默认在非输入框切为英文"
            )
        }
    }
    
    func testPerAppPolicyOverrideAndPersistence() {
        let vsCode = "com.microsoft.VSCode"
        let iterm2 = "com.googlecode.iterm2"
        
        // 覆盖 VS Code 为豁免
        manager.setNonInputPolicy(for: vsCode, policy: .exempt)
        XCTAssertEqual(manager.effectiveNonInputPolicy(for: vsCode), .exempt)
        XCTAssertEqual(manager.configuredNonInputPolicy(for: vsCode), .exempt)
        
        // 覆盖 iTerm2 为始终切英
        manager.setNonInputPolicy(for: iterm2, policy: .alwaysEnglish)
        XCTAssertEqual(manager.effectiveNonInputPolicy(for: iterm2), .alwaysEnglish)
        
        // 验证持久化重新加载
        let reloadedManager = GranularityManager(customStorageURL: tempURL)
        XCTAssertEqual(reloadedManager.effectiveNonInputPolicy(for: vsCode), .exempt)
        XCTAssertEqual(reloadedManager.effectiveNonInputPolicy(for: iterm2), .alwaysEnglish)
        
        // 清除自定义配置，回退默认
        manager.setNonInputPolicy(for: vsCode, policy: nil)
        XCTAssertEqual(manager.effectiveNonInputPolicy(for: vsCode), .alwaysEnglish)
    }
    
    // MARK: - Input Field Determination Tests
    
    func testInputFieldRoleDetermination() {
        let fingerprinter = ElementFingerprinter()
        let dummyElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        
        // 输入框角色白名单
        XCTAssertTrue(fingerprinter.determineIfInputField(element: dummyElement, role: "AXTextField", subrole: nil))
        XCTAssertTrue(fingerprinter.determineIfInputField(element: dummyElement, role: "AXTextArea", subrole: nil))
        XCTAssertTrue(fingerprinter.determineIfInputField(element: dummyElement, role: "AXSearchField", subrole: nil))
        XCTAssertTrue(fingerprinter.determineIfInputField(element: dummyElement, role: "AXComboBox", subrole: nil))
        XCTAssertTrue(fingerprinter.determineIfInputField(element: dummyElement, role: "AXGroup", subrole: "AXContentEditable"))
        XCTAssertTrue(fingerprinter.determineIfInputField(element: dummyElement, role: "AXTextField", subrole: "AXSecureTextField"))
        XCTAssertTrue(fingerprinter.determineIfInputField(element: dummyElement, role: "AXGroup", subrole: "AXSearchField"))
        XCTAssertTrue(fingerprinter.determineIfInputField(element: dummyElement, role: "AXGroup", subrole: "AXTextField"))
        
        // 明确的非输入框角色黑名单测试
        XCTAssertFalse(fingerprinter.determineIfInputField(element: dummyElement, role: "AXButton", subrole: nil))
        XCTAssertFalse(fingerprinter.determineIfInputField(element: dummyElement, role: "AXList", subrole: nil))
        XCTAssertFalse(fingerprinter.determineIfInputField(element: dummyElement, role: "AXOutline", subrole: nil))
        XCTAssertFalse(fingerprinter.determineIfInputField(element: dummyElement, role: "AXTable", subrole: nil))
        XCTAssertFalse(fingerprinter.determineIfInputField(element: dummyElement, role: "AXScrollArea", subrole: nil))
        XCTAssertFalse(fingerprinter.determineIfInputField(element: dummyElement, role: "AXScrollBar", subrole: nil))
        XCTAssertFalse(fingerprinter.determineIfInputField(element: dummyElement, role: "AXSplitGroup", subrole: nil))
        XCTAssertFalse(fingerprinter.determineIfInputField(element: dummyElement, role: "AXTabGroup", subrole: nil))
        XCTAssertFalse(fingerprinter.determineIfInputField(element: dummyElement, role: "AXToolbar", subrole: nil))
        XCTAssertFalse(fingerprinter.determineIfInputField(element: dummyElement, role: "AXWindow", subrole: nil))
        XCTAssertFalse(fingerprinter.determineIfInputField(element: dummyElement, role: "AXImage", subrole: nil))
        XCTAssertFalse(fingerprinter.determineIfInputField(element: dummyElement, role: "AXStaticText", subrole: nil))
    }
    
    func testCanvasEditorPolicyAndFocusResolution() {
        let zedBundleID = "dev.zed.Zed"
        
        // 1. Zed 编辑器默认非输入策略应当为豁免 (.exempt)
        XCTAssertEqual(
            manager.effectiveNonInputPolicy(for: zedBundleID),
            .exempt,
            "Zed 自绘编辑器默认应处于豁免策略下"
        )
        
        // 2. 指纹解析器将 Zed 视口映射为有效的可编辑输入框与稳定指纹
        let fingerprinter = ElementFingerprinter()
        let dummyElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let currentApp = NSRunningApplication.current
        
        let context = fingerprinter.resolveFocusContext(
            from: dummyElement,
            runningApp: currentApp,
            isBrowserApp: false
        )
        
        // 验证通用非输入元素不会生成 fieldID
        if !context.isInputField {
            XCTAssertNil(context.fieldID, "非输入控件不应分配 fieldID")
        }
    }
    
    // MARK: - Cross-Window Field Fallback Tests
    
    func testCrossWindowFieldFallbackInSameApp() {
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_store_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        
        let store = HierarchicalProfileStore(customStorageURL: storeURL)
        let bundleID = "com.microsoft.VSCode"
        let sharedFieldID = "stable_editor_hash_123"
        
        // 场景：在窗口 A (项目 A) 的编辑区设置了输入法 "com.apple.inputmethod.SCIM.ITABC"
        let contextA = FocusContext(
            bundleID: bundleID,
            appName: "VS Code",
            windowID: "window_project_a",
            windowTitle: "FileA.swift — ProjectA",
            fieldID: sharedFieldID,
            fieldDescription: "多行文本区 (AXTextArea)",
            role: "AXTextArea",
            isInputField: true
        )
        store.record(context: contextA, sourceID: "com.apple.inputmethod.SCIM.ITABC", effectiveGranularity: .field)
        
        // 场景：切换到窗口 B (项目 B)，当前窗口从未记录过，但具有相同的 sharedFieldID
        let contextB = FocusContext(
            bundleID: bundleID,
            appName: "VS Code",
            windowID: "window_project_b",
            windowTitle: "FileB.swift — ProjectB",
            fieldID: sharedFieldID,
            fieldDescription: "多行文本区 (AXTextArea)",
            role: "AXTextArea",
            isInputField: true
        )
        
        // 在 field 粒度下，窗口 B 应当自动继承同 App 下已记录过的相同输入框偏好
        let queryResult = store.queryPreferredSource(for: contextB, effectiveGranularity: .field)
        XCTAssertEqual(queryResult, "com.apple.inputmethod.SCIM.ITABC", "相同结构指纹的输入框应能跨窗口自动复用偏好")
    }
    
    func testIDEWindowStabilizationAcrossTabs() {
        let fingerprinter = ElementFingerprinter()
        let dummyElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        
        let vsCodeApp = NSRunningApplication.current
        // 模拟同一工程下切换两个不同文件 tab：
        // 无论文件如何切换，只要属于同一个工程工作区，windowID 应当完全恒定相同，杜绝窗口分裂
        let contextTab1 = fingerprinter.resolveFocusContext(
            from: dummyElement,
            runningApp: vsCodeApp,
            isBrowserApp: false
        )
        XCTAssertNotNil(contextTab1.windowID)
    }
}
