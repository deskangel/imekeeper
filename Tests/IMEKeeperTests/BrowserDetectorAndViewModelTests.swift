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
    
    @MainActor
    func testPreferencesAppLockDoesNotSortImmediatelyUntilReopened() {
        let tempDir = FileManager.default.temporaryDirectory
        let storeURL = tempDir.appendingPathComponent("vm_test_lock_sort_\(UUID().uuidString).json")
        let granURL = tempDir.appendingPathComponent("vm_test_gran_sort_\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: granURL)
        }
        
        let store = HierarchicalProfileStore(customStorageURL: storeURL)
        let granManager = GranularityManager(customStorageURL: granURL)
        let mockManager = MockInputSourceManager()
        
        let appA = "com.test.Alpha"
        let appB = "com.test.Beta"
        let appZ = "com.test.Zulu"
        
        let ctxA = FocusContext(bundleID: appA, appName: "Alpha", windowID: "win-a", windowTitle: "Win A")
        let ctxB = FocusContext(bundleID: appB, appName: "Beta", windowID: "win-b", windowTitle: "Win B")
        let ctxZ = FocusContext(bundleID: appZ, appName: "Zulu", windowID: "win-z", windowTitle: "Win Z")
        
        store.record(context: ctxA, sourceID: "s1", effectiveGranularity: .app)
        store.record(context: ctxB, sourceID: "s2", effectiveGranularity: .app)
        store.record(context: ctxZ, sourceID: "s3", effectiveGranularity: .app)
        
        let viewModel = HierarchySettingsViewModel(
            store: store,
            granularityManager: granManager,
            inputSourceManager: mockManager
        )
        
        // 初始状态：未锁定，按字母顺序排列
        XCTAssertEqual(viewModel.hierarchyItems.map(\.title), ["Alpha", "Beta", "Zulu"])
        
        guard let zuluItem = viewModel.hierarchyItems.first(where: { $0.title == "Zulu" }) else {
            XCTFail("未找到 Zulu 节点")
            return
        }
        
        // 1. 在偏好设置中锁定 Zulu：要求不立刻重排序，保持视觉位置在原处
        viewModel.toggleLock(for: zuluItem)
        
        let updatedZulu = viewModel.hierarchyItems.first(where: { $0.title == "Zulu" })
        XCTAssertEqual(updatedZulu?.isLocked, true)
        XCTAssertEqual(updatedZulu?.lockStatus, .locked(level: .app))
        // 顺序应当保持不变，Zulu 依然在最后
        XCTAssertEqual(
            viewModel.hierarchyItems.map(\.title),
            ["Alpha", "Beta", "Zulu"],
            "锁定 App 时不能立刻触发排序，必须保持当前列表顺序稳定"
        )
        
        // 2. 模拟重新打开 preferences：此时才触发排序，已锁定的 Zulu 置顶
        viewModel.openPreferences()
        XCTAssertEqual(
            viewModel.hierarchyItems.map(\.title),
            ["Zulu", "Alpha", "Beta"],
            "重新打开偏好设置时必须执行排序，将已锁定的 App 排在最前面"
        )
        
        // 3. 在偏好设置中解锁 Zulu：同样不能立刻重排序
        guard let lockedZulu = viewModel.hierarchyItems.first(where: { $0.title == "Zulu" }) else {
            XCTFail("未找到置顶的 Zulu 节点")
            return
        }
        viewModel.toggleLock(for: lockedZulu)
        
        let unlockedZulu = viewModel.hierarchyItems.first(where: { $0.title == "Zulu" })
        XCTAssertEqual(unlockedZulu?.isLocked, false)
        XCTAssertEqual(unlockedZulu?.lockStatus, .unlocked)
        // 顺序应当保持不变，未重排前 Zulu 依然在最前面
        XCTAssertEqual(
            viewModel.hierarchyItems.map(\.title),
            ["Zulu", "Alpha", "Beta"],
            "解锁 App 时不能立刻触发排序，必须保持当前列表顺序稳定"
        )
        
        // 4. 再次打开 preferences 时触发排序，恢复字母顺序
        viewModel.openPreferences()
        XCTAssertEqual(
            viewModel.hierarchyItems.map(\.title),
            ["Alpha", "Beta", "Zulu"],
            "重新打开偏好设置时执行排序，恢复未锁定的字母排序"
        )
    }
}
