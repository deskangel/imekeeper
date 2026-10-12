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
    @Published public var currentFocusLockStatus: HierarchyItem.LockStatus = .unlocked
    @Published public var currentActiveSource: InputSourceModel?
    @Published public var isEnabled: Bool = true
    @Published public var currentLanguage: AppLanguage = LocalizationManager.shared.currentLanguage
    
    public let store: HierarchicalProfileStore
    public let granularityManager: GranularityManager
    public let inputSourceManager: InputSourceManagerProtocol
    private var cancellables = Set<AnyCancellable>()
    
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
        
        refreshTree()
    }
    
    /// 设置应用程序语言
    public func setLanguage(_ language: AppLanguage) {
        LocalizationManager.shared.setLanguage(language)
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
    
    /// 切换某一层级节点的锁定状态
    public func toggleLock(for item: HierarchyItem) {
        store.toggleLock(for: item)
        refreshTree()
        if let context = currentFocusContext {
            let gran = granularityManager.effectiveGranularity(for: context.bundleID, isBrowser: context.isBrowserApp)
            self.currentFocusLockStatus = store.lockStatus(for: context, effectiveGranularity: gran)
        }
    }
    
    /// 当焦点改变时，同步刷新状态
    public func handleFocusChanged(_ context: FocusContext) {
        self.currentFocusContext = context
        self.currentActiveSource = inputSourceManager.currentSource
        let gran = granularityManager.effectiveGranularity(for: context.bundleID, isBrowser: context.isBrowserApp)
        self.currentFocusLockStatus = store.lockStatus(for: context, effectiveGranularity: gran)
    }
}
