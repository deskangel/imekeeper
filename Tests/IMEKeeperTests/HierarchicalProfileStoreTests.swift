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
    
    func testIndependentSourceUpdatesAndParentInheritance() {
        let appBundleID = "com.apple.dt.Xcode"
        let window1ID = "win-main-1"
        let field1ID = "field-code-1"
        let sourceEnglish = "com.apple.keylayout.ABC"
        let sourceChinese = "com.apple.inputmethod.SCIM.ITABC"
        let sourceJapanese = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"
        
        let context1 = FocusContext(
            bundleID: appBundleID,
            appName: "Xcode",
            windowID: window1ID,
            windowTitle: "Main.swift",
            fieldID: field1ID,
            fieldDescription: "代码编辑器 1",
            role: "AXTextArea",
            isInputField: true
        )
        store.record(context: context1, sourceID: sourceEnglish, effectiveGranularity: .field)
        
        let tree = store.buildHierarchyItems(granularityManager: granularityManager)
        guard let appItem = tree.first,
              let winItem = appItem.children?.first,
              let fieldItem = winItem.children?.first else {
            XCTFail("应当成功构造大纲树")
            return
        }
        
        // 1. 在 Field 级别修改为日文：验证不覆盖所属 Window 与 App
        store.updateSource(for: fieldItem, newSourceID: sourceJapanese)
        XCTAssertEqual(store.queryPreferredSource(for: context1, effectiveGranularity: .field), sourceJapanese, "Field 自身应更新为日文")
        let treeAfterFieldUpdate = store.buildHierarchyItems(granularityManager: granularityManager)
        XCTAssertEqual(treeAfterFieldUpdate.first?.currentSourceID, sourceEnglish, "修改下级 Field 严禁覆盖上级 App")
        XCTAssertEqual(treeAfterFieldUpdate.first?.children?.first?.currentSourceID, sourceEnglish, "修改下级 Field 严禁覆盖上级 Window")
        
        // 2. 在 Window 级别修改为中文：验证不覆盖上级 App，亦不覆盖下级已有 Field
        store.updateSource(for: winItem, newSourceID: sourceChinese)
        let treeAfterWinUpdate = store.buildHierarchyItems(granularityManager: granularityManager)
        XCTAssertEqual(treeAfterWinUpdate.first?.currentSourceID, sourceEnglish, "修改 Window 严禁覆盖上级 App")
        XCTAssertEqual(treeAfterWinUpdate.first?.children?.first?.currentSourceID, sourceChinese, "Window 自身应更新为中文")
        XCTAssertEqual(treeAfterWinUpdate.first?.children?.first?.children?.first?.currentSourceID, sourceJapanese, "修改 Window 严禁覆盖下级已有 Field")
        
        // 3. 在 App 级别修改为日文：验证不覆盖已有的 Window 与 Field
        store.updateSource(for: appItem, newSourceID: sourceJapanese)
        let treeAfterAppUpdate = store.buildHierarchyItems(granularityManager: granularityManager)
        XCTAssertEqual(treeAfterAppUpdate.first?.currentSourceID, sourceJapanese, "App 自身应更新为日文")
        XCTAssertEqual(treeAfterAppUpdate.first?.children?.first?.currentSourceID, sourceChinese, "修改 App 严禁覆盖已有的 Window")
        XCTAssertEqual(treeAfterAppUpdate.first?.children?.first?.children?.first?.currentSourceID, sourceJapanese, "修改 App 严禁覆盖已有的 Field")
        
        // 4. 新创建的 Window：验证自动继承上级 App 当前设置 (sourceJapanese)
        let window2ID = "win-main-2"
        let contextNewWin = FocusContext(
            bundleID: appBundleID,
            appName: "Xcode",
            windowID: window2ID,
            windowTitle: "SecondWindow.swift",
            role: "AXWindow",
            isInputField: false
        )
        // 第一次查询新窗口，回退并继承 App 级偏好
        let newWinQueried = store.queryPreferredSource(for: contextNewWin, effectiveGranularity: .window)
        XCTAssertEqual(newWinQueried, sourceJapanese, "新创建的 Window 应继承上级 App 的当前设置")
        
        // 5. 新创建的 Field：验证自动继承所属 Window 当前设置 (sourceChinese)
        let field2ID = "field-search-new"
        let contextNewField = FocusContext(
            bundleID: appBundleID,
            appName: "Xcode",
            windowID: window1ID,
            windowTitle: "Main.swift",
            fieldID: field2ID,
            fieldDescription: "新搜索框",
            role: "AXSearchField",
            isInputField: true
        )
        let newFieldQueried = store.queryPreferredSource(for: contextNewField, effectiveGranularity: .field)
        XCTAssertEqual(newFieldQueried, sourceChinese, "新创建的 Field 应继承上级 Window 的当前设置")
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
    
    func testCleanSubItemsAtAppGranularityLevel() {
        let appBundleID = "com.apple.dt.Xcode"
        let win1ID = "win-main-1"
        let win2ID = "win-main-2"
        let field1ID = "field-editor"
        let sourceApp = "com.apple.keylayout.ABC"
        let sourceField = "com.apple.inputmethod.SCIM.ITABC"
        
        let ctx1 = FocusContext(
            bundleID: appBundleID,
            appName: "Xcode",
            windowID: win1ID,
            windowTitle: "MainWindow",
            fieldID: field1ID,
            fieldDescription: "Editor",
            role: "AXTextArea"
        )
        let ctx2 = FocusContext(
            bundleID: appBundleID,
            appName: "Xcode",
            windowID: win2ID,
            windowTitle: "SecondWindow"
        )
        
        // 记录输入框与多窗口数据
        store.record(context: ctx1, sourceID: sourceField, effectiveGranularity: .field)
        store.record(context: ctx2, sourceID: sourceApp, effectiveGranularity: .window)
        
        // 设置 Xcode 粒度为 .app
        granularityManager.setGranularity(for: appBundleID, level: .app)
        
        var tree = store.buildHierarchyItems(granularityManager: granularityManager)
        guard let appItem = tree.first else {
            XCTFail("应当成功构造 App 节点")
            return
        }
        
        XCTAssertEqual(appItem.children?.count, 2, "清理前应当存在 2 个窗口记录")
        XCTAssertTrue(appItem.canCleanSubItems, "在 .app 粒度下存在下级窗口时，应当允许清理")
        XCTAssertTrue(appItem.isCleanActionAvailable, ".app 粒度下清理按钮应处于可用状态")
        
        // 执行 .app 粒度下的清理
        store.cleanSubItems(for: appBundleID, granularity: .app)
        
        // 重新构建树验证
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        guard let cleanedAppItem = tree.first else {
            XCTFail("清理后 App 节点依然必须存在")
            return
        }
        
        XCTAssertNil(cleanedAppItem.children, "在 .app 粒度下清理后，所有下属窗口与输入框应被彻底清空")
        XCTAssertFalse(cleanedAppItem.canCleanSubItems, "清理完成后无下级冗余项，按钮应当置灰禁用")
        // 验证 App 自身输入法记忆不受影响
        XCTAssertEqual(cleanedAppItem.currentSourceID, sourceApp)
    }
    
    func testCleanSubItemsAtWindowGranularityLevel() {
        let appBundleID = "com.apple.Safari"
        let win1ID = "win-tab-1"
        let win2ID = "win-tab-2"
        let field1ID = "search-field"
        let field2ID = "address-field"
        
        let ctx1 = FocusContext(
            bundleID: appBundleID,
            appName: "Safari",
            windowID: win1ID,
            windowTitle: "Apple",
            fieldID: field1ID,
            fieldDescription: "Search",
            role: "AXTextField"
        )
        let ctx2 = FocusContext(
            bundleID: appBundleID,
            appName: "Safari",
            windowID: win2ID,
            windowTitle: "Google",
            fieldID: field2ID,
            fieldDescription: "Address",
            role: "AXTextField"
        )
        
        store.record(context: ctx1, sourceID: "com.apple.keylayout.ABC", effectiveGranularity: .field)
        store.record(context: ctx2, sourceID: "com.apple.inputmethod.SCIM.ITABC", effectiveGranularity: .field)
        
        // 设置 Safari 粒度为 .window
        granularityManager.setGranularity(for: appBundleID, level: .window)
        
        var tree = store.buildHierarchyItems(granularityManager: granularityManager)
        guard let appItem = tree.first else {
            XCTFail("应当成功构造 App 节点")
            return
        }
        
        XCTAssertEqual(appItem.children?.count, 2, "应当有 2 个窗口")
        XCTAssertEqual(appItem.children?.first?.children?.count, 1, "窗口 1 下应当有 1 个输入框")
        XCTAssertEqual(appItem.children?.last?.children?.count, 1, "窗口 2 下应当有 1 个输入框")
        XCTAssertTrue(appItem.canCleanSubItems, ".window 粒度下存在下级输入框，应当允许清理")
        
        // 执行 .window 粒度下的清理
        store.cleanSubItems(for: appBundleID, granularity: .window)
        
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        guard let cleanedAppItem = tree.first else {
            XCTFail("App 节点必须存在")
            return
        }
        
        // 窗口必须保留
        XCTAssertEqual(cleanedAppItem.children?.count, 2, "在 .window 粒度下清理后，窗口必须完整保留")
        // 但所有窗口下的输入框应全部清空
        XCTAssertNil(cleanedAppItem.children?.first?.children, "窗口 1 下的输入框应已被清空")
        XCTAssertNil(cleanedAppItem.children?.last?.children, "窗口 2 下的输入框应已被清空")
        XCTAssertFalse(cleanedAppItem.canCleanSubItems, "所有输入框清空后，App 的清理按钮应置灰禁用")
    }
    
    func testCleanSpecificWindowFields() {
        let appBundleID = "com.test.Editor"
        let win1ID = "win-1"
        let field1ID = "field-1"
        
        let ctx = FocusContext(
            bundleID: appBundleID,
            appName: "Editor",
            windowID: win1ID,
            windowTitle: "Document",
            fieldID: field1ID,
            fieldDescription: "Body",
            role: "AXTextArea"
        )
        store.record(context: ctx, sourceID: "com.apple.keylayout.ABC", effectiveGranularity: .field)
        
        var tree = store.buildHierarchyItems(granularityManager: granularityManager)
        guard let winItem = tree.first?.children?.first else {
            XCTFail("应当存在窗口项")
            return
        }
        
        XCTAssertTrue(winItem.canCleanSubItems, "窗口存在输入框时应可清理")
        XCTAssertEqual(winItem.children?.count, 1)
        
        // 单独清理该窗口下的输入框
        store.cleanFields(for: appBundleID, windowID: win1ID)
        
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        guard let updatedWin = tree.first?.children?.first else {
            XCTFail("窗口项仍应存在")
            return
        }
        XCTAssertNil(updatedWin.children, "窗口输入框已被清空")
        XCTAssertFalse(updatedWin.canCleanSubItems, "输入框已清空，不可再次清理")
    }
    
    func testCleanAllRedundantSubItemsAcrossApps() {
        let appA = "com.apple.Terminal" // will be .app
        let appB = "com.apple.Safari"   // will be .window
        let appC = "com.apple.Notes"    // will be .field
        
        let ctxA = FocusContext(bundleID: appA, appName: "Terminal", windowID: "win-term", windowTitle: "term", fieldID: "field-term")
        let ctxB = FocusContext(bundleID: appB, appName: "Safari", windowID: "win-safari", windowTitle: "safari", fieldID: "field-safari")
        let ctxC = FocusContext(bundleID: appC, appName: "Notes", windowID: "win-notes", windowTitle: "notes", fieldID: "field-notes")
        
        store.record(context: ctxA, sourceID: "s1", effectiveGranularity: .field)
        store.record(context: ctxB, sourceID: "s2", effectiveGranularity: .field)
        store.record(context: ctxC, sourceID: "s3", effectiveGranularity: .field)
        
        granularityManager.setGranularity(for: appA, level: .app)
        granularityManager.setGranularity(for: appB, level: .window)
        granularityManager.setGranularity(for: appC, level: .field)
        
        XCTAssertTrue(store.hasAnyRedundantSubItems(granularityManager: granularityManager))
        
        // 全局清理所有冗余
        store.cleanAllRedundantSubItems(granularityManager: granularityManager)
        
        let tree = store.buildHierarchyItems(granularityManager: granularityManager)
        let itemA = tree.first(where: { $0.id == "app:\(appA)" })
        let itemB = tree.first(where: { $0.id == "app:\(appB)" })
        let itemC = tree.first(where: { $0.id == "app:\(appC)" })
        
        // appA (.app 粒度): 窗口和输入框全部清空
        XCTAssertNil(itemA?.children)
        // appB (.window 粒度): 窗口保留，但输入框清空
        XCTAssertEqual(itemB?.children?.count, 1)
        XCTAssertNil(itemB?.children?.first?.children)
        // appC (.field 粒度): 窗口与输入框均完整保留
        XCTAssertEqual(itemC?.children?.count, 1)
        XCTAssertEqual(itemC?.children?.first?.children?.count, 1)
        
        XCTAssertFalse(store.hasAnyRedundantSubItems(granularityManager: granularityManager))
    }
}
