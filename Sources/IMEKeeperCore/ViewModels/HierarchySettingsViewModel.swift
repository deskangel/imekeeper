import Foundation
import Combine

/// 设置面板与多层级树状大纲的响应式 ViewModel
@MainActor
public final class HierarchySettingsViewModel: ObservableObject {
    
    @Published public var hierarchyItems: [HierarchyItem] = []
    @Published public var availableSources: [InputSourceModel] = []
    @Published public var globalGranularity: GranularityLevel = .field
    @Published public var globalNonInputPolicy: NonInputPolicy = .alwaysEnglish
    @Published public var searchQuery: String = "" {
        didSet {
            refreshTree()
        }
    }
    @Published public var currentFocusContext: FocusContext?
    @Published public var currentFocusLockStatus: HierarchyItem.LockStatus = .unlocked
    @Published public var currentActiveSource: InputSourceModel?
    @Published public var isEnabled: Bool = true
    @Published public var isAutoStartEnabled: Bool = false
    @Published public var currentLanguage: AppLanguage = LocalizationManager.shared.currentLanguage
    @Published public var selectedItemID: String?
    @Published public var expandedItemIDs: Set<String> = []
    
    public let store: HierarchicalProfileStore
    public let granularityManager: GranularityManager
    public let inputSourceManager: InputSourceManagerProtocol
    public let autoStartManager: AutoStartManagerProtocol
    private var cancellables = Set<AnyCancellable>()
    private var appDisplayOrder: [String]?
    
    public init(
        store: HierarchicalProfileStore,
        granularityManager: GranularityManager,
        inputSourceManager: InputSourceManagerProtocol,
        autoStartManager: AutoStartManagerProtocol = AutoStartManager()
    ) {
        self.store = store
        self.granularityManager = granularityManager
        self.inputSourceManager = inputSourceManager
        self.autoStartManager = autoStartManager
        self.isAutoStartEnabled = autoStartManager.isAutoStartEnabled
        self.globalGranularity = granularityManager.getGlobalDefault()
        self.globalNonInputPolicy = granularityManager.getGlobalNonInputDefault()
        self.availableSources = inputSourceManager.availableSources
        self.currentActiveSource = inputSourceManager.currentSource
        self.currentLanguage = LocalizationManager.shared.currentLanguage
        
        // 监听语言变化，自动重新生成树状大纲并刷新 UI
        LocalizationManager.shared.$currentLanguage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newLang in
                guard let self = self else { return }
                self.currentLanguage = newLang
                self.refreshTree()
            }
            .store(in: &cancellables)
        
