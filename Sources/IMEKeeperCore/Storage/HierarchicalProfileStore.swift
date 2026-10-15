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
            
        case .field:
            if let fieldID = context.fieldID,
               let fieldProfile = appProfile.fields[fieldID] {
                return fieldProfile.sourceID
            }
            // 未曾记录过的全新输入框，默认继承应用最后使用的输入法
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
            
        case .field:
            if let fieldID = context.fieldID,
               let fieldProfile = appProfile.fields[fieldID] {
                return fieldProfile.isLocked
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
            
        case .field:
            if let fieldID = context.fieldID,
               let fieldProfile = appProfile.fields[fieldID],
               fieldProfile.isLocked {
                return .locked(level: .field)
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
        case .app(let bundleID, _, _):
            if var app = profiles[bundleID] {
                app.isLocked.toggle()
                profiles[bundleID] = app
            }
        case .field(let bundleID, let fieldID):
            if var app = profiles[bundleID], var field = app.fields[fieldID] {
                field.isLocked.toggle()
                app.fields[fieldID] = field
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
        
        if effectiveGranularity == .field, context.isInputField, let fieldID = context.fieldID {
            // 当 App 自身已被锁定时，不再向该应用新增任何输入框记录（避免在浏览器、IDE 等场景下偏好和记录无限暴涨）
            if appProfile.isLocked && appProfile.fields[fieldID] == nil {
                // 跳过新增 field
            } else {
                let fieldIdentifier = context.fieldDescription ?? context.role ?? AppConstants.Accessibility.unknownFieldIdentifier
                // 检查输入框是否为新创建：新创建的输入框继承上级 App 当前指定的输入法设置
                var fieldProfile = appProfile.fields[fieldID] ?? FieldProfile(
                    id: fieldID,
                    fieldIdentifier: fieldIdentifier,
                    role: context.role ?? AppConstants.Accessibility.textFieldRole,
                    sourceID: appProfile.lastSourceID
                )
                // 仅在输入框未锁定且未继承应用锁定时更新输入框的输入法（保留已有的自定义名称，避免被覆盖）
                if !fieldProfile.isLocked && !appProfile.isLocked {
                    fieldProfile.sourceID = sourceID
                    fieldProfile.lastUpdated = Date()
                }
                appProfile.fields[fieldID] = fieldProfile
            }
        }
        
        profiles[context.bundleID] = appProfile
        
        lock.unlock()
        saveToDisk()
    }
    
    // MARK: - Node Modification for Settings UI
    
    /// 重命名指定输入框的显示标题/标识
    public func renameField(bundleID: String, fieldID: String, newName: String) {
        lock.lock()
        defer {
            lock.unlock()
            saveToDisk()
        }
        
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if var app = profiles[bundleID], var field = app.fields[fieldID] {
            field.fieldIdentifier = trimmed
            field.lastUpdated = Date()
            app.fields[fieldID] = field
            profiles[bundleID] = app
        }
    }
    
    public func updateSource(for item: HierarchyItem, newSourceID: String) {
        lock.lock()
        defer {
            lock.unlock()
            saveToDisk()
        }
        
        // 遵循隔离原则：修改 Field 绝不覆盖上级 App；修改 App 亦不覆盖已有 Field
        switch item.itemType {
        case .app(let bundleID, _, _):
            if var app = profiles[bundleID] {
                app.lastSourceID = newSourceID
                app.lastUpdated = Date()
                profiles[bundleID] = app
            }
        case .field(let bundleID, let fieldID):
            if var app = profiles[bundleID],
               var field = app.fields[fieldID] {
                field.sourceID = newSourceID
                field.lastUpdated = Date()
                app.fields[fieldID] = field
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
        case .app(let bundleID, _, _):
            profiles.removeValue(forKey: bundleID)
        case .field(let bundleID, let fieldID):
            if var app = profiles[bundleID] {
                app.fields.removeValue(forKey: fieldID)
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
    
    // MARK: - Cleaning Redundant Sub-Items
    
    /// 清理指定应用下的下级输入框记忆
    public func cleanSubItems(for bundleID: String, granularity: GranularityLevel) {
        lock.lock()
        defer {
            lock.unlock()
            saveToDisk()
        }
        
        guard var app = profiles[bundleID] else { return }
        
        switch granularity {
        case .app:
            app.fields.removeAll()
            profiles[bundleID] = app
        case .field:
            break
        }
    }
    
    /// 根据层级项类型清理对应的下级冗余记录
    public func clean(item: HierarchyItem) {
        switch item.itemType {
        case .app(let bundleID, let granularity, _):
            cleanSubItems(for: bundleID, granularity: granularity)
        case .field:
            break
        }
    }
    
    /// 根据每个 App 当前的生效粒度，全局清理所有冗余的下级输入框记录
    public func cleanAllRedundantSubItems(granularityManager: GranularityManager) {
        lock.lock()
        defer {
            lock.unlock()
            saveToDisk()
        }
        
        for (bundleID, var app) in profiles {
            let isBrowser = AppConstants.Browsers.knownBrowserBundleIDs.contains(bundleID)
            let gran = granularityManager.effectiveGranularity(for: bundleID, isBrowser: isBrowser)
            switch gran {
            case .app:
                app.fields.removeAll()
                profiles[bundleID] = app
            case .field:
                break
            }
        }
    }
    
    /// 检查全局是否存在任何不符合当前生效粒度的冗余下级记录
    public func hasAnyRedundantSubItems(granularityManager: GranularityManager) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        for (bundleID, app) in profiles {
            let isBrowser = AppConstants.Browsers.knownBrowserBundleIDs.contains(bundleID)
            let gran = granularityManager.effectiveGranularity(for: bundleID, isBrowser: isBrowser)
            switch gran {
            case .app:
                if !app.fields.isEmpty { return true }
            case .field:
                break
            }
        }
        return false
    }
    
    /// 判断给定的焦点上下文在当前生效粒度下是否需要自动收录至存储结构中
    public func shouldAutoRecordContext(_ context: FocusContext, effectiveGranularity: GranularityLevel) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        guard let appProfile = profiles[context.bundleID] else {
            return true
        }
        
        switch effectiveGranularity {
        case .app:
            return false
        case .field:
            // 当 App 已被锁定时，不主动收录新发现的输入框节点
            if appProfile.isLocked {
                return false
            }
            if context.isInputField, let fieldID = context.fieldID {
                return appProfile.fields[fieldID] == nil
            }
            return false
        }
    }
    
    // MARK: - Tree Presentation Generator
    
    private enum HierarchySortPriority {
        static let directlyLocked = 0
        static let partiallyLocked = 1
        static let unlocked = 2
    }
    
    /// 将存储的扁平结构构造为适用于 OutlineGroup 渲染的树状项列表（锁定的项目置顶显示，或遵循外部指定的显示顺序）
    public func buildHierarchyItems(
        granularityManager: GranularityManager,
        searchQuery: String? = nil,
        customAppOrder: [String]? = nil
    ) -> [HierarchyItem] {
        lock.lock()
        defer { lock.unlock() }
        
        var result: [HierarchyItem] = []
        let query = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // 应用程序排序：若指定了已有显示顺序，则保持当前视觉顺序稳定；否则执行完整排序（锁定项置顶，同级按名称字母升序）
        let sortedApps: [AppProfile]
        if let customAppOrder = customAppOrder {
            let orderMap = Dictionary(uniqueKeysWithValues: customAppOrder.enumerated().map { ($0.element, $0.offset) })
            sortedApps = profiles.values.sorted { lhs, rhs in
                let lhsIndex = orderMap[lhs.id] ?? Int.max
                let rhsIndex = orderMap[rhs.id] ?? Int.max
                if lhsIndex != rhsIndex {
                    return lhsIndex < rhsIndex
                }
                return lhs.appName.localizedStandardCompare(rhs.appName) == .orderedAscending
            }
        } else {
            sortedApps = profiles.values.sorted { lhs, rhs in
                let lhsPriority = lhs.isLocked ? HierarchySortPriority.directlyLocked : (lhs.fields.values.contains { $0.isLocked } ? HierarchySortPriority.partiallyLocked : HierarchySortPriority.unlocked)
                let rhsPriority = rhs.isLocked ? HierarchySortPriority.directlyLocked : (rhs.fields.values.contains { $0.isLocked } ? HierarchySortPriority.partiallyLocked : HierarchySortPriority.unlocked)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                return lhs.appName.localizedStandardCompare(rhs.appName) == .orderedAscending
            }
        }
        
        for app in sortedApps {
            let configuredGranularity = granularityManager.configuredGranularity(for: app.id)
            let displayGranularity = configuredGranularity ?? granularityManager.getGlobalDefault()
            
            var fieldItems: [HierarchyItem] = []
            // 输入框排序：直接锁定的输入框置顶
            let sortedFields = app.fields.values.sorted { lhs, rhs in
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
                } else if app.isLocked {
                    fieldLockStatus = .inherited(from: .app)
                } else {
                    fieldLockStatus = .unlocked
                }
                
                let hashPrefix = String(field.id.prefix(AppConstants.UI.fieldHashDisplayLength))
                let fieldItem = HierarchyItem(
                    id: "field:\(app.id):\(field.id)",
                    title: field.fieldIdentifier.isEmpty ? field.role : field.fieldIdentifier,
                    subtitle: L10n.fieldRoleSubtitle(role: field.role),
                    hashSubtitle: L10n.fieldHashSubtitle(hashPrefix: hashPrefix),
                    itemType: .field(bundleID: app.id, fieldID: field.id),
                    currentSourceID: field.sourceID,
                    isLocked: field.isLocked,
                    lockStatus: fieldLockStatus
                )
                fieldItems.append(fieldItem)
            }
            
            let appLockStatus: HierarchyItem.LockStatus = app.isLocked ? .locked(level: .app) : .unlocked
            let nonInputPolicy = granularityManager.effectiveNonInputPolicy(for: app.id)
            
            let appItem = HierarchyItem(
                id: "app:\(app.id)",
                title: app.appName,
                subtitle: app.id,
                itemType: .app(bundleID: app.id, granularity: displayGranularity, nonInputPolicy: nonInputPolicy),
                currentSourceID: app.lastSourceID,
                isLocked: app.isLocked,
                lockStatus: appLockStatus,
                children: fieldItems.isEmpty ? nil : fieldItems
            )
            
            // 搜索过滤逻辑
            if let query = query, !query.isEmpty {
                let matchesApp = app.appName.lowercased().contains(query) || app.id.lowercased().contains(query)
                let matchesField = fieldItems.contains { $0.title.lowercased().contains(query) }
                if matchesApp || matchesField {
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
