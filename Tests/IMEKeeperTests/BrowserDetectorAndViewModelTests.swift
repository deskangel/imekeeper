import XCTest
@testable import IMEKeeperCore

final class MockInputSourceManager: @unchecked Sendable, InputSourceManagerProtocol {
    var currentSource: InputSourceModel = InputSourceModel(id: "com.apple.keylayout.ABC", localizedName: "ABC", isAsciiCapable: true, isCurrent: true)
    var availableSources: [InputSourceModel] = [
        InputSourceModel(id: "com.apple.keylayout.ABC", localizedName: "ABC", isAsciiCapable: true, isCurrent: true),
        InputSourceModel(id: "com.apple.inputmethod.SCIM.ITABC", localizedName: "简体拼音", isAsciiCapable: false, isCurrent: false)
    ]
    var onUserChangedHandler: (@Sendable (InputSourceModel) -> Void)?
    
    func selectSource(id sourceID: String) -> Bool {
        if let found = availableSources.first(where: { $0.id == sourceID }) {
            currentSource = found
            return true
        }
        return false
    }
    
    func setOnUserChangedSourceHandler(_ handler: (@Sendable (InputSourceModel) -> Void)?) {
        self.onUserChangedHandler = handler
    }
    
    func reloadAvailableSources() {}
}

final class BrowserDetectorAndViewModelTests: XCTestCase {
    
    func testBrowserDetection() {
        let detector = BrowserAppDetector()
        
        // 浏览器应识别为 true
        XCTAssertTrue(detector.isBrowser(bundleID: "com.apple.Safari"))
        XCTAssertTrue(detector.isBrowser(bundleID: "com.google.Chrome"))
        XCTAssertTrue(detector.isBrowser(bundleID: "company.thebrowser.Browser"))
        XCTAssertTrue(detector.isBrowser(bundleID: "com.microsoft.edgemac"))
        XCTAssertTrue(detector.isBrowser(bundleID: "org.mozilla.firefox"))
        
        // 原生普通 App 应识别为 false
        XCTAssertFalse(detector.isBrowser(bundleID: "com.apple.dt.Xcode"))
        XCTAssertFalse(detector.isBrowser(bundleID: "com.apple.Terminal"))
        XCTAssertFalse(detector.isBrowser(bundleID: "com.tencent.xinWeChat"))
    }
    
    @MainActor
    func testViewModelSearchAndFiltering() {
        let tempDir = FileManager.default.temporaryDirectory
        let storeURL = tempDir.appendingPathComponent("vm_test_store_\(UUID().uuidString).json")
        let granURL = tempDir.appendingPathComponent("vm_test_gran_\(UUID().uuidString).json")
        
        let store = HierarchicalProfileStore(customStorageURL: storeURL)
        let granManager = GranularityManager(customStorageURL: granURL)
        let mockManager = MockInputSourceManager()
        
        // 预设两条数据
        let xcodeContext = FocusContext(
            bundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            windowID: "win-1",
            windowTitle: "AppDelegate.swift"
        )
        store.record(context: xcodeContext, sourceID: "com.apple.keylayout.ABC", effectiveGranularity: .field)
        
        let wechatContext = FocusContext(
            bundleID: "com.tencent.xinWeChat",
            appName: "微信",
            windowID: "win-chat",
            windowTitle: "技术交流群"
        )
        store.record(context: wechatContext, sourceID: "com.apple.inputmethod.SCIM.ITABC", effectiveGranularity: .field)
        
        let viewModel = HierarchySettingsViewModel(
            store: store,
            granularityManager: granManager,
            inputSourceManager: mockManager
        )
        
        // 初始无搜索时应包含两条
        XCTAssertEqual(viewModel.hierarchyItems.count, 2)
        
        // 搜索 "微信"
        viewModel.searchQuery = "微信"
        XCTAssertEqual(viewModel.hierarchyItems.count, 1)
        XCTAssertEqual(viewModel.hierarchyItems.first?.title, "微信")
        
        // 搜索 "Xcode"
        viewModel.searchQuery = "xcode"
        XCTAssertEqual(viewModel.hierarchyItems.count, 1)
        XCTAssertEqual(viewModel.hierarchyItems.first?.title, "Xcode")
        
        // 清空搜索
        viewModel.searchQuery = ""
        XCTAssertEqual(viewModel.hierarchyItems.count, 2)
        
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default.removeItem(at: granURL)
    }
    
    @MainActor
    func testViewModelFocusedAppSelection() {
        let tempDir = FileManager.default.temporaryDirectory
        let storeURL = tempDir.appendingPathComponent("vm_sel_test_store_\(UUID().uuidString).json")
        let granURL = tempDir.appendingPathComponent("vm_sel_test_gran_\(UUID().uuidString).json")
        
        let store = HierarchicalProfileStore(customStorageURL: storeURL)
        let granManager = GranularityManager(customStorageURL: granURL)
        granManager.setGlobalDefault(.app)
        let mockManager = MockInputSourceManager()
        
        let xcodeContext = FocusContext(
            bundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            windowID: "win-1",
            windowTitle: "AppDelegate.swift"
        )
        store.record(context: xcodeContext, sourceID: "com.apple.keylayout.ABC", effectiveGranularity: .app)
        
        let wechatContext = FocusContext(
            bundleID: "com.tencent.xinWeChat",
            appName: "微信",
            windowID: "win-chat",
            windowTitle: "技术交流群"
        )
        store.record(context: wechatContext, sourceID: "com.apple.inputmethod.SCIM.ITABC", effectiveGranularity: .app)
        
        let viewModel = HierarchySettingsViewModel(
            store: store,
            granularityManager: granManager,
            inputSourceManager: mockManager
        )
        
        // 当切换焦点到 Xcode 时，应自动选中 app:com.apple.dt.Xcode
        viewModel.handleFocusChanged(xcodeContext)
        XCTAssertEqual(viewModel.selectedItemID, "app:com.apple.dt.Xcode")
        
        // 当切换焦点到微信时，应自动选中 app:com.tencent.xinWeChat
        viewModel.handleFocusChanged(wechatContext)
        XCTAssertEqual(viewModel.selectedItemID, "app:com.tencent.xinWeChat")
        
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default.removeItem(at: granURL)
    }
    
