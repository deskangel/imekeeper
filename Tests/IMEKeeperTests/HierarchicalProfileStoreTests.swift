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
    
    func testCascadingSourceUpdateFromAppAndWindow() {
        let appBundleID = "com.apple.dt.Xcode"
        let windowID = "win-main"
        let fieldID = "field-code"
        let sourceEnglish = "com.apple.keylayout.ABC"
        let sourceChinese = "com.apple.inputmethod.SCIM.ITABC"
        let sourceJapanese = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"
        
        let context = FocusContext(
            bundleID: appBundleID,
            appName: "Xcode",
            windowID: windowID,
            windowTitle: "Main.swift",
            fieldID: fieldID,
            fieldDescription: "代码编辑器",
            role: "AXTextArea"
        )
        store.record(context: context, sourceID: sourceEnglish, effectiveGranularity: .field)
        
        let tree = store.buildHierarchyItems(granularityManager: granularityManager)
        guard let appItem = tree.first,
              let winItem = appItem.children?.first else {
            XCTFail("应当成功构造大纲树")
            return
        }
        
        // 1. 在 App 级别修改输入法为中文，验证下属窗口和输入框全部级联更新
        store.updateSource(for: appItem, newSourceID: sourceChinese)
        XCTAssertEqual(store.queryPreferredSource(for: context, effectiveGranularity: .field), sourceChinese, "App 级别修改输入法必须级联覆盖其下所有输入框")
        XCTAssertEqual(store.queryPreferredSource(for: context, effectiveGranularity: .window), sourceChinese, "App 级别修改输入法必须级联覆盖其下所有窗口")
        
        let treeAfterAppUpdate = store.buildHierarchyItems(granularityManager: granularityManager)
        XCTAssertEqual(treeAfterAppUpdate.first?.currentSourceID, sourceChinese)
        XCTAssertEqual(treeAfterAppUpdate.first?.children?.first?.currentSourceID, sourceChinese)
        XCTAssertEqual(treeAfterAppUpdate.first?.children?.first?.children?.first?.currentSourceID, sourceChinese)
        
        // 2. 在 Window 级别修改输入法为日文，验证下属输入框级联更新
        store.updateSource(for: winItem, newSourceID: sourceJapanese)
        XCTAssertEqual(store.queryPreferredSource(for: context, effectiveGranularity: .field), sourceJapanese, "Window 级别修改输入法必须级联覆盖其下所有输入框")
        
        let treeAfterWinUpdate = store.buildHierarchyItems(granularityManager: granularityManager)
        XCTAssertEqual(treeAfterWinUpdate.first?.children?.first?.currentSourceID, sourceJapanese)
        XCTAssertEqual(treeAfterWinUpdate.first?.children?.first?.children?.first?.currentSourceID, sourceJapanese)
    }
    
    func testLockingPreventsRecordOverwrite() {
        let appBundleID = "com.apple.dt.Xcode"
        let windowID = "win-main"
        let fieldID = "field-code"
        let sourceEnglish = "com.apple.keylayout.ABC"
        let sourceChinese = "com.apple.inputmethod.SCIM.ITABC"
        
        let context = FocusContext(
            bundleID: appBundleID,
            appName: "Xcode",
            windowID: windowID,
            windowTitle: "Main.swift",
            fieldID: fieldID,
            fieldDescription: "代码编辑器",
            role: "AXTextArea"
        )
        
        // 初始记录为英文
        store.record(context: context, sourceID: sourceEnglish, effectiveGranularity: .field)
        
        let tree = store.buildHierarchyItems(granularityManager: granularityManager)
        guard let appItem = tree.first else {
            XCTFail("应当成功构造大纲树")
            return
        }
        
        // 1. 切换 App 为锁定状态
        store.toggleLock(for: appItem)
        XCTAssertTrue(store.isContextLocked(for: context, effectiveGranularity: .app))
        XCTAssertTrue(store.isContextLocked(for: context, effectiveGranularity: .window))
        XCTAssertTrue(store.isContextLocked(for: context, effectiveGranularity: .field))
        
        // 2. 模拟临时手动切换输入法为中文并尝试 record 记录
        store.record(context: context, sourceID: sourceChinese, effectiveGranularity: .app)
        
        // 3. 验证被锁定后，App 级输入法未被冲掉，依然保持英文
        let queryResult = store.queryPreferredSource(for: context, effectiveGranularity: .app)
        XCTAssertEqual(queryResult, sourceEnglish, "App 锁定后，临时切换输入法绝不覆盖记忆设置")
    }
    
    func testThreeDistinctLockLevelsAndInheritance() {
        let appBundleID = "com.test.Editor"
        let win1ID = "win-1"
        let win2ID = "win-2"
        let field1ID = "field-1"
        
        let context1 = FocusContext(
            bundleID: appBundleID,
            appName: "Editor",
            windowID: win1ID,
            windowTitle: "Window 1",
            fieldID: field1ID,
            fieldDescription: "Input",
            role: "AXTextField"
        )
        let context2 = FocusContext(
            bundleID: appBundleID,
            appName: "Editor",
            windowID: win2ID,
            windowTitle: "Window 2"
        )
        
        store.record(context: context1, sourceID: "source.A", effectiveGranularity: .field)
        store.record(context: context2, sourceID: "source.B", effectiveGranularity: .window)
        
        var tree = store.buildHierarchyItems(granularityManager: granularityManager)
        guard let appNode = tree.first,
              let win1Node = appNode.children?.first(where: { $0.id == "win:\(appBundleID):\(win1ID)" }),
              let field1Node = win1Node.children?.first else {
            XCTFail("节点结构不完整")
            return
        }
        
        // 初始状态均为 unlocked
        XCTAssertEqual(appNode.lockStatus, .unlocked)
        XCTAssertEqual(win1Node.lockStatus, .unlocked)
        XCTAssertEqual(field1Node.lockStatus, .unlocked)
        
        // 1. 仅锁定窗口 win1Node
        store.toggleLock(for: win1Node)
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        let updatedWin1 = tree.first?.children?.first(where: { $0.id == win1Node.id })
        let updatedField1 = updatedWin1?.children?.first
        
        XCTAssertEqual(updatedWin1?.lockStatus, .locked(level: .window))
        XCTAssertEqual(updatedField1?.lockStatus, .inherited(from: .window), "窗口锁定后，下级输入框应当呈现继承窗口锁定")
        
        // 2. 解除窗口锁定，单独锁定输入框 field1
        store.toggleLock(for: win1Node) // unlock win1
        if let currentField = store.buildHierarchyItems(granularityManager: granularityManager).first?.children?.first?.children?.first {
            store.toggleLock(for: currentField)
        }
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        let fieldOnlyWin = tree.first?.children?.first(where: { $0.id == win1Node.id })
        let fieldOnlyField = fieldOnlyWin?.children?.first
        
        XCTAssertEqual(fieldOnlyWin?.lockStatus, .unlocked)
        XCTAssertEqual(fieldOnlyField?.lockStatus, .locked(level: .field), "独立锁定输入框时，状态应当为输入框级锁定")
        
        // 3. 锁定整个 App
        if let currentApp = tree.first {
            store.toggleLock(for: currentApp)
        }
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        let appLockedApp = tree.first
        let appLockedWin2 = appLockedApp?.children?.first(where: { $0.id == "win:\(appBundleID):\(win2ID)" })
        XCTAssertEqual(appLockedApp?.lockStatus, .locked(level: .app))
        XCTAssertEqual(appLockedWin2?.lockStatus, .inherited(from: .app), "App 锁定后，未显式锁定的窗口应当呈现继承应用锁定")
    }
    
    func testLockedItemsSortedAtTop() {
        let appA = "com.test.Alpha"
        let appB = "com.test.Beta"
        let appZ = "com.test.Zulu"
        
        let ctxA = FocusContext(bundleID: appA, appName: "Alpha", windowID: "win-a", windowTitle: "Win A")
        let ctxB = FocusContext(bundleID: appB, appName: "Beta", windowID: "win-b", windowTitle: "Win B")
        let ctxZ = FocusContext(bundleID: appZ, appName: "Zulu", windowID: "win-z", windowTitle: "Win Z")
        
        store.record(context: ctxA, sourceID: "s1", effectiveGranularity: .app)
        store.record(context: ctxB, sourceID: "s2", effectiveGranularity: .app)
        store.record(context: ctxZ, sourceID: "s3", effectiveGranularity: .app)
        
        // 锁定字母排序靠后的 Zulu
        var tree = store.buildHierarchyItems(granularityManager: granularityManager)
        if let zuluNode = tree.first(where: { $0.title == "Zulu" }) {
            store.toggleLock(for: zuluNode)
        }
        
        // 重新构建树，验证 Zulu 被置顶在最前面
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        XCTAssertEqual(tree.first?.title, "Zulu", "被锁定的 App 必须严格置顶排序在列表最上方")
        XCTAssertEqual(tree[1].title, "Alpha")
        XCTAssertEqual(tree[2].title, "Beta")
    }
}
