import XCTest
@testable import IMEKeeperCore

final class InputSwitchAntiOscillationTests: XCTestCase {
    
    private var tempURL: URL!
    private var store: HierarchicalProfileStore!
    private var granularityManager: GranularityManager!
    
    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        tempURL = tempDir.appendingPathComponent("anti_oscillation_test_\(UUID().uuidString).json")
        store = HierarchicalProfileStore(customStorageURL: tempURL)
        granularityManager = GranularityManager()
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }
    
    // MARK: - Timing Constants Verification
    
    func testAntiOscillationTimingConstantsConfigured() {
        // 验证防抖、抑制窗口与手动保护冷静期参数均合理配置且无魔法数字
        XCTAssertGreaterThan(AppConstants.Timing.focusDebounceMilliseconds, 0)
        XCTAssertGreaterThan(AppConstants.Timing.antiLoopSuppressionTimeoutSeconds, 0.1)
        XCTAssertGreaterThan(AppConstants.Timing.manualSwitchGracePeriodSeconds, 0.1)
        XCTAssertLessThanOrEqual(AppConstants.Timing.manualSwitchGracePeriodSeconds, 1.0)
    }
    
    // MARK: - Non-Input Field Manual Switch & Inheritance Tests
    
    func testNonInputFieldManualSwitchPersistsAtAppLevel() {
        let bundleID = "com.apple.Safari"
        let windowID = "win-main-page"
        let sourceChinese = "com.apple.inputmethod.SCIM.ITABC"
        
        // 构造非输入框焦点上下文 (isInputField = false)
        let nonInputContext = FocusContext(
            bundleID: bundleID,
            appName: "Safari",
            windowID: windowID,
            windowTitle: "Search Page",
            fieldID: nil,
            fieldDescription: nil,
            role: "AXWebArea",
            isBrowserApp: true,
            isInputField: false
        )
        
        // 模拟用户在空白区手动按下快捷键切为中文：回退以 .app 粒度记录
        store.record(context: nonInputContext, sourceID: sourceChinese, effectiveGranularity: .app)
        
        // 验证应用级输入法偏好成功更新为中文
        let queriedSource = store.queryPreferredSource(for: nonInputContext, effectiveGranularity: .app)
        XCTAssertEqual(queriedSource, sourceChinese, "非输入框下的手动切换应当成功持久化至 App 层级")
    }
    
    func testNewFieldInheritsAppManualSwitchPreference() {
        let bundleID = "com.apple.Notes"
        let windowID = "win-note-1"
        let sourceChinese = "com.apple.inputmethod.SCIM.ITABC"
        
        // 1. 用户在应用空白区手动切换输入法为中文
        let nonInputContext = FocusContext(
            bundleID: bundleID,
            appName: "Notes",
            windowID: windowID,
            windowTitle: "My Note",
            fieldID: nil,
            fieldDescription: nil,
            role: "AXWindow",
            isInputField: false
        )
        store.record(context: nonInputContext, sourceID: sourceChinese, effectiveGranularity: .app)
        
        // 2. 随后用户点击进入全新输入框 (从未单独记录过 fieldID)
        let newFieldContext = FocusContext(
            bundleID: bundleID,
            appName: "Notes",
            windowID: windowID,
            windowTitle: "My Note",
            fieldID: "new_editor_field_hash_456",
            fieldDescription: "正文编辑区",
            role: "AXTextArea",
            isInputField: true
        )
        
        // 3. 在 field 粒度下查询：新输入框应当继承应用最后使用的中文输入法，杜绝切回旧英文
        let resolvedSource = store.queryPreferredSource(for: newFieldContext, effectiveGranularity: .field)
        XCTAssertEqual(resolvedSource, sourceChinese, "新获得焦点的输入框必须自动继承该应用手动设定的输入法，避免振荡切英")
    }
    
    // MARK: - Lock Safety Verification
    
    func testLockedContextDoesNotMutateDuringManualSwitch() {
        let bundleID = "com.apple.dt.Xcode"
        let windowID = "win-code"
        let sourceEnglish = "com.apple.keylayout.ABC"
        let sourceChinese = "com.apple.inputmethod.SCIM.ITABC"
        
        let context = FocusContext(
            bundleID: bundleID,
            appName: "Xcode",
            windowID: windowID,
            windowTitle: "AppDelegate.swift",
            fieldID: "editor_field_1",
            fieldDescription: "Source Editor",
            role: "AXTextArea",
            isInputField: true
        )
        
        // 初始记录为英文并锁定该 App
        store.record(context: context, sourceID: sourceEnglish, effectiveGranularity: .app)
        let tree = store.buildHierarchyItems(granularityManager: granularityManager)
        if let appItem = tree.first {
            store.toggleLock(for: appItem)
        }
        
        XCTAssertTrue(store.isContextLocked(for: context, effectiveGranularity: .app))
        
        // 尝试模拟手动切换记录，验证锁定层级输入法绝不被冲掉
        store.record(context: context, sourceID: sourceChinese, effectiveGranularity: .app)
        let queriedSource = store.queryPreferredSource(for: context, effectiveGranularity: .app)
        XCTAssertEqual(queriedSource, sourceEnglish, "App 锁定状态下，手动切换记录绝不污染锁定偏好")
    }
}
