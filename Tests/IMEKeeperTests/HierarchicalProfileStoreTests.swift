import XCTest
@testable import IMEKeeperCore

final class HierarchicalProfileStoreTests: XCTestCase {
    
    private var tempURL: URL!
    private var store: HierarchicalProfileStore!
    private var granularityManager: GranularityManager!
    
    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        tempURL = tempDir.appendingPathComponent("test_profiles_\(UUID().uuidString).json")
        let granURL = tempDir.appendingPathComponent("test_granularity_\(UUID().uuidString).json")
        
        store = HierarchicalProfileStore(customStorageURL: tempURL)
        granularityManager = GranularityManager(customStorageURL: granURL)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }
    
    func testFieldLevelLookupAndInheritance() {
        let appBundleID = "com.apple.dt.Xcode"
        let windowID = "win-main-1"
        let field1ID = "field-editor"
        let field2ID = "field-search"
        let sourceEnglish = "com.apple.keylayout.ABC"
        let sourceChinese = "com.apple.inputmethod.SCIM.ITABC"
        
        // 1. 在 field-editor 中记录为英文
        let context1 = FocusContext(
            bundleID: appBundleID,
            appName: "Xcode",
            windowID: windowID,
            windowTitle: "Project.swift",
            fieldID: field1ID,
            fieldDescription: "代码编辑区",
            role: "AXTextArea"
        )
        store.record(context: context1, sourceID: sourceEnglish, effectiveGranularity: .field)
        
        // 验证 field-editor 查询出英文
        let result1 = store.queryPreferredSource(for: context1, effectiveGranularity: .field)
        XCTAssertEqual(result1, sourceEnglish)
        
        // 2. 在同一窗口内聚焦全新的输入框 field-search (尚未被记录)
        let context2 = FocusContext(
            bundleID: appBundleID,
            appName: "Xcode",
            windowID: windowID,
            windowTitle: "Project.swift",
            fieldID: field2ID,
            fieldDescription: "搜索框",
            role: "AXSearchField"
        )
        
        // 验证：严格遵循用户决策，未记录的全新输入框默认继承所属窗口最后使用的输入法 (即英文)
        let result2 = store.queryPreferredSource(for: context2, effectiveGranularity: .field)
        XCTAssertEqual(result2, sourceEnglish, "全新输入框应当自动继承该窗口最后一次记录的输入法")
        
        // 3. 用户在 field-search 中手动切换为中文并记录
        store.record(context: context2, sourceID: sourceChinese, effectiveGranularity: .field)
        
        // 再次查询两个输入框，验证彼此独立并分别记忆
        XCTAssertEqual(store.queryPreferredSource(for: context1, effectiveGranularity: .field), sourceEnglish)
        XCTAssertEqual(store.queryPreferredSource(for: context2, effectiveGranularity: .field), sourceChinese)
    }
    
    func testWindowLevelFallbackWhenFieldDisabled() {
        let appBundleID = "com.apple.dt.Xcode"
        let windowID = "win-main-1"
        let fieldID = "field-search"
        let sourceChinese = "com.apple.inputmethod.SCIM.ITABC"
        
        let context = FocusContext(
            bundleID: appBundleID,
            appName: "Xcode",
            windowID: windowID,
            windowTitle: "Project.swift",
            fieldID: fieldID,
            fieldDescription: "搜索框",
            role: "AXSearchField"
        )
        store.record(context: context, sourceID: sourceChinese, effectiveGranularity: .window)
        
        // 当粒度被限制为 .window 时，即使用户在不同 field，也只返回 window 级输入法
        let queryResult = store.queryPreferredSource(for: context, effectiveGranularity: .window)
        XCTAssertEqual(queryResult, sourceChinese)
    }
    
    func testAppLevelFallback() {
        let appBundleID = "com.apple.Terminal"
        let window1 = "win-term-1"
        let window2 = "win-term-2"
        let sourceEnglish = "com.apple.keylayout.ABC"
        
        let context1 = FocusContext(
            bundleID: appBundleID,
            appName: "Terminal",
            windowID: window1,
            windowTitle: "bash"
        )
        store.record(context: context1, sourceID: sourceEnglish, effectiveGranularity: .app)
        
        // 打开全新窗口 window2，粒度为 .app 时直接回退至 App 级记录
        let context2 = FocusContext(
            bundleID: appBundleID,
            appName: "Terminal",
            windowID: window2,
            windowTitle: "zsh"
        )
        let result = store.queryPreferredSource(for: context2, effectiveGranularity: .app)
        XCTAssertEqual(result, sourceEnglish)
    }
    
    func testTreeModificationAndDeletion() {
        let appBundleID = "com.apple.Notes"
        let windowID = "win-notes"
        let fieldID = "field-note-body"
        
        let context = FocusContext(
            bundleID: appBundleID,
            appName: "备忘录",
            windowID: windowID,
            windowTitle: "我的笔记",
            fieldID: fieldID,
            fieldDescription: "正文",
            role: "AXTextArea"
        )
        store.record(context: context, sourceID: "com.apple.keylayout.ABC", effectiveGranularity: .field)
        
        // 构造树结构
        let tree = store.buildHierarchyItems(granularityManager: granularityManager)
        XCTAssertEqual(tree.count, 1)
        XCTAssertEqual(tree.first?.children?.count, 1)
        
        // 修改输入法
        if let fieldItem = tree.first?.children?.first?.children?.first {
            store.updateSource(for: fieldItem, newSourceID: "com.apple.inputmethod.SCIM.ITABC")
            let updated = store.queryPreferredSource(for: context, effectiveGranularity: .field)
            XCTAssertEqual(updated, "com.apple.inputmethod.SCIM.ITABC")
            
            // 删除该节点
            store.delete(item: fieldItem)
            let afterDelete = store.buildHierarchyItems(granularityManager: granularityManager)
            XCTAssertEqual(afterDelete.first?.children?.first?.children?.count ?? 0, 0)
        } else {
            XCTFail("应当成功构造三级树节点")
        }
    }
}
