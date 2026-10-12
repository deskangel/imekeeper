import XCTest
@testable import IMEKeeperCore

@MainActor
final class LocalizationTests: XCTestCase {
    
    private var testDefaults: UserDefaults!
    private let suiteName = "com.antigravity.imekeeper.test.localization"
    
    override func setUp() async throws {
        try await super.setUp()
        testDefaults = UserDefaults(suiteName: suiteName)
        testDefaults.removePersistentDomain(forName: suiteName)
    }
    
    override func tearDown() async throws {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        try await super.tearDown()
    }
    
    func testInitialStateIsSystemAndResolvesEffectiveLanguage() {
        let manager = LocalizationManager(userDefaults: testDefaults)
        XCTAssertEqual(manager.currentLanguage, .system)
        
        let effective = manager.currentEffectiveLanguage
        XCTAssertTrue(effective == .zhHans || effective == .en)
    }
    
    func testExplicitLanguageSwitchingAndPersistence() {
        let manager = LocalizationManager(userDefaults: testDefaults)
        
        // 切换为英文
        manager.setLanguage(.en)
        let expEn = expectation(description: "Wait for en language set")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertEqual(manager.currentLanguage, .en)
            XCTAssertEqual(manager.currentEffectiveLanguage, .en)
            XCTAssertEqual(self.testDefaults.string(forKey: AppConstants.Storage.appLanguageStorageKey), "en")
            expEn.fulfill()
        }
        wait(for: [expEn], timeout: 1.0)
        
        // 重新初始化，确保从持久化中读取
        let reloadedManager = LocalizationManager(userDefaults: testDefaults)
        XCTAssertEqual(reloadedManager.currentLanguage, .en)
        XCTAssertEqual(reloadedManager.currentEffectiveLanguage, .en)
    }
    
    func testL10nEnglishStrings() {
        LocalizationManager.shared.setLanguage(.en)
        let exp = expectation(description: "Wait for English switch")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertEqual(L10n.menuStatusRunning, "IME Keeper: Running")
            XCTAssertEqual(L10n.menuStatusPaused, "IME Keeper: Paused")
            XCTAssertEqual(L10n.defaultWindowPlaceholder, "Main Window")
            XCTAssertEqual(L10n.settingsWindowTitle, "IME Keeper - Hierarchy Memory & Preferences")
            XCTAssertEqual(L10n.clearAllHistory, "Clear All History")
            XCTAssertEqual(L10n.doneButton, "Done")
            
            XCTAssertEqual(GranularityLevel.app.localizedName, "App Level (App)")
            XCTAssertEqual(GranularityLevel.window.localizedName, "Window Level (Window)")
            XCTAssertEqual(GranularityLevel.field.localizedName, "Field Level (Field)")
            
            XCTAssertEqual(L10n.windowSubtitle(fieldCount: 1), "Contains 1 field record")
            XCTAssertEqual(L10n.windowSubtitle(fieldCount: 5), "Contains 5 field records")
            XCTAssertEqual(L10n.fieldRoleSubtitle(role: "AXTextField"), "Role: AXTextField")
            
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
    
    func testL10nChineseStrings() {
        LocalizationManager.shared.setLanguage(.zhHans)
        let exp = expectation(description: "Wait for Chinese switch")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertEqual(L10n.menuStatusRunning, "IME Keeper: 运行中")
            XCTAssertEqual(L10n.menuStatusPaused, "IME Keeper: 已暂停")
            XCTAssertEqual(L10n.defaultWindowPlaceholder, "主窗口")
            XCTAssertEqual(L10n.settingsWindowTitle, "IME Keeper - 层级记忆与偏好设置")
            XCTAssertEqual(L10n.clearAllHistory, "清空所有历史")
            XCTAssertEqual(L10n.doneButton, "完成")
            
            XCTAssertEqual(GranularityLevel.app.localizedName, "应用级 (App)")
            XCTAssertEqual(GranularityLevel.window.localizedName, "窗口级 (Window)")
            XCTAssertEqual(GranularityLevel.field.localizedName, "输入框级 (Field)")
            
            XCTAssertEqual(L10n.windowSubtitle(fieldCount: 1), "包含 1 个输入框记录")
            XCTAssertEqual(L10n.windowSubtitle(fieldCount: 5), "包含 5 个输入框记录")
            XCTAssertEqual(L10n.fieldRoleSubtitle(role: "AXTextField"), "角色: AXTextField")
            
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
}
