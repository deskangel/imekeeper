import Foundation

/// 树状层级输入法记忆与回退解析引擎
public final class HierarchicalProfileStore: @unchecked Sendable {
    
    private let lock = NSLock()
    private var profiles: [String: AppProfile] = [:]
    private let storageURL: URL
    
    public init(customStorageURL: URL? = nil) {
        if let customURL = customStorageURL {
            self.storageURL = customURL
        } else {
            let fileManager = FileManager.default
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let folderURL = appSupport.appendingPathComponent(AppConstants.Storage.appSupportFolderName, isDirectory: true)
            try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            self.storageURL = folderURL.appendingPathComponent(AppConstants.Storage.profileStorageFileName)
        }
        loadFromDisk()
    }
    
    // MARK: - Query & Lookup
    
    /// 根据当前焦点上下文与生效粒度，解析出应使用的历史输入法
    /// - Parameters:
    ///   - context: 焦点上下文
    ///   - effectiveGranularity: 当前生效的粒度控制
    /// - Returns: 记忆的目标输入法 ID，若没有任何历史记录则返回 nil
    public func queryPreferredSource(
        for context: FocusContext,
        effectiveGranularity: GranularityLevel
    ) -> String? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let appProfile = profiles[context.bundleID] else {
            return nil
        }
        
