import Foundation
import Carbon

/// 基于 macOS Carbon HIToolbox 的原生键盘输入法管理器
public final class CarbonInputSourceManager: @unchecked Sendable, InputSourceManagerProtocol {
    
    private let lock = NSLock()
    private var _cachedAvailableSources: [InputSourceModel] = []
    private var _onUserChangedSource: (@Sendable (InputSourceModel) -> Void)?
    
    /// 防回环抑制状态：记录由程序化发起切换的目标 ID 与抑制有效期截止时间
    private var suppressedTargetSourceID: String?
    private var suppressedUntilDate: Date?
    
    /// 最近一次向外分发（或程序化设置）的生效输入源 ID，用于严格去重
    private var lastDispatchedSourceID: String?
    
    public init() {
        reloadAvailableSources()
        lock.lock()
        lastDispatchedSourceID = currentSourceWithoutLock.id
        lock.unlock()
        setupNotificationObserver()
    }
    
    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }
    
    public var currentSource: InputSourceModel {
        lock.lock()
        defer { lock.unlock() }
        
        guard let currentTIS = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return InputSourceModel.unknown(id: AppConstants.InputSource.defaultAsciiSourceID)
        }
        return parseInputSource(currentTIS, isCurrent: true)
    }
    
    public var availableSources: [InputSourceModel] {
        lock.lock()
        defer { lock.unlock() }
        return _cachedAvailableSources
    }
    
    public func reloadAvailableSources() {
        lock.lock()
        defer { lock.unlock() }
        
        let filterProperties = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource
        ] as CFDictionary
        
        guard let sourceListRef = TISCreateInputSourceList(filterProperties, false)?.takeRetainedValue() as? [TISInputSource] else {
            _cachedAvailableSources = []
            return
        }
        
        var parsed: [InputSourceModel] = []
        let currentID = currentSourceWithoutLock.id
        
        for source in sourceListRef {
            // 过滤不可选择的源
            guard let isSelectablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else {
                continue
            }
            let isSelectable = Unmanaged<CFBoolean>.fromOpaque(isSelectablePtr).takeUnretainedValue()
            if !CFBooleanGetValue(isSelectable) {
                continue
            }
            
            let model = parseInputSource(source, isCurrent: false)
            let finalModel = InputSourceModel(
                id: model.id,
                localizedName: model.localizedName,
                isAsciiCapable: model.isAsciiCapable,
                isCurrent: (model.id == currentID)
            )
            parsed.append(finalModel)
        }
        
        // 去重并按本地化名称排序
        var uniqueDict: [String: InputSourceModel] = [:]
        for item in parsed {
            uniqueDict[item.id] = item
        }
        _cachedAvailableSources = uniqueDict.values.sorted { $0.localizedName < $1.localizedName }
    }
    
    @discardableResult
    public func selectSource(id sourceID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        // 如果当前已经是目标输入法，无需触发 Carbon 调用
        if currentSourceWithoutLock.id == sourceID {
            return true
        }
        
        guard let targetTIS = findTISInputSource(by: sourceID) else {
            return false
        }
        
        // 设置防回环抑制窗口与分发缓存
        suppressedTargetSourceID = sourceID
        suppressedUntilDate = Date().addingTimeInterval(AppConstants.Timing.antiLoopSuppressionTimeoutSeconds)
        lastDispatchedSourceID = sourceID
        
        let status = TISSelectInputSource(targetTIS)
        return status == noErr
    }
    
    public func setOnUserChangedSourceHandler(_ handler: (@Sendable (InputSourceModel) -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        _onUserChangedSource = handler
    }
    
    // MARK: - Private Helpers
    
    private var currentSourceWithoutLock: InputSourceModel {
        guard let currentTIS = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return InputSourceModel.unknown(id: AppConstants.InputSource.defaultAsciiSourceID)
        }
        return parseInputSource(currentTIS, isCurrent: true)
    }
    
    private func parseInputSource(_ source: TISInputSource, isCurrent: Bool) -> InputSourceModel {
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return InputSourceModel.unknown(id: AppConstants.InputSource.defaultAsciiSourceID)
        }
        let idString = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        
        var nameString = idString
        if let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            nameString = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
        }
        
        var isAscii = false
        if let asciiPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) {
            let cfBool = Unmanaged<CFBoolean>.fromOpaque(asciiPtr).takeUnretainedValue()
            isAscii = CFBooleanGetValue(cfBool)
        }
        
        return InputSourceModel(
            id: idString,
            localizedName: nameString,
            isAsciiCapable: isAscii,
            isCurrent: isCurrent
        )
    }
    
    private func findTISInputSource(by id: String) -> TISInputSource? {
        let filterProperties = [
            kTISPropertyInputSourceID: id as CFString
        ] as CFDictionary
        
        guard let sourceListRef = TISCreateInputSourceList(filterProperties, false)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        return sourceListRef.first
    }
    
    private func setupNotificationObserver() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleInputSourceChangedNotification(_:)),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }
    
    @objc private func handleInputSourceChangedNotification(_ notification: Notification) {
        lock.lock()
        let now = Date()
        let activeSource = currentSourceWithoutLock
        
        // 检查防回环抑制：在抑制有效期内持续抑制目标输入法，切勿在首次收到广播时提前清空标记
        if let target = suppressedTargetSourceID,
           let timeout = suppressedUntilDate {
            if now <= timeout {
                if activeSource.id == target {
                    // 程序化发起的切换：持续静默忽略 macOS HIToolbox 的重复广播
                    lock.unlock()
                    return
                }
            } else {
                // 超时已过，清理过期标记
                suppressedTargetSourceID = nil
                suppressedUntilDate = nil
            }
        }
        
        // 重复广播去重：当前源与最近一次分发/设置的源相同，直接短路忽略
        if activeSource.id == lastDispatchedSourceID {
            lock.unlock()
            return
        }
        
        // 确认是有效的新状态变更，消费过期的抑制标记并更新最后分发记录
        suppressedTargetSourceID = nil
        suppressedUntilDate = nil
        lastDispatchedSourceID = activeSource.id
        
        let callback = _onUserChangedSource
        lock.unlock()
        
        // 用户手动切换，分发回调
        callback?(activeSource)
    }
}
