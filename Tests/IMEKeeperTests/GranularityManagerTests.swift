import XCTest
@testable import IMEKeeperCore

final class GranularityManagerTests: XCTestCase {
    
    private var tempURL: URL!
    private var manager: GranularityManager!
    
    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        tempURL = tempDir.appendingPathComponent("test_gran_\(UUID().uuidString).json")
        manager = GranularityManager(customStorageURL: tempURL)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }
    
    func testDefaultGranularity() {
        XCTAssertEqual(manager.getGlobalDefault(), .field)
        
        let appBundleID = "com.apple.dt.Xcode"
        XCTAssertEqual(manager.effectiveGranularity(for: appBundleID, isBrowser: false), .field)
    }
    
    func testAppSpecificOverride() {
        let appBundleID = "com.apple.dt.Xcode"
        
        // 为 Xcode 独立设置为 .window 级
        manager.setGranularity(for: appBundleID, level: .window)
        XCTAssertEqual(manager.effectiveGranularity(for: appBundleID, isBrowser: false), .window)
        XCTAssertEqual(manager.configuredGranularity(for: appBundleID), .window)
        
        // 为 Xcode 独立设置为 .app 级
        manager.setGranularity(for: appBundleID, level: .app)
        XCTAssertEqual(manager.effectiveGranularity(for: appBundleID, isBrowser: false), .app)
        
        // 移除配置，回退至全局默认
        manager.setGranularity(for: appBundleID, level: nil)
        XCTAssertEqual(manager.effectiveGranularity(for: appBundleID, isBrowser: false), .field)
    }
    
    func testBrowserCappingProtection() {
        let safariBundleID = "com.apple.Safari"
        let chromeBundleID = "com.google.Chrome"
        
        // 全局默认是 .field 级，但当 isBrowser 为 true 且未独立配置时，系统自动保护限制在 .window 级
        XCTAssertEqual(manager.effectiveGranularity(for: safariBundleID, isBrowser: true), .window)
        XCTAssertEqual(manager.effectiveGranularity(for: chromeBundleID, isBrowser: true), .window)
        
        // 如果用户特意将浏览器配置为 .app 级，则允许 .app
        manager.setGranularity(for: safariBundleID, level: .app)
        XCTAssertEqual(manager.effectiveGranularity(for: safariBundleID, isBrowser: true), .app)
        
        // 如果用户显式将浏览器配置为 .field 级，系统尊重用户的独立配置
        manager.setGranularity(for: safariBundleID, level: .field)
        XCTAssertEqual(manager.effectiveGranularity(for: safariBundleID, isBrowser: true), .field)
    }
}
