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
        
        // 2. 在同一 App 内聚焦全新的输入框 field-search (尚未被记录)
        let context2 = FocusContext(
            bundleID: appBundleID,
            appName: "Xcode",
            windowID: windowID,
            windowTitle: "Project.swift",
            fieldID: field2ID,
            fieldDescription: "搜索框",
            role: "AXSearchField"
        )
        
        // 验证：未记录的全新输入框默认继承该应用最后使用的输入法 (即英文)
        let result2 = store.queryPreferredSource(for: context2, effectiveGranularity: .field)
        XCTAssertEqual(result2, sourceEnglish, "全新输入框应当自动继承该应用最后一次记录的输入法")
        
        // 3. 用户在 field-search 中手动切换为中文并记录
        store.record(context: context2, sourceID: sourceChinese, effectiveGranularity: .field)
        
        // 再次查询两个输入框，验证彼此独立并分别记忆
        XCTAssertEqual(store.queryPreferredSource(for: context1, effectiveGranularity: .field), sourceEnglish)
        XCTAssertEqual(store.queryPreferredSource(for: context2, effectiveGranularity: .field), sourceChinese)
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
        
        // 构造树结构：App -> [Field]
        let tree = store.buildHierarchyItems(granularityManager: granularityManager)
        XCTAssertEqual(tree.count, 1)
        XCTAssertEqual(tree.first?.children?.count, 1)
        
        // 修改输入法
        if let fieldItem = tree.first?.children?.first {
            store.updateSource(for: fieldItem, newSourceID: "com.apple.inputmethod.SCIM.ITABC")
            let updated = store.queryPreferredSource(for: context, effectiveGranularity: .field)
            XCTAssertEqual(updated, "com.apple.inputmethod.SCIM.ITABC")
            
            // 删除该节点
            store.delete(item: fieldItem)
            let afterDelete = store.buildHierarchyItems(granularityManager: granularityManager)
            XCTAssertEqual(afterDelete.first?.children?.count ?? 0, 0)
        } else {
            XCTFail("应当成功构造两级树节点")
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
              let fieldItem = appItem.children?.first else {
            XCTFail("应当成功构造大纲树")
            return
        }
        
        // 1. 在 Field 级别修改为日文：验证不覆盖所属 App
        store.updateSource(for: fieldItem, newSourceID: sourceJapanese)
        XCTAssertEqual(store.queryPreferredSource(for: context1, effectiveGranularity: .field), sourceJapanese, "Field 自身应更新为日文")
        let treeAfterFieldUpdate = store.buildHierarchyItems(granularityManager: granularityManager)
        XCTAssertEqual(treeAfterFieldUpdate.first?.currentSourceID, sourceEnglish, "修改下级 Field 严禁覆盖上级 App")
        
        // 2. 在 App 级别修改为中文：验证不覆盖已有的 Field
        store.updateSource(for: appItem, newSourceID: sourceChinese)
        let treeAfterAppUpdate = store.buildHierarchyItems(granularityManager: granularityManager)
        XCTAssertEqual(treeAfterAppUpdate.first?.currentSourceID, sourceChinese, "App 自身应更新为中文")
        XCTAssertEqual(treeAfterAppUpdate.first?.children?.first?.currentSourceID, sourceJapanese, "修改 App 严禁覆盖已有的 Field")
        
        // 3. 新创建的 Field：验证自动继承 App 当前设置 (sourceChinese)
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
        XCTAssertEqual(newFieldQueried, sourceChinese, "新创建的 Field 应继承上级 App 的当前设置")
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
        XCTAssertTrue(store.isContextLocked(for: context, effectiveGranularity: .field))
        
        // 2. 模拟临时手动切换输入法为中文并尝试 record 记录
        store.record(context: context, sourceID: sourceChinese, effectiveGranularity: .app)
        
        // 3. 验证被锁定后，App 级输入法未被冲掉，依然保持英文
        let queryResult = store.queryPreferredSource(for: context, effectiveGranularity: .app)
        XCTAssertEqual(queryResult, sourceEnglish, "App 锁定后，临时切换输入法绝不覆盖记忆设置")
    }
    
    func testTwoDistinctLockLevelsAndInheritance() {
        let appBundleID = "com.test.Editor"
        let winID = "win-1"
        let field1ID = "field-1"
        let field2ID = "field-2"
        
        let context1 = FocusContext(
            bundleID: appBundleID,
            appName: "Editor",
            windowID: winID,
            windowTitle: "Window 1",
            fieldID: field1ID,
            fieldDescription: "Input 1",
            role: "AXTextField"
        )
        let context2 = FocusContext(
            bundleID: appBundleID,
            appName: "Editor",
            windowID: winID,
            windowTitle: "Window 1",
            fieldID: field2ID,
            fieldDescription: "Input 2",
            role: "AXTextField"
        )
        
        store.record(context: context1, sourceID: "source.A", effectiveGranularity: .field)
        store.record(context: context2, sourceID: "source.B", effectiveGranularity: .field)
        
        var tree = store.buildHierarchyItems(granularityManager: granularityManager)
        guard let appNode = tree.first,
              let field1Node = appNode.children?.first(where: { $0.id == "field:\(appBundleID):\(field1ID)" }),
              let field2Node = appNode.children?.first(where: { $0.id == "field:\(appBundleID):\(field2ID)" }) else {
            XCTFail("节点结构不完整")
            return
        }
        
        // 初始状态均为 unlocked
        XCTAssertEqual(appNode.lockStatus, .unlocked)
        XCTAssertEqual(field1Node.lockStatus, .unlocked)
        XCTAssertEqual(field2Node.lockStatus, .unlocked)
        
        // 1. 仅锁定输入框 field1Node
        store.toggleLock(for: field1Node)
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        let updatedApp = tree.first
        let updatedField1 = updatedApp?.children?.first(where: { $0.id == field1Node.id })
        let updatedField2 = updatedApp?.children?.first(where: { $0.id == field2Node.id })
        
        XCTAssertEqual(updatedApp?.lockStatus, .unlocked)
        XCTAssertEqual(updatedField1?.lockStatus, .locked(level: .field))
        XCTAssertEqual(updatedField2?.lockStatus, .unlocked)
        
        // 2. 锁定整个 App
        store.toggleLock(for: updatedApp!)
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        let appLockedApp = tree.first
        let appLockedField1 = appLockedApp?.children?.first(where: { $0.id == field1Node.id })
        let appLockedField2 = appLockedApp?.children?.first(where: { $0.id == field2Node.id })
        
        XCTAssertEqual(appLockedApp?.lockStatus, .locked(level: .app))
        // 显式锁定的 field1 保持 field 级锁定
        XCTAssertEqual(appLockedField1?.lockStatus, .locked(level: .field))
        // 未显式锁定的 field2 呈现继承应用锁定
        XCTAssertEqual(appLockedField2?.lockStatus, .inherited(from: .app), "App 锁定后，未显式锁定的输入框应当呈现继承应用锁定")
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
        let field1ID = "field-editor"
        let field2ID = "field-search"
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
            windowID: win1ID,
            windowTitle: "MainWindow",
            fieldID: field2ID,
            fieldDescription: "Search",
            role: "AXSearchField"
        )
        
        // 记录多个输入框
        let ctxApp = FocusContext(bundleID: appBundleID, appName: "Xcode", windowID: win1ID, windowTitle: "MainWindow", isInputField: false)
        store.record(context: ctxApp, sourceID: sourceApp, effectiveGranularity: .app)
        store.record(context: ctx1, sourceID: sourceField, effectiveGranularity: .field)
        store.record(context: ctx2, sourceID: sourceField, effectiveGranularity: .field)
        
        // 设置 Xcode 粒度为 .app
        granularityManager.setGranularity(for: appBundleID, level: .app)
        
        var tree = store.buildHierarchyItems(granularityManager: granularityManager)
        guard let appItem = tree.first else {
            XCTFail("应当成功构造 App 节点")
            return
        }
        
        XCTAssertEqual(appItem.children?.count, 2, "清理前应当存在 2 个输入框记录")
        XCTAssertTrue(appItem.canCleanSubItems, "在 .app 粒度下存在下级输入框时，应当允许清理")
        XCTAssertTrue(appItem.isCleanActionAvailable, ".app 粒度下清理按钮应处于可用状态")
        
        // 执行 .app 粒度下的清理
        store.cleanSubItems(for: appBundleID, granularity: .app)
        
        // 重新构建树验证
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        guard let cleanedAppItem = tree.first else {
            XCTFail("清理后 App 节点依然必须存在")
            return
        }
        
        XCTAssertNil(cleanedAppItem.children, "在 .app 粒度下清理后，所有下属输入框应被彻底清空")
        XCTAssertFalse(cleanedAppItem.canCleanSubItems, "清理完成后无下级冗余项，按钮应当置灰禁用")
        // 验证 App 自身输入法记忆不受影响
        XCTAssertEqual(cleanedAppItem.currentSourceID, sourceApp)
    }
    
    func testCleanSubItemsAtFieldGranularityLevelPreservesLockedFields() {
        let appBundleID = "com.apple.Safari"
        let field1ID = "field-search"
        let field2ID = "field-comment"
        
        let ctx1 = FocusContext(
            bundleID: appBundleID,
            appName: "Safari",
            windowID: "win-1",
            windowTitle: "Tab 1",
            fieldID: field1ID,
            fieldDescription: "Search"
        )
        let ctx2 = FocusContext(
            bundleID: appBundleID,
            appName: "Safari",
            windowID: "win-1",
            windowTitle: "Tab 1",
            fieldID: field2ID,
            fieldDescription: "Comment"
        )
        
        store.record(context: ctx1, sourceID: "com.apple.keylayout.US", effectiveGranularity: .field)
        store.record(context: ctx2, sourceID: "com.apple.inputmethod.SCIM.ITABC", effectiveGranularity: .field)
        
        // 锁定 field1
        var tree = store.buildHierarchyItems(granularityManager: granularityManager)
        let appItem = tree.first!
        let field1Item = appItem.children!.first(where: { $0.id.contains(field1ID) })!
        store.toggleLock(for: field1Item)
        
        granularityManager.setGranularity(for: appBundleID, level: .field)
        
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        let targetAppItem = tree.first!
        XCTAssertEqual(targetAppItem.children?.count, 2, "清理前应有 2 个输入框")
        XCTAssertTrue(targetAppItem.canCleanSubItems, "在 .field 粒度下存在未锁定的输入框时，允许清理")
        
        // 执行 .field 粒度下的清理
        store.cleanSubItems(for: appBundleID, granularity: .field)
        
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        let cleanedAppItem = tree.first!
        XCTAssertEqual(cleanedAppItem.children?.count, 1, "清理后应仅保留 1 个锁定的输入框")
        XCTAssertEqual(cleanedAppItem.children?.first?.id, "field:\(appBundleID):\(field1ID)")
        XCTAssertTrue(cleanedAppItem.children!.first!.isLocked, "保留的输入框必须是锁定状态")
        XCTAssertFalse(cleanedAppItem.canCleanSubItems, "已无任何未锁定输入框，清理按钮应当置灰禁用")
    }
    
    func testLockedAppProtectsSubItemsFromCleaning() {
        let appBundleID = "com.apple.Xcode"
        let ctx = FocusContext(
            bundleID: appBundleID,
            appName: "Xcode",
            windowID: "win-1",
            windowTitle: "Main",
            fieldID: "editor",
            fieldDescription: "Code"
        )
        store.record(context: ctx, sourceID: "com.apple.keylayout.US", effectiveGranularity: .field)
        granularityManager.setGranularity(for: appBundleID, level: .app)
        
        var tree = store.buildHierarchyItems(granularityManager: granularityManager)
        var appItem = tree.first!
        XCTAssertTrue(appItem.canCleanSubItems)
        
        // 锁定该 App
        store.toggleLock(for: appItem)
        
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        appItem = tree.first!
        XCTAssertTrue(appItem.isLocked)
        XCTAssertFalse(appItem.canCleanSubItems, "App 锁定状态下，下级输入框受保护，清理按钮必须置灰禁用")
        
        // 尝试执行清理：预期无操作，受锁定保护
        store.cleanSubItems(for: appBundleID, granularity: .app)
        
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        let protectedApp = tree.first!
        XCTAssertEqual(protectedApp.children?.count, 1, "App 锁定状态下，cleanSubItems 不得删除其下级输入框")
        
        // 解锁后再次执行清理
        store.toggleLock(for: protectedApp)
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        let unlockedApp = tree.first!
        XCTAssertTrue(unlockedApp.canCleanSubItems, "解锁后按钮恢复可用")
        store.cleanSubItems(for: appBundleID, granularity: .app)
        
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        XCTAssertNil(tree.first?.children, "解锁后清理成功清空下级输入框")
    }
    
    func testCleanAllRedundantSubItemsAcrossApps() {
        let appA = "com.apple.Terminal" // .app, unlocked
        let appB = "com.apple.Xcode"    // .app, locked
        let appC = "com.apple.Notes"    // .field, unlocked, has 1 locked field & 1 unlocked field
        
        let ctxA = FocusContext(bundleID: appA, appName: "Terminal", windowID: "win-term", windowTitle: "term", fieldID: "field-term")
        let ctxB = FocusContext(bundleID: appB, appName: "Xcode", windowID: "win-xc", windowTitle: "xc", fieldID: "field-xc")
        let ctxC1 = FocusContext(bundleID: appC, appName: "Notes", windowID: "win-notes", windowTitle: "notes", fieldID: "field-notes-1")
        let ctxC2 = FocusContext(bundleID: appC, appName: "Notes", windowID: "win-notes", windowTitle: "notes", fieldID: "field-notes-2")
        
        store.record(context: ctxA, sourceID: "s1", effectiveGranularity: .field)
        store.record(context: ctxB, sourceID: "s2", effectiveGranularity: .field)
        store.record(context: ctxC1, sourceID: "s3", effectiveGranularity: .field)
        store.record(context: ctxC2, sourceID: "s4", effectiveGranularity: .field)
        
        granularityManager.setGranularity(for: appA, level: .app)
        granularityManager.setGranularity(for: appB, level: .app)
        granularityManager.setGranularity(for: appC, level: .field)
        
        var tree = store.buildHierarchyItems(granularityManager: granularityManager)
        // 锁定 appB
        let itemB = tree.first(where: { $0.id == "app:\(appB)" })!
        store.toggleLock(for: itemB)
        
        // 锁定 appC 下的 field-notes-1
        let itemC = tree.first(where: { $0.id == "app:\(appC)" })!
        let fieldC1 = itemC.children!.first(where: { $0.id.contains("field-notes-1") })!
        store.toggleLock(for: fieldC1)
        
        XCTAssertTrue(store.hasAnyRedundantSubItems(granularityManager: granularityManager), "存在可清理项时全局检查应为 true")
        
        // 全局清理所有应用
        store.cleanAllRedundantSubItems(granularityManager: granularityManager)
        
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        let cleanedA = tree.first(where: { $0.id == "app:\(appA)" })
        let cleanedB = tree.first(where: { $0.id == "app:\(appB)" })
        let cleanedC = tree.first(where: { $0.id == "app:\(appC)" })
        
        // appA (.app 粒度, 未锁定): 输入框全部清空
        XCTAssertNil(cleanedA?.children)
        // appB (.app 粒度, 已锁定): 输入框受保护完整保留
        XCTAssertEqual(cleanedB?.children?.count, 1)
        // appC (.field 粒度, 未锁定): 仅保留锁定的 field-notes-1
        XCTAssertEqual(cleanedC?.children?.count, 1)
        XCTAssertEqual(cleanedC?.children?.first?.id, "field:\(appC):field-notes-1")
        
        // 全局可清理项已全部打扫完毕
        XCTAssertFalse(store.hasAnyRedundantSubItems(granularityManager: granularityManager))
    }
    
    func testLegacyProfileMigrationFromDisk() throws {
        // 模拟旧版本包含 "windows" 嵌套的 JSON 数据
        let legacyJSON = """
        {
          "com.legacy.app": {
            "id": "com.legacy.app",
            "appName": "LegacyApp",
            "lastSourceID": "com.apple.keylayout.US",
            "isLocked": false,
            "windows": {
              "win-1": {
                "id": "win-1",
                "windowTitle": "Window 1",
                "lastSourceID": "com.apple.keylayout.US",
                "isLocked": false,
                "fields": {
                  "field-alpha": {
                    "id": "field-alpha",
                    "fieldIdentifier": "Editor",
                    "role": "AXTextArea",
                    "sourceID": "com.apple.inputmethod.SCIM.ITABC",
                    "isLocked": true
                  }
                }
              }
            }
          }
        }
        """
        
        let migrationURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_legacy_migration_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: migrationURL) }
        
        try legacyJSON.data(using: .utf8)!.write(to: migrationURL)
        
        // 实例化 Store 加载
        let store = HierarchicalProfileStore(customStorageURL: migrationURL)
        let tree = store.buildHierarchyItems(granularityManager: granularityManager)
        
        XCTAssertEqual(tree.count, 1)
        let appItem = tree.first!
        XCTAssertEqual(appItem.title, "LegacyApp")
        XCTAssertEqual(appItem.children?.count, 1, "旧窗口下的 field-alpha 应当被平滑升级迁移到 App.fields 中")
        let fieldItem = appItem.children!.first!
        XCTAssertEqual(fieldItem.id, "field:com.legacy.app:field-alpha")
        XCTAssertEqual(fieldItem.currentSourceID, "com.apple.inputmethod.SCIM.ITABC")
        XCTAssertTrue(fieldItem.isLocked)
        
        // 执行修改或保存后检查持久化磁盘文件，验证已无 "windows" 键
        store.record(context: FocusContext(bundleID: "com.legacy.app", appName: "LegacyApp", windowID: "win-1", windowTitle: "Win", fieldID: "field-beta"), sourceID: "com.apple.keylayout.US", effectiveGranularity: .field)
        
        let savedData = try Data(contentsOf: migrationURL)
        let savedJSONString = String(data: savedData, encoding: .utf8)!
        XCTAssertFalse(savedJSONString.contains("\"windows\""), "重新保存后必须彻底清理 windows 层级，不留旧字段")
        XCTAssertTrue(savedJSONString.contains("\"fields\""), "必须采用纯净的 fields 字典")
    }
    
    func testRenameFieldProfileAndPersistence() throws {
        let appBundleID = "com.antigravity.test.rename"
        let fieldID = "abcdef1234567890"
        let context = FocusContext(
            bundleID: appBundleID,
            appName: "RenameApp",
            windowID: "win-rename",
            windowTitle: "MainWindow",
            fieldID: fieldID,
            fieldDescription: "Original Name",
            role: "AXTextField"
        )
        
        // 1. 初次记录
        store.record(context: context, sourceID: "com.apple.keylayout.US", effectiveGranularity: .field)
        
        var tree = store.buildHierarchyItems(granularityManager: granularityManager)
        let originalFieldItem = tree.first?.children?.first(where: { $0.id == "field:\(appBundleID):\(fieldID)" })
        XCTAssertEqual(originalFieldItem?.title, "Original Name")
        XCTAssertEqual(originalFieldItem?.hashSubtitle, L10n.fieldHashSubtitle(hashPrefix: "abcdef12"))
        
        // 2. 重命名
        store.renameField(bundleID: appBundleID, fieldID: fieldID, newName: "Custom Renamed Title")
        
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        let renamedFieldItem = tree.first?.children?.first(where: { $0.id == "field:\(appBundleID):\(fieldID)" })
        XCTAssertEqual(renamedFieldItem?.title, "Custom Renamed Title")
        XCTAssertEqual(renamedFieldItem?.hashSubtitle, L10n.fieldHashSubtitle(hashPrefix: "abcdef12"))
        
        // 3. 再次获取焦点并 record，验证自定义名称不被原始探测名冲掉
        store.record(context: context, sourceID: "com.apple.keylayout.US", effectiveGranularity: .field)
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        let preservedFieldItem = tree.first?.children?.first(where: { $0.id == "field:\(appBundleID):\(fieldID)" })
        XCTAssertEqual(preservedFieldItem?.title, "Custom Renamed Title", "再次聚焦录入不应冲掉用户自定义重命名")
        
        // 4. 从磁盘重新加载验证持久化
        let reloadedStore = HierarchicalProfileStore(customStorageURL: tempURL)
        let reloadedTree = reloadedStore.buildHierarchyItems(granularityManager: granularityManager)
        let persistedFieldItem = reloadedTree.first?.children?.first(where: { $0.id == "field:\(appBundleID):\(fieldID)" })
        XCTAssertEqual(persistedFieldItem?.title, "Custom Renamed Title", "重命名在持久化重载后必须完整保留")
    }
    
    func testLockedAppDoesNotAddNewFieldsAtFieldGranularity() {
        let appBundleID = "com.microsoft.VSCode"
        let terminalFieldID = "vscode-terminal-input"
        let newSearchFieldID = "vscode-search-widget"
        let defaultAppSource = "com.apple.keylayout.ABC"
        let terminalSource = "com.apple.keylayout.US"
        
        let ctxTerminal = FocusContext(
            bundleID: appBundleID,
            appName: "Code",
            windowID: "win-workspace",
            windowTitle: "Workspace",
            fieldID: terminalFieldID,
            fieldDescription: "终端输入区",
            role: "AXTextField",
            isInputField: true
        )
        
        let ctxNewSearch = FocusContext(
            bundleID: appBundleID,
            appName: "Code",
            windowID: "win-workspace",
            windowTitle: "Workspace",
            fieldID: newSearchFieldID,
            fieldDescription: "全局搜索框",
            role: "AXSearchField",
            isInputField: true
        )
        
        // 1. 初次记录常用输入框（例如终端）并锁定该输入框
        store.record(context: ctxTerminal, sourceID: terminalSource, effectiveGranularity: .field)
        var tree = store.buildHierarchyItems(granularityManager: granularityManager)
        guard let appItem = tree.first,
              let terminalItem = appItem.children?.first(where: { $0.id == "field:\(appBundleID):\(terminalFieldID)" }) else {
            XCTFail("应当成功构造大纲树")
            return
        }
        store.toggleLock(for: terminalItem)
        
        // 2. 将应用设置为锁定状态
        store.toggleLock(for: appItem)
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        XCTAssertEqual(tree.first?.lockStatus, .locked(level: .app), "应用必须处于锁定状态")
        
        // 3. 验证当应用被锁定后，新输入框在 field 粒度下绝不自动收录
        let shouldAutoRecord = store.shouldAutoRecordContext(ctxNewSearch, effectiveGranularity: .field)
        XCTAssertFalse(shouldAutoRecord, "App 锁定后，处于 field 粒度也不再自动收录新 field，防止记录暴涨")
        
        // 4. 尝试执行 record 录入新输入框，验证其不会被添加到 fields 集合中
        store.record(context: ctxNewSearch, sourceID: "com.apple.inputmethod.SCIM.ITABC", effectiveGranularity: .field)
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        let updatedAppItem = tree.first
        XCTAssertEqual(updatedAppItem?.children?.count, 1, "App 锁定后，新输入框绝不被添加进 fields 字典中")
        XCTAssertEqual(updatedAppItem?.children?.first?.id, "field:\(appBundleID):\(terminalFieldID)")
        
        // 5. 验证新输入框平稳降级使用 App 的基准偏好输入法，已有输入框不受影响
        let newFieldPreferred = store.queryPreferredSource(for: ctxNewSearch, effectiveGranularity: .field)
        XCTAssertEqual(newFieldPreferred, terminalSource, "未收录的新输入框降级使用应用基准输入法")
        let terminalPreferred = store.queryPreferredSource(for: ctxTerminal, effectiveGranularity: .field)
        XCTAssertEqual(terminalPreferred, terminalSource, "已有锁定的常用输入框偏好完好保留")
        
        // 6. 解锁应用后，新输入框恢复正常自动收录与创建能力
        store.toggleLock(for: updatedAppItem!)
        let shouldAutoRecordAfterUnlock = store.shouldAutoRecordContext(ctxNewSearch, effectiveGranularity: .field)
        XCTAssertTrue(shouldAutoRecordAfterUnlock, "应用解锁后，新输入框恢复允许自动收录")
        store.record(context: ctxNewSearch, sourceID: "com.apple.inputmethod.SCIM.ITABC", effectiveGranularity: .field)
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        XCTAssertEqual(tree.first?.children?.count, 2, "应用解锁后，新输入框能够正常记录")
    }
    
    func testFieldLevelDoesNotOverwriteAppLevelPreferenceAndFallsBackProperly() {
        let appBundleID = "com.google.antigravity"
        let windowID = "win-editor"
        let fieldID = "field-editor-textarea"
        let sourceEnglish = "com.apple.keylayout.ABC"
        let sourceChinese = "com.apple.inputmethod.SCIM.ITABC"
        
        // 1. 初始化 App 级别偏好为中文
        let appOnlyContext = FocusContext(
            bundleID: appBundleID,
            appName: "Antigravity",
            windowID: windowID,
            windowTitle: "Workspace — Antigravity",
            fieldID: nil,
            fieldDescription: nil,
            role: "AXWindow",
            isInputField: false
        )
        store.record(context: appOnlyContext, sourceID: sourceChinese, effectiveGranularity: .app)
        
        let initialAppQueried = store.queryPreferredSource(for: appOnlyContext, effectiveGranularity: .field)
        XCTAssertEqual(initialAppQueried, sourceChinese, "App 初始记录应当为中文")
        
        // 2. 在 field 粒度下聚焦 AXTextArea 输入框并设定为英文
        let fieldContext = FocusContext(
            bundleID: appBundleID,
            appName: "Antigravity",
            windowID: windowID,
            windowTitle: "Workspace — Antigravity",
            fieldID: fieldID,
            fieldDescription: "多行文本区 (AXTextArea)",
            role: "AXTextArea",
            isInputField: true
        )
        store.record(context: fieldContext, sourceID: sourceEnglish, effectiveGranularity: .field)
        
        // 验证 Field 自身查询为英文
        let fieldQueried = store.queryPreferredSource(for: fieldContext, effectiveGranularity: .field)
        XCTAssertEqual(fieldQueried, sourceEnglish, "AXTextArea 应当记录并查询出英文")
        
        // 3. 关键验证：记录 Field 英文后，App 级基准偏好严禁被覆盖为英文，必须维持中文
        let appAfterFieldRecord = store.queryPreferredSource(for: appOnlyContext, effectiveGranularity: .field)
        XCTAssertEqual(appAfterFieldRecord, sourceChinese, "记录下级 Field 严禁污染上级 App 偏好")
        
        let tree = store.buildHierarchyItems(granularityManager: granularityManager)
        XCTAssertEqual(tree.first?.currentSourceID, sourceChinese, "树状大纲中 App 的输入法必须保持为中文")
        XCTAssertEqual(tree.first?.children?.first?.currentSourceID, sourceEnglish, "树状大纲中 Field 的输入法必须保持为英文")
    }
    
    func testAntigravityFieldLevelChineseWithAppUSPreferenceAndNonInputSwitch() {
        let appBundleID = "com.google.antigravity"
        let windowID = "win-antigravity-1"
        let fieldID = "field-antigravity-textarea"
        let sourceUS = AppConstants.InputSource.primaryUSSourceID
        let sourceChinese = "com.apple.inputmethod.SCIM.ITABC"
        
        // 1. 设置粒度为 .field
        granularityManager.setGranularity(for: appBundleID, level: .field)
        
        // 2. 模拟 App 级与 Field 级分别记录
        let appOnlyContext = FocusContext(
            bundleID: appBundleID,
            appName: "Antigravity",
            windowID: windowID,
            windowTitle: "Antigravity",
            isInputField: false
        )
        store.record(context: appOnlyContext, sourceID: sourceUS, effectiveGranularity: .app)
        
        let fieldContext = FocusContext(
            bundleID: appBundleID,
            appName: "Antigravity",
            windowID: windowID,
            windowTitle: "Antigravity",
            fieldID: fieldID,
            fieldDescription: "AXTextArea",
            role: "AXTextArea",
            isInputField: true
        )
        store.record(context: fieldContext, sourceID: sourceChinese, effectiveGranularity: .field)
        
        // 3. 模拟用户在设置面板分别设置与锁定 App 级（美国）与 Field 级（中文）
        var tree = store.buildHierarchyItems(granularityManager: granularityManager)
        let appItem = tree.first(where: { $0.id.contains(appBundleID) })!
        store.updateSource(for: appItem, newSourceID: sourceUS)
        store.toggleLock(for: appItem)
        
        tree = store.buildHierarchyItems(granularityManager: granularityManager)
        let reloadedAppItem = tree.first(where: { $0.id.contains(appBundleID) })!
        let fieldItem = reloadedAppItem.children!.first(where: { $0.id.contains(fieldID) })!
        store.updateSource(for: fieldItem, newSourceID: sourceChinese)
        
        // 4. 验证输入框内查询为中文
        let queryInField = store.queryPreferredSource(for: fieldContext, effectiveGranularity: .field)
        XCTAssertEqual(queryInField, sourceChinese, "输入框内应当生效中文偏好")
        
        // 5. 焦点离开输入框（点击非输入区，isInputField: false）
        let nonInputContext = FocusContext(
            bundleID: appBundleID,
            appName: "Antigravity",
            windowID: windowID,
            windowTitle: "Antigravity",
            isInputField: false
        )
        let queryNonInput = store.queryPreferredSource(for: nonInputContext, effectiveGranularity: .field)
        XCTAssertEqual(queryNonInput, sourceUS, "焦点移至非输入区时，应当回退并生效 App 级的 US 偏好")
    }
    
    func testInputSourceModelFollowsSystemLocalizedName() {
        // 场景 1: 系统全局为英文（系统输入法菜单显示 "U.S."），即使用户在 IME Keeper 中设置 App 语言为中文，输入法名称依然必须显示为 "U.S."
        let nameInEnglishSystem = AppConstants.InputSource.resolveNameAlignedWithSystemLanguage(
            sourceID: AppConstants.InputSource.primaryUSSourceID,
            defaultName: "U.S.",
            simulatedSystemLanguageIsChinese: false
        )
        XCTAssertEqual(nameInEnglishSystem, "U.S.", "系统为英文时，输入法名称必须跟随系统显示为 U.S.，不受 App 语言干扰")
        
        // 场景 2: 系统全局为中文（系统输入法菜单显示 "美国"），即使用户在 IME Keeper 中设置 App 语言为英文，输入法名称依然必须显示为 "美国"
        let nameInChineseSystem = AppConstants.InputSource.resolveNameAlignedWithSystemLanguage(
            sourceID: AppConstants.InputSource.primaryUSSourceID,
            defaultName: "美国",
            simulatedSystemLanguageIsChinese: true
        )
        XCTAssertEqual(nameInChineseSystem, "美国", "系统为中文时，输入法名称必须跟随系统显示为'美国'，不受 App 语言干扰")
        
        // 场景 3: 简体双拼在英文系统下显示 "Shuangpin – Simplified"，在中文系统下显示 "简体双拼"
        let shuangpinEnglish = AppConstants.InputSource.resolveNameAlignedWithSystemLanguage(
            sourceID: "com.apple.inputmethod.SCIM.Shuangpin",
            defaultName: "Shuangpin – Simplified",
            simulatedSystemLanguageIsChinese: false
        )
        XCTAssertEqual(shuangpinEnglish, "Shuangpin – Simplified")
        
        let shuangpinChinese = AppConstants.InputSource.resolveNameAlignedWithSystemLanguage(
            sourceID: "com.apple.inputmethod.SCIM.Shuangpin",
            defaultName: "简体双拼",
            simulatedSystemLanguageIsChinese: true
        )
        XCTAssertEqual(shuangpinChinese, "简体双拼")
    }
}