    @MainActor
    func testViewModelGranularityBasedFocusLocation() {
        let tempDir = FileManager.default.temporaryDirectory
        let storeURL = tempDir.appendingPathComponent("vm_gran_loc_store_\(UUID().uuidString).json")
        let granURL = tempDir.appendingPathComponent("vm_gran_loc_gran_\(UUID().uuidString).json")
        
        let store = HierarchicalProfileStore(customStorageURL: storeURL)
        let granManager = GranularityManager(customStorageURL: granURL)
        let mockManager = MockInputSourceManager()
        
        // 准备一个包含 Window 和 Field 的数据结构
        let contextField = FocusContext(
            bundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            windowID: "win-main",
            windowTitle: "Main.swift",
            fieldID: "field-editor",
            fieldDescription: "Editor",
            role: "AXTextArea"
        )
        store.record(context: contextField, sourceID: "com.apple.keylayout.ABC", effectiveGranularity: .field)
        
        let viewModel = HierarchySettingsViewModel(
            store: store,
            granularityManager: granManager,
            inputSourceManager: mockManager
        )
        
        let appID = "app:com.apple.dt.Xcode"
        let fieldID = "field:com.apple.dt.Xcode:field-editor"
        
        // 1. 当粒度设为 .app 时，仅定位到 app 节点，不展开任何子项
        granManager.setGranularity(for: "com.apple.dt.Xcode", level: .app)
        viewModel.handleFocusChanged(contextField)
        XCTAssertEqual(viewModel.selectedItemID, appID)
        XCTAssertFalse(viewModel.isExpanded(appID))
        
        // 2. 当粒度设为 .field 时，定位到具体的 field 节点，并同时展开所属 app
        granManager.setGranularity(for: "com.apple.dt.Xcode", level: .field)
        viewModel.handleFocusChanged(contextField)
        XCTAssertEqual(viewModel.selectedItemID, fieldID)
        XCTAssertTrue(viewModel.isExpanded(appID))
        
        // 3. 当处于 .field 粒度但遇到未记录的输入框或非输入区时，平滑回退至 app 级
        let nonFieldContext = FocusContext(
            bundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            windowID: "win-main",
            windowTitle: "Main.swift",
            fieldID: "unrecorded-field",
            isInputField: false
        )
        viewModel.handleFocusChanged(nonFieldContext)
        XCTAssertEqual(viewModel.selectedItemID, appID)
        
        // 4. 当遇到完全未记录的上下文时，平滑定位至 app 级
        let unrecordedContext = FocusContext(
            bundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            windowID: "unknown-win",
            windowTitle: "Unknown"
        )
        viewModel.handleFocusChanged(unrecordedContext)
        XCTAssertEqual(viewModel.selectedItemID, appID)
        
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default.removeItem(at: granURL)
    }
    
    @MainActor
    func testViewModelSetGranularityAutoExpandsNode() {
        let tempDir = FileManager.default.temporaryDirectory
        let storeURL = tempDir.appendingPathComponent("vm_test_expand_\(UUID().uuidString).json")
        let granURL = tempDir.appendingPathComponent("vm_test_gran_expand_\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: granURL)
        }
        
        let store = HierarchicalProfileStore(customStorageURL: storeURL)
        let granManager = GranularityManager(customStorageURL: granURL)
        let mockManager = MockInputSourceManager()
        
        let appBundleID = "com.google.antigravity-ide"
        let context = FocusContext(
            bundleID: appBundleID,
            appName: "Antigravity IDE",
            windowID: "win-1",
            windowTitle: "Main"
        )
        store.record(context: context, sourceID: "com.apple.keylayout.ABC", effectiveGranularity: .app)
        
        let viewModel = HierarchySettingsViewModel(
            store: store,
            granularityManager: granManager,
            inputSourceManager: mockManager
        )
        
        let appNodeID = "app:\(appBundleID)"
        XCTAssertFalse(viewModel.isExpanded(appNodeID))
        
        // 当用户将该 App 的粒度设为 .field 时，应当自动展开该应用节点
        viewModel.setGranularity(for: appBundleID, level: .field)
        XCTAssertTrue(viewModel.isExpanded(appNodeID))
        
        // 当用户将粒度设为 .app 时，维持已有状态
        viewModel.setExpanded(appNodeID, isExpanded: false)
        viewModel.setGranularity(for: appBundleID, level: .app)
        XCTAssertFalse(viewModel.isExpanded(appNodeID))
    }
}
