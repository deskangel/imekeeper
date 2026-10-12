import Foundation
import Combine

/// 设置面板与多层级树状大纲的响应式 ViewModel
@MainActor
public final class HierarchySettingsViewModel: ObservableObject {
    
    @Published public var hierarchyItems: [HierarchyItem] = []
    @Published public var availableSources: [InputSourceModel] = []
    @Published public var globalGranularity: GranularityLevel = .field
    @Published public var searchQuery: String = "" {
        didSet {
            refreshTree()
        }
    }
    @Published public var currentFocusContext: FocusContext?
    @Published public var currentActiveSource: InputSourceModel?
    @Published public var isEnabled: Bool = true
    
    public let store: HierarchicalProfileStore
    public let granularityManager: GranularityManager
    public let inputSourceManager: InputSourceManagerProtocol
    
    public init(
        store: HierarchicalProfileStore,
        granularityManager: GranularityManager,
        inputSourceManager: InputSourceManagerProtocol
    ) {
        self.store = store
        self.granularityManager = granularityManager
        self.inputSourceManager = inputSourceManager
        self.globalGranularity = granularityManager.getGlobalDefault()
        self.availableSources = inputSourceManager.availableSources
        self.currentActiveSource = inputSourceManager.currentSource
        
        refreshTree()
    }
    
    /// 刷新整棵大纲树
    public func refreshTree() {
        self.hierarchyItems = store.buildHierarchyItems(
            granularityManager: granularityManager,
            searchQuery: searchQuery
        )
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
    
    /// 删除某一层级节点
    public func deleteItem(_ item: HierarchyItem) {
        store.delete(item: item)
        refreshTree()
    }
    
    /// 设置某个 App 专属生效粒度
    public func setGranularity(for bundleID: String, level: GranularityLevel?) {
        granularityManager.setGranularity(for: bundleID, level: level)
        refreshTree()
    }
    
    /// 获取某个 App 的独立配置粒度
    public func configuredGranularity(for bundleID: String) -> GranularityLevel? {
        granularityManager.configuredGranularity(for: bundleID)
    }
    
    /// 设置全局生效默认粒度
    public func setGlobalGranularity(_ level: GranularityLevel) {
        granularityManager.setGlobalDefault(level)
        self.globalGranularity = level
        refreshTree()
    }
    
    /// 清除所有历史记录
    public func clearAllHistory() {
        store.clearAll()
        refreshTree()
    }
    
    /// 当焦点改变时，同步刷新状态
    public func handleFocusChanged(_ context: FocusContext) {
        self.currentFocusContext = context
        self.currentActiveSource = inputSourceManager.currentSource
    }
}
