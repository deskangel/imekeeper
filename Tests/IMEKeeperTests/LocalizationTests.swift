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
            XCTAssertEqual(GranularityLevel.field.localizedName, "Field Level (Field)")
            
            XCTAssertEqual(L10n.fieldRoleSubtitle(role: "AXTextField"), "Role: AXTextField")
            XCTAssertEqual(L10n.fieldHashSubtitle(hashPrefix: "a1b2c3d4"), "Hash: a1b2c3d4")
            XCTAssertEqual(L10n.doubleClickToRenameHelp, "Double-click to rename field")
            XCTAssertEqual(L10n.lockedAppCannotCleanHelp, "App is locked; sub-items are protected and cannot be cleaned. Unlock app first")
            XCTAssertEqual(L10n.cleanUnlockedFieldsHelp, "Clean unlocked fields in this app")
            XCTAssertEqual(L10n.noUnlockedFieldsToCleanHelp, "No unlocked fields to clean")
            
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
            XCTAssertEqual(GranularityLevel.field.localizedName, "输入框级 (Field)")
            
            XCTAssertEqual(L10n.fieldRoleSubtitle(role: "AXTextField"), "角色: AXTextField")
            XCTAssertEqual(L10n.fieldHashSubtitle(hashPrefix: "a1b2c3d4"), "哈希: a1b2c3d4")
            XCTAssertEqual(L10n.doubleClickToRenameHelp, "双击以重命名输入框")
            XCTAssertEqual(L10n.lockedAppCannotCleanHelp, "应用已锁定，下级记录受保护无法清理，请先解锁应用")
            XCTAssertEqual(L10n.cleanUnlockedFieldsHelp, "清理此应用下未锁定的输入框记录")
            XCTAssertEqual(L10n.noUnlockedFieldsToCleanHelp, "无待清理的未锁定输入框记录")
            
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
}