        openPreferences()
    }
    
    /// 设置应用程序语言
    public func setLanguage(_ language: AppLanguage) {
        LocalizationManager.shared.setLanguage(language)
    }
    
    /// 打开偏好设置时调用：触发全量排序并稳定记录当前大纲显示顺序
    public func openPreferences() {
        self.appDisplayOrder = nil
        refreshTree(sorting: true)
    }
    
    /// 刷新整棵大纲树
    /// - Parameter sorting: 是否重新按照锁定权重全局排序。若为 false 则维持当前大纲视觉顺序
    public func refreshTree(sorting: Bool = false) {
        if sorting {
            self.appDisplayOrder = nil
        }
        self.hierarchyItems = store.buildHierarchyItems(
            granularityManager: granularityManager,
            searchQuery: searchQuery,
            customAppOrder: appDisplayOrder
        )
        
        // 预热所有包含的应用图标至内存缓存，避免在列表滚动时触发主线程磁盘 I/O 或系统 IPC
        let appBundleIDs = hierarchyItems.compactMap { item -> String? in
            if case .app(let bundleID, _, _) = item.itemType {
                return bundleID
            }
            return nil
        }
        self.appDisplayOrder = appBundleIDs
        AppIconProvider.shared.preloadIcons(for: appBundleIDs)
        
        if selectedItemID == nil, let context = currentFocusContext {
            locateFocusedItem(for: context)
        }
    }
    
    /// 刷新输入法列表
    public func reloadInputSources() {
        inputSourceManager.reloadAvailableSources()
        self.availableSources = inputSourceManager.availableSources
        self.currentActiveSource = inputSourceManager.currentSource
    }
    
    /// 更新某一层级项绑定的输入法
    public func updateSource(for item: HierarchyItem, newSourceID: String) {
        store.updateSource(for: item, newSourceID: newSourceID)
        refreshTree()
    }
    
    /// 重命名输入框显示标识/名称
    public func renameField(item: HierarchyItem, newName: String) {
        guard case .field(let bundleID, let fieldID) = item.itemType else { return }
        store.renameField(bundleID: bundleID, fieldID: fieldID, newName: newName)
        refreshTree()
    }
    
    /// 删除某一层级节点
    public func deleteItem(_ item: HierarchyItem) {
        store.delete(item: item)
        refreshTree()
    }
    
    /// 设置某个 App 专属生效粒度
    public func setGranularity(for bundleID: String, level: GranularityLevel?) {
        granularityManager.setGranularity(for: bundleID, level: level)
        if level == .field {
            expandedItemIDs.insert("app:\(bundleID)")
        }
        refreshTree()
    }
    
    /// 获取某个 App 的独立配置粒度
    public func configuredGranularity(for bundleID: String) -> GranularityLevel? {
        granularityManager.configuredGranularity(for: bundleID)
    }
    
    /// 设置某个 App 专属的非输入行为策略
    public func setNonInputPolicy(for bundleID: String, policy: NonInputPolicy?) {
        granularityManager.setNonInputPolicy(for: bundleID, policy: policy)
        refreshTree()
    }
    
    /// 获取某个 App 实际生效的非输入策略
    public func effectiveNonInputPolicy(for bundleID: String) -> NonInputPolicy {
        granularityManager.effectiveNonInputPolicy(for: bundleID)
    }
    
    /// 获取某个 App 用户独立配置的非输入策略
    public func configuredNonInputPolicy(for bundleID: String) -> NonInputPolicy? {
        granularityManager.configuredNonInputPolicy(for: bundleID)
    }
    
    /// 设置全局生效默认粒度
    public func setGlobalGranularity(_ level: GranularityLevel) {
        granularityManager.setGlobalDefault(level)
        self.globalGranularity = level
        refreshTree()
    }
    
    /// 设置全局生效默认非输入行为策略
    public func setGlobalNonInputPolicy(_ policy: NonInputPolicy) {
        granularityManager.setGlobalNonInputDefault(policy)
        self.globalNonInputPolicy = policy
        refreshTree()
    }
    
    /// 清除所有历史记录
    public func clearAllHistory() {
        store.clearAll()
        refreshTree()
    }
    
    /// 清理指定层级项的下级记录（App 粒度下清理其所有输入框记录）
    public func cleanItem(_ item: HierarchyItem) {
        store.clean(item: item)
        refreshTree()
    }
    
    /// 清理指定应用下的下级记忆（根据生效粒度）
    public func cleanSubItems(for bundleID: String, granularity: GranularityLevel) {
        store.cleanSubItems(for: bundleID, granularity: granularity)
        refreshTree()
    }
    
    /// 全局清理所有应用下不符合当前生效粒度的冗余下级记录
    public func cleanAllRedundantSubItems() {
        store.cleanAllRedundantSubItems(granularityManager: granularityManager)
        refreshTree()
    }
    
    /// 是否存在任何可全局清理的冗余记录
    public var hasRedundantSubItems: Bool {
        store.hasAnyRedundantSubItems(granularityManager: granularityManager)
    }
    
    /// 切换某一层级节点的锁定状态（就地更新节点状态，不立刻触发列表重排序，保持视觉位置稳定）
    public func toggleLock(for item: HierarchyItem) {
        store.toggleLock(for: item)
        updateLockStatusInPlace(for: item)
        if let context = currentFocusContext {
            let gran = granularityManager.effectiveGranularity(for: context.bundleID, isBrowser: context.isBrowserApp)
            self.currentFocusLockStatus = store.lockStatus(for: context, effectiveGranularity: gran)
        }
    }
    
    /// 在不重新排序的情况下就地刷新层级项的锁定状态
    private func updateLockStatusInPlace(for item: HierarchyItem) {
        switch item.itemType {
        case .app(let bundleID, _, _):
            let appID = "app:\(bundleID)"
            guard let appIndex = hierarchyItems.firstIndex(where: { $0.id == appID }) else { return }
            var appItem = hierarchyItems[appIndex]
            appItem.isLocked.toggle()
            appItem.lockStatus = appItem.isLocked ? .locked(level: .app) : .unlocked
            
            // 同步联动该 App 下各输入框的继承保护状态
            if var children = appItem.children {
                for i in 0..<children.count {
                    if children[i].isLocked {
                        children[i].lockStatus = .locked(level: .field)
                    } else if appItem.isLocked {
                        children[i].lockStatus = .inherited(from: .app)
                    } else {
                        children[i].lockStatus = .unlocked
                    }
                }
                appItem.children = children
            }
            hierarchyItems[appIndex] = appItem
            
        case .field(let bundleID, _):
            let appID = "app:\(bundleID)"
            guard let appIndex = hierarchyItems.firstIndex(where: { $0.id == appID }) else { return }
            var appItem = hierarchyItems[appIndex]
            guard var children = appItem.children,
                  let fieldIndex = children.firstIndex(where: { $0.id == item.id }) else { return }
            
            var fieldItem = children[fieldIndex]
            fieldItem.isLocked.toggle()
            if fieldItem.isLocked {
                fieldItem.lockStatus = .locked(level: .field)
            } else if appItem.isLocked {
                fieldItem.lockStatus = .inherited(from: .app)
            } else {
                fieldItem.lockStatus = .unlocked
            }
            children[fieldIndex] = fieldItem
            appItem.children = children
            hierarchyItems[appIndex] = appItem
        }
    }
    
    /// 判断指定层级节点是否处于展开状态
    public func isExpanded(_ id: String) -> Bool {
        expandedItemIDs.contains(id)
    }
    
    /// 设置指定层级节点的展开状态
    public func setExpanded(_ id: String, isExpanded: Bool) {
        if isExpanded {
            expandedItemIDs.insert(id)
        } else {
            expandedItemIDs.remove(id)
        }
    }
    
    /// 根据当前焦点上下文与生效粒度，解析出应该定位的目标节点 ID 与必须展开的祖先节点 ID 列表
    public func resolveTargetItemID(for context: FocusContext) -> (targetID: String, ancestorIDs: [String])? {
        let appID = "app:\(context.bundleID)"
        guard let appItem = hierarchyItems.first(where: { $0.id == appID }) else {
            return nil
        }
        
        let effectiveGranularity = granularityManager.effectiveGranularity(
            for: context.bundleID,
            isBrowser: context.isBrowserApp
        )
        
        switch effectiveGranularity {
        case .app:
            // 设定为 app 粒度时，定位到 App 根节点
            return (targetID: appID, ancestorIDs: [])
            
        case .field:
            if let fieldID = context.fieldID {
                let fieldItemID = "field:\(context.bundleID):\(fieldID)"
                if let fieldItems = appItem.children,
                   fieldItems.contains(where: { $0.id == fieldItemID }) {
                    return (targetID: fieldItemID, ancestorIDs: [appID])
                }
            }
            
            // 输入框尚未记录或焦点处于非输入区，回退至所属应用
            return (targetID: appID, ancestorIDs: [])
        }
    }
    
    /// 自动选中并展开当前聚焦元素对应的层级项
    public func locateFocusedItem(for context: FocusContext) {
        guard let resolved = resolveTargetItemID(for: context) else { return }
        self.selectedItemID = resolved.targetID
        for ancestorID in resolved.ancestorIDs {
            self.expandedItemIDs.insert(ancestorID)
        }
    }
    
    /// 当焦点改变时，同步刷新状态并自动定位
    public func handleFocusChanged(_ context: FocusContext) {
        self.currentFocusContext = context
        self.currentActiveSource = inputSourceManager.currentSource
        let gran = granularityManager.effectiveGranularity(for: context.bundleID, isBrowser: context.isBrowserApp)
        self.currentFocusLockStatus = store.lockStatus(for: context, effectiveGranularity: gran)
        
        locateFocusedItem(for: context)
    }
    
    /// 设置开机自启
    public func setAutoStartEnabled(_ enabled: Bool) {
        autoStartManager.setAutoStartEnabled(enabled)
        self.isAutoStartEnabled = autoStartManager.isAutoStartEnabled
    }
}
