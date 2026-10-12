import XCTest
import AppKit
@testable import IMEKeeperCore

final class AppIconProviderTests: XCTestCase {
    
    private var provider: AppIconProvider!
    
    override func setUp() {
        super.setUp()
        provider = AppIconProvider()
    }
    
    override func tearDown() {
        provider.clearCache()
        super.tearDown()
    }
    
    func testEmptyOrWhitespaceBundleIDReturnsNil() {
        XCTAssertNil(provider.icon(for: ""))
        XCTAssertNil(provider.icon(for: "   "))
    }
    
    func testNonExistentAppBundleIDReturnsNil() {
        let fakeBundleID = "com.nonexistent.fakeapp.\(UUID().uuidString)"
        XCTAssertNil(provider.icon(for: fakeBundleID))
    }
    
    func testSystemAppIconResolutionAndCaching() {
        let finderBundleID = "com.apple.finder"
        
        let firstLookup = provider.icon(for: finderBundleID)
        XCTAssertNotNil(firstLookup, "Finder 应能成功解析出系统应用图标")
        
        let secondLookup = provider.icon(for: finderBundleID)
        XCTAssertNotNil(secondLookup)
        XCTAssertEqual(firstLookup, secondLookup, "第二次查找应从缓存中直接返回同一 NSImage 实例")
    }
    
    func testClearCache() {
        let finderBundleID = "com.apple.finder"
        let _ = provider.icon(for: finderBundleID)
        
        provider.clearCache()
        
        // 清理缓存后再次查询仍应正常解析
        let afterClearLookup = provider.icon(for: finderBundleID)
        XCTAssertNotNil(afterClearLookup)
    }
}