        switch effectiveGranularity {
        case .app:
            return appProfile.lastSourceID
            
        case .window:
            if let windowProfile = appProfile.windows[context.windowID] {
                return windowProfile.lastSourceID
            }
            return appProfile.lastSourceID
            
        case .field:
            if let windowProfile = appProfile.windows[context.windowID] {
                if let fieldID = context.fieldID,
                   let fieldProfile = windowProfile.fields[fieldID] {
                    return fieldProfile.sourceID
                }
                // 用户决策：同窗口未曾记录过的全新输入框，默认继承窗口最后使用的输入法
                return windowProfile.lastSourceID
            }
            return appProfile.lastSourceID
        }
    }
    
    // MARK: - Lock State Management
    
    /// 判断给定的焦点上下文在当前生效粒度下是否受锁定保护
    public func isContextLocked(
        for context: FocusContext,
        effectiveGranularity: GranularityLevel
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        guard let appProfile = profiles[context.bundleID] else {
            return false
        }
        
        // 若应用级已被锁定，则整个 App 内所有上下文均受到锁定保护
        if appProfile.isLocked {
            return true
        }
        
        switch effectiveGranularity {
        case .app:
            return appProfile.isLocked
            
        case .window:
            if let windowProfile = appProfile.windows[context.windowID] {
                return windowProfile.isLocked
            }
            return false
            
        case .field:
            if let windowProfile = appProfile.windows[context.windowID] {
                if windowProfile.isLocked {
                    return true
                }
                if let fieldID = context.fieldID,
                   let fieldProfile = windowProfile.fields[fieldID] {
                    return fieldProfile.isLocked
                }
            }
            return false
        }
    }
    
    /// 解析指定焦点上下文的当前细分锁定层级
    public func lockStatus(
        for context: FocusContext,
        effectiveGranularity: GranularityLevel
    ) -> HierarchyItem.LockStatus {
        lock.lock()
        defer { lock.unlock() }
        
        guard let appProfile = profiles[context.bundleID] else {
            return .unlocked
        }
        
        if appProfile.isLocked {
            return .locked(level: .app)
        }
        
        switch effectiveGranularity {
        case .app:
            return .unlocked
            
        case .window:
            if let windowProfile = appProfile.windows[context.windowID], windowProfile.isLocked {
                return .locked(level: .window)
            }
            return .unlocked
            
        case .field:
            if let windowProfile = appProfile.windows[context.windowID] {
                if let fieldID = context.fieldID,
                   let fieldProfile = windowProfile.fields[fieldID],
                   fieldProfile.isLocked {
                    return .locked(level: .field)
                }
                if windowProfile.isLocked {
                    return .inherited(from: .window)
                }
            }
            return .unlocked
        }
    }
    
    /// 切换某个节点的锁定状态并持久化
    public func toggleLock(for item: HierarchyItem) {
        lock.lock()
        defer {
            lock.unlock()
            saveToDisk()
        }
        
        switch item.itemType {
        case .app(let bundleID, _):
            if var app = profiles[bundleID] {
                app.isLocked.toggle()
                profiles[bundleID] = app
            }
        case .window(let bundleID, let windowID):
            if var app = profiles[bundleID], var win = app.windows[windowID] {
                win.isLocked.toggle()
                app.windows[windowID] = win
                profiles[bundleID] = app
            }
        case .field(let bundleID, let windowID, let fieldID):
            if var app = profiles[bundleID], var win = app.windows[windowID], var field = win.fields[fieldID] {
                field.isLocked.toggle()
                win.fields[fieldID] = field
                app.windows[windowID] = win
                profiles[bundleID] = app
            }
        }
    }
    
    // MARK: - Record & Update
    
    /// 记录当前焦点上下文绑定的输入法
    public func record(
        context: FocusContext,
        sourceID: String,
        effectiveGranularity: GranularityLevel
    ) {
        lock.lock()
        
        var appProfile = profiles[context.bundleID] ?? AppProfile(
            id: context.bundleID,
            appName: context.appName,
            lastSourceID: sourceID
        )
        
        // 仅在 App 自身未锁定时更新 appProfile 的输入法
        if !appProfile.isLocked {
            appProfile.lastSourceID = sourceID
            appProfile.lastUpdated = Date()
        }
        
        var windowProfile = appProfile.windows[context.windowID] ?? WindowProfile(
            id: context.windowID,
            windowTitle: context.windowTitle,
            lastSourceID: sourceID
        )
        
        // 仅在窗口未锁定且未继承 App 锁定时更新窗口的输入法
        if !windowProfile.isLocked && !appProfile.isLocked {
            windowProfile.lastSourceID = sourceID
            windowProfile.windowTitle = context.windowTitle
            windowProfile.lastUpdated = Date()
        }
        
        if effectiveGranularity == .field, let fieldID = context.fieldID {
            let fieldIdentifier = context.fieldDescription ?? context.role ?? AppConstants.Accessibility.unknownFieldIdentifier
            var fieldProfile = windowProfile.fields[fieldID] ?? FieldProfile(
                id: fieldID,
                fieldIdentifier: fieldIdentifier,
                role: context.role ?? AppConstants.Accessibility.textFieldRole,
                sourceID: sourceID
            )
            // 仅在输入框未锁定且未继承窗口/应用锁定时更新输入框的输入法
            if !fieldProfile.isLocked && !windowProfile.isLocked && !appProfile.isLocked {
                fieldProfile.sourceID = sourceID
                fieldProfile.fieldIdentifier = fieldIdentifier
                fieldProfile.lastUpdated = Date()
            }
            windowProfile.fields[fieldID] = fieldProfile
        }
        
        appProfile.windows[context.windowID] = windowProfile
        profiles[context.bundleID] = appProfile
        
        lock.unlock()
        saveToDisk()
    }
    
    // MARK: - Node Modification for Settings UI
    
    public func updateSource(for item: HierarchyItem, newSourceID: String) {
        lock.lock()
        defer {
            lock.unlock()
            saveToDisk()
        }
        
        switch item.itemType {
        case .app(let bundleID, _):
            if var app = profiles[bundleID] {
                app.lastSourceID = newSourceID
                app.lastUpdated = Date()
                // 级联更新该应用下所有已记录的窗口与输入框
                for (winID, var win) in app.windows {
                    win.lastSourceID = newSourceID
                    win.lastUpdated = Date()
                    for (fieldID, var field) in win.fields {
                        field.sourceID = newSourceID
                        field.lastUpdated = Date()
                        win.fields[fieldID] = field
                    }
                    app.windows[winID] = win
                }
                profiles[bundleID] = app
            }
        case .window(let bundleID, let windowID):
            if var app = profiles[bundleID], var win = app.windows[windowID] {
                win.lastSourceID = newSourceID
                win.lastUpdated = Date()
                app.lastSourceID = newSourceID
                app.lastUpdated = Date()
                // 级联更新该窗口下所有已记录的输入框
                for (fieldID, var field) in win.fields {
                    field.sourceID = newSourceID
                    field.lastUpdated = Date()
                    win.fields[fieldID] = field
                }
                app.windows[windowID] = win
                profiles[bundleID] = app
            }
        case .field(let bundleID, let windowID, let fieldID):
            if var app = profiles[bundleID],
               var win = app.windows[windowID],
               var field = win.fields[fieldID] {
                field.sourceID = newSourceID
                field.lastUpdated = Date()
                win.lastSourceID = newSourceID
                win.lastUpdated = Date()
                app.lastSourceID = newSourceID
                app.lastUpdated = Date()
                win.fields[fieldID] = field
                app.windows[windowID] = win
                profiles[bundleID] = app
            }
        }
    }
    
    public func delete(item: HierarchyItem) {
        lock.lock()
        defer {
            lock.unlock()
            saveToDisk()
        }
        
        switch item.itemType {
        case .app(let bundleID, _):
            profiles.removeValue(forKey: bundleID)
        case .window(let bundleID, let windowID):
            if var app = profiles[bundleID] {
                app.windows.removeValue(forKey: windowID)
                profiles[bundleID] = app
            }
        case .field(let bundleID, let windowID, let fieldID):
            if var app = profiles[bundleID], var win = app.windows[windowID] {
                win.fields.removeValue(forKey: fieldID)
                app.windows[windowID] = win
                profiles[bundleID] = app
            }
        }
    }
    
    public func clearAll() {
        lock.lock()
        profiles.removeAll()
        lock.unlock()
        saveToDisk()
    }
    
    // MARK: - Tree Presentation Generator
    
    private enum HierarchySortPriority {
        static let directlyLocked = 0
        static let partiallyLocked = 1
        static let unlocked = 2
    }
    
    /// 将存储的扁平结构构造为适用于 OutlineGroup 渲染的树状项列表（锁定的项目置顶显示）
    public func buildHierarchyItems(
        granularityManager: GranularityManager,
        searchQuery: String? = nil
    ) -> [HierarchyItem] {
        lock.lock()
        defer { lock.unlock() }
        
        var result: [HierarchyItem] = []
        let query = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // 应用程序排序：直接锁定的应用排在最前面，包含锁定窗口/输入框的应用居中，未锁定的排最后；同优先级按应用名字母排序
        let sortedApps = profiles.values.sorted { lhs, rhs in
            let lhsPriority = lhs.isLocked ? HierarchySortPriority.directlyLocked : (lhs.windows.values.contains { $0.isLocked || $0.fields.values.contains { $0.isLocked } } ? HierarchySortPriority.partiallyLocked : HierarchySortPriority.unlocked)
            let rhsPriority = rhs.isLocked ? HierarchySortPriority.directlyLocked : (rhs.windows.values.contains { $0.isLocked || $0.fields.values.contains { $0.isLocked } } ? HierarchySortPriority.partiallyLocked : HierarchySortPriority.unlocked)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.appName.localizedStandardCompare(rhs.appName) == .orderedAscending
        }
        
        for app in sortedApps {
            let isBrowser = AppConstants.Browsers.knownBrowserBundleIDs.contains(app.id)
            let configuredGranularity = granularityManager.configuredGranularity(for: app.id)
            let displayGranularity = configuredGranularity ?? granularityManager.getGlobalDefault()
            
            var windowItems: [HierarchyItem] = []
            // 窗口排序：直接锁定的窗口置顶，包含锁定输入框的居中，未锁定的排后
            let sortedWindows = app.windows.values.sorted { lhs, rhs in
                let lhsPriority = lhs.isLocked ? HierarchySortPriority.directlyLocked : (lhs.fields.values.contains { $0.isLocked } ? HierarchySortPriority.partiallyLocked : HierarchySortPriority.unlocked)
                let rhsPriority = rhs.isLocked ? HierarchySortPriority.directlyLocked : (rhs.fields.values.contains { $0.isLocked } ? HierarchySortPriority.partiallyLocked : HierarchySortPriority.unlocked)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                return lhs.windowTitle.localizedStandardCompare(rhs.windowTitle) == .orderedAscending
            }
            
            for win in sortedWindows {
                var fieldItems: [HierarchyItem] = []
                // 输入框排序：直接锁定的输入框置顶
                let sortedFields = win.fields.values.sorted { lhs, rhs in
                    let lhsPriority = lhs.isLocked ? HierarchySortPriority.directlyLocked : HierarchySortPriority.unlocked
                    let rhsPriority = rhs.isLocked ? HierarchySortPriority.directlyLocked : HierarchySortPriority.unlocked
                    if lhsPriority != rhsPriority {
                        return lhsPriority < rhsPriority
                    }
                    return lhs.fieldIdentifier.localizedStandardCompare(rhs.fieldIdentifier) == .orderedAscending
                }
                
                for field in sortedFields {
                    // 输入框级锁定状态解析
                    let fieldLockStatus: HierarchyItem.LockStatus
                    if field.isLocked {
                        fieldLockStatus = .locked(level: .field)
                    } else if win.isLocked {
                        fieldLockStatus = .inherited(from: .window)
                    } else if app.isLocked {
                        fieldLockStatus = .inherited(from: .app)
                    } else {
                        fieldLockStatus = .unlocked
                    }
                    
                    let fieldItem = HierarchyItem(
                        id: "field:\(app.id):\(win.id):\(field.id)",
                        title: field.fieldIdentifier.isEmpty ? field.role : field.fieldIdentifier,
                        subtitle: L10n.fieldRoleSubtitle(role: field.role),
                        itemType: .field(bundleID: app.id, windowID: win.id, fieldID: field.id),
                        currentSourceID: field.sourceID,
                        isLocked: field.isLocked,
                        lockStatus: fieldLockStatus
                    )
                    fieldItems.append(fieldItem)
                }
                
                // 窗口级锁定状态解析
                let winLockStatus: HierarchyItem.LockStatus
                if win.isLocked {
                    winLockStatus = .locked(level: .window)
                } else if app.isLocked {
                    winLockStatus = .inherited(from: .app)
                } else {
                    winLockStatus = .unlocked
                }
                
                let winItem = HierarchyItem(
                    id: "win:\(app.id):\(win.id)",
                    title: win.windowTitle.isEmpty ? L10n.defaultWindowPlaceholder : win.windowTitle,
                    subtitle: L10n.windowSubtitle(fieldCount: win.fields.count),
                    itemType: .window(bundleID: app.id, windowID: win.id),
                    currentSourceID: win.lastSourceID,
                    isLocked: win.isLocked,
                    lockStatus: winLockStatus,
                    children: fieldItems.isEmpty ? nil : fieldItems
                )
                windowItems.append(winItem)
            }
            
            let browserHint = isBrowser && displayGranularity == .field ? L10n.browserEnvironmentHint : ""
            let appLockStatus: HierarchyItem.LockStatus = app.isLocked ? .locked(level: .app) : .unlocked
            
            let appItem = HierarchyItem(
                id: "app:\(app.id)",
                title: app.appName,
                subtitle: "\(app.id)\(browserHint)",
                itemType: .app(bundleID: app.id, granularity: displayGranularity),
                currentSourceID: app.lastSourceID,
                isLocked: app.isLocked,
                lockStatus: appLockStatus,
                children: windowItems.isEmpty ? nil : windowItems
            )
            
            // 搜索过滤逻辑
            if let query = query, !query.isEmpty {
                let matchesApp = app.appName.lowercased().contains(query) || app.id.lowercased().contains(query)
                let matchesWindow = windowItems.contains { $0.title.lowercased().contains(query) }
                if matchesApp || matchesWindow {
                    result.append(appItem)
                }
            } else {
                result.append(appItem)
            }
        }
        
        return result
    }
    
    // MARK: - Persistence
    
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([String: AppProfile].self, from: data) else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        self.profiles = decoded
    }
    
    private func saveToDisk() {
        lock.lock()
        let copy = profiles
        lock.unlock()
        
        guard let encoded = try? JSONEncoder().encode(copy) else { return }
        try? encoded.write(to: storageURL, options: .atomic)
    }
}
