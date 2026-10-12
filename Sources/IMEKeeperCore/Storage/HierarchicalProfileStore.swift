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
        appProfile.lastSourceID = sourceID
        appProfile.lastUpdated = Date()
        
        var windowProfile = appProfile.windows[context.windowID] ?? WindowProfile(
            id: context.windowID,
            windowTitle: context.windowTitle,
            lastSourceID: sourceID
        )
        windowProfile.lastSourceID = sourceID
        windowProfile.windowTitle = context.windowTitle
        windowProfile.lastUpdated = Date()
        
        if effectiveGranularity == .field, let fieldID = context.fieldID {
            let fieldIdentifier = context.fieldDescription ?? context.role ?? AppConstants.Accessibility.unknownFieldIdentifier
            var fieldProfile = windowProfile.fields[fieldID] ?? FieldProfile(
                id: fieldID,
                fieldIdentifier: fieldIdentifier,
                role: context.role ?? AppConstants.Accessibility.textFieldRole,
                sourceID: sourceID
            )
            fieldProfile.sourceID = sourceID
            fieldProfile.fieldIdentifier = fieldIdentifier
            fieldProfile.lastUpdated = Date()
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
    
    /// 将存储的扁平结构构造为适用于 OutlineGroup 渲染的树状项列表
    public func buildHierarchyItems(
        granularityManager: GranularityManager,
        searchQuery: String? = nil
    ) -> [HierarchyItem] {
        lock.lock()
        defer { lock.unlock() }
        
        var result: [HierarchyItem] = []
        let query = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        let sortedApps = profiles.values.sorted { $0.appName < $1.appName }
        
        for app in sortedApps {
            let isBrowser = AppConstants.Browsers.knownBrowserBundleIDs.contains(app.id)
            let configuredGranularity = granularityManager.configuredGranularity(for: app.id)
            let displayGranularity = configuredGranularity ?? granularityManager.getGlobalDefault()
            
            var windowItems: [HierarchyItem] = []
            let sortedWindows = app.windows.values.sorted { $0.windowTitle < $1.windowTitle }
            
            for win in sortedWindows {
                var fieldItems: [HierarchyItem] = []
                let sortedFields = win.fields.values.sorted { $0.fieldIdentifier < $1.fieldIdentifier }
                
                for field in sortedFields {
                    let fieldItem = HierarchyItem(
                        id: "field:\(app.id):\(win.id):\(field.id)",
                        title: field.fieldIdentifier.isEmpty ? field.role : field.fieldIdentifier,
                        subtitle: "角色: \(field.role)",
                        itemType: .field(bundleID: app.id, windowID: win.id, fieldID: field.id),
                        currentSourceID: field.sourceID
                    )
                    fieldItems.append(fieldItem)
                }
                
                let winItem = HierarchyItem(
                    id: "win:\(app.id):\(win.id)",
                    title: win.windowTitle.isEmpty ? AppConstants.Accessibility.defaultWindowPlaceholder : win.windowTitle,
                    subtitle: "包含 \(win.fields.count) 个输入框记录",
                    itemType: .window(bundleID: app.id, windowID: win.id),
                    currentSourceID: win.lastSourceID,
                    children: fieldItems.isEmpty ? nil : fieldItems
                )
                windowItems.append(winItem)
            }
            
            let browserHint = isBrowser && displayGranularity == .field ? " · 浏览器环境（受保护最高生效至窗口级）" : ""
            let appItem = HierarchyItem(
                id: "app:\(app.id)",
                title: app.appName,
                subtitle: "\(app.id)\(browserHint)",
                itemType: .app(bundleID: app.id, granularity: displayGranularity),
                currentSourceID: app.lastSourceID,
                children: windowItems.isEmpty ? nil : windowItems
            )
            
            // 搜索过滤过滤逻辑
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
