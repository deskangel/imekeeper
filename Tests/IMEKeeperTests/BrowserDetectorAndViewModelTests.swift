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
}
