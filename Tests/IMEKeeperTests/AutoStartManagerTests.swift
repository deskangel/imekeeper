import XCTest
@testable import IMEKeeperCore

final class AutoStartManagerTests: XCTestCase {
    
    func testMockAutoStartManagerInitialStateAndToggle() {
        let mock = MockAutoStartManager(initialEnabled: false, requiresApproval: false)
        XCTAssertFalse(mock.isAutoStartEnabled)
        XCTAssertFalse(mock.requiresApproval)
        
        // 启用自启动
        let enableSuccess = mock.setAutoStartEnabled(true)
        XCTAssertTrue(enableSuccess)
        XCTAssertTrue(mock.isAutoStartEnabled)
        
        // 关闭自启动
        let disableSuccess = mock.setAutoStartEnabled(false)
        XCTAssertTrue(disableSuccess)
        XCTAssertFalse(mock.isAutoStartEnabled)
    }
    
    func testMockAutoStartManagerWithApprovalRequired() {
        let mock = MockAutoStartManager(initialEnabled: true, requiresApproval: true)
        XCTAssertTrue(mock.isAutoStartEnabled)
        XCTAssertTrue(mock.requiresApproval)
    }
    
    @MainActor
    func testViewModelAutoStartIntegration() {
        let tempDir = FileManager.default.temporaryDirectory
        let storeURL = tempDir.appendingPathComponent("autostart_test_store_\(UUID().uuidString).json")
        let granURL = tempDir.appendingPathComponent("autostart_test_gran_\(UUID().uuidString).json")
        
        let store = HierarchicalProfileStore(customStorageURL: storeURL)
        let granManager = GranularityManager(customStorageURL: granURL)
        let mockInputSource = MockInputSourceManager()
        let mockAutoStart = MockAutoStartManager(initialEnabled: false)
        
        let viewModel = HierarchySettingsViewModel(
            store: store,
            granularityManager: granManager,
            inputSourceManager: mockInputSource,
            autoStartManager: mockAutoStart
        )
        
        // 初始状态应与 mock 保持一致
        XCTAssertFalse(viewModel.isAutoStartEnabled)
        
        // 通过 ViewModel 启用
        viewModel.setAutoStartEnabled(true)
        XCTAssertTrue(viewModel.isAutoStartEnabled)
        XCTAssertTrue(mockAutoStart.isAutoStartEnabled)
        
        // 通过 ViewModel 关闭
        viewModel.setAutoStartEnabled(false)
        XCTAssertFalse(viewModel.isAutoStartEnabled)
        XCTAssertFalse(mockAutoStart.isAutoStartEnabled)
        
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default.removeItem(at: granURL)
    }
    
    func testAutoStartManagerProductionInstanceDoesNotCrash() {
        let manager = AutoStartManager()
        // 在未打包为完整 macOS App Bundle 运行环境的 CLI 测试中，访问 status 不应崩溃
        _ = manager.isAutoStartEnabled
        _ = manager.requiresApproval
    }
    
    func testLocalizationAutoStartStrings() {
        // 中文测试
        LocalizationManager.shared.setLanguage(.zhHans)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        
        XCTAssertEqual(L10n.menuAutoStart, "开机自动启动")
        XCTAssertEqual(L10n.launchAtLoginCheckbox, "开机自启动")
        XCTAssertTrue(L10n.launchAtLoginHelp.contains("登录时自动在后台启动"))
        
        // 英文测试
        LocalizationManager.shared.setLanguage(.en)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        
        XCTAssertEqual(L10n.menuAutoStart, "Launch at Login")
        XCTAssertEqual(L10n.launchAtLoginCheckbox, "Launch at Login")
        XCTAssertTrue(L10n.launchAtLoginHelp.contains("launch IME Keeper in background"))
        
        // 恢复默认系统语言
        LocalizationManager.shared.setLanguage(.system)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
}
