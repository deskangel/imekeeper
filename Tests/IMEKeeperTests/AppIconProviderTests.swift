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
    
    func testNegativeCachingForUnresolvedBundleID() {
        let fakeBundleID = "com.nonexistent.fakeapp.\(UUID().uuidString)"
        
        // 第一次查询：解析失败并存入负缓存
        let firstLookup = provider.icon(for: fakeBundleID)
        XCTAssertNil(firstLookup)
        
        // 第二次查询：命中负缓存，直接快速返回 nil
        let secondLookup = provider.icon(for: fakeBundleID)
        XCTAssertNil(secondLookup)
        
        // 清除缓存后重试
        provider.clearCache()
        let afterClear = provider.icon(for: fakeBundleID)
        XCTAssertNil(afterClear)
    }
    
    func testIconThumbnailPreScaledSize() {
        let finderBundleID = "com.apple.finder"
        guard let icon = provider.icon(for: finderBundleID) else {
            XCTFail("Finder 图标应能成功解析")
            return
        }
        
        XCTAssertEqual(icon.size.width, AppConstants.UI.iconThumbnailSize)
        XCTAssertEqual(icon.size.height, AppConstants.UI.iconThumbnailSize)
    }
}
