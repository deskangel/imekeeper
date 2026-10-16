import Foundation
import AppKit
import ApplicationServices

/// 系统级前台焦点事件与无障碍观察者管理器
public final class FocusObserver: @unchecked Sendable {
    
    private let lock = NSLock()
    private let fingerprinter = ElementFingerprinter()
    private let browserDetector = BrowserAppDetector()
    
    private var currentPid: pid_t = 0
    private var currentAXObserver: AXObserver?
    private var currentAppElement: AXUIElement?
    
    /// 上一个有效获得焦点的可编辑输入框元素与上下文（用于容器降级时的活跃性复查）
    private var lastFocusedInputElement: AXUIElement?
    private var lastFocusContext: FocusContext?
    
    private var debounceWorkItem: DispatchWorkItem?
    private var onFocusChangedHandler: (@Sendable (FocusContext) -> Void)?
    
    public init() {}
    
    deinit {
        stopObserving()
    }
    
    /// 开始全局焦点监听
    public func startObserving(onFocusChanged: @escaping @Sendable (FocusContext) -> Void) {
        lock.lock()
        self.onFocusChangedHandler = onFocusChanged
        lock.unlock()
        
        // 监听应用前后台切换
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleApplicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        // 初始化当前前台应用
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            attachToApp(frontApp)
        }
    }
    
    /// 停止全局焦点监听
    public func stopObserving() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        detachCurrentObserver()
        
        lock.lock()
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        onFocusChangedHandler = nil
        lock.unlock()
    }
    
    // MARK: - Observer Management
    
    @objc private func handleApplicationActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        if isSelfApplication(app) {
            detachCurrentObserver()
            return
        }
        attachToApp(app)
    }
    
    private func isSelfApplication(_ app: NSRunningApplication) -> Bool {
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return true
        }
        if let bundleID = app.bundleIdentifier,
           let myBundleID = Bundle.main.bundleIdentifier,
           bundleID == myBundleID {
            return true
        }
        return false
    }
    
    private func attachToApp(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid > 0, !isSelfApplication(app) else {
            detachCurrentObserver()
            return
        }
        
        detachCurrentObserver()
        
        let appElement = AXUIElementCreateApplication(pid)
        
        // 关键增强：为 Chromium / Electron 应用（如 VS Code、Antigravity IDE、Slack 等）激活无障碍树，
        // 否则内核默认不构建可编辑控件无障碍节点，也不会派发输入框焦点变化通知
        AXUIElementSetAttributeValue(
            appElement,
            AppConstants.Accessibility.manualAccessibilityAttribute as CFString,
            kCFBooleanTrue
        )
        AXUIElementSetAttributeValue(
            appElement,
            AppConstants.Accessibility.enhancedUserInterfaceAttribute as CFString,
            kCFBooleanTrue
        )
        
        var observerRef: AXObserver?
        
        let axCallback: AXObserverCallback = { observer, element, notificationName, refcon in
            guard let refcon = refcon else { return }
            let selfPtr = Unmanaged<FocusObserver>.fromOpaque(refcon).takeUnretainedValue()
            selfPtr.handleAXNotification(element: element, notification: notificationName as String)
        }
        
        let createStatus = AXObserverCreate(pid, axCallback, &observerRef)
        guard createStatus == .success, let observer = observerRef else {
            // 应用可能未响应或拒绝无障碍连接，做基础降级
            probeCurrentElementDirectly(for: app, appElement: appElement)
            return
        }
        
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        AXObserverAddNotification(observer, appElement, kAXFocusedUIElementChangedNotification as CFString, selfPointer)
        AXObserverAddNotification(observer, appElement, kAXFocusedWindowChangedNotification as CFString, selfPointer)
        
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        
        lock.lock()
        self.currentPid = pid
        self.currentAXObserver = observer
        self.currentAppElement = appElement
        lock.unlock()
        
        // 初始探查一次当前焦点
        probeCurrentElementDirectly(for: app, appElement: appElement)
    }
    
    private func detachCurrentObserver() {
        lock.lock()
        defer { lock.unlock() }
        
        if let observer = currentAXObserver, let appElement = currentAppElement {
            AXObserverRemoveNotification(observer, appElement, kAXFocusedUIElementChangedNotification as CFString)
            AXObserverRemoveNotification(observer, appElement, kAXFocusedWindowChangedNotification as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        currentAXObserver = nil
        currentAppElement = nil
        currentPid = 0
        lastFocusedInputElement = nil
        lastFocusContext = nil
    }
    
    // MARK: - Notification Handling & Debounce
    
    private func handleAXNotification(element: AXUIElement, notification: String) {
        guard let runningApp = NSRunningApplication(processIdentifier: currentPid) else { return }
        
        // 关键时序优化：若接收到的是窗口切换通知，优先探查应用内当前实际聚焦的输入控件，避免窗口元素覆盖输入框
        var targetElement = element
        if notification == (kAXFocusedWindowChangedNotification as String), let appElement = currentAppElement {
            var focusedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
               let focused = focusedRef {
                targetElement = (focused as! AXUIElement)
            }
        }
        
        scheduleFocusResolution(element: targetElement, runningApp: runningApp)
    }
    
    private func probeCurrentElementDirectly(for app: NSRunningApplication, appElement: AXUIElement) {
        var focusedElementRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementRef)
        
        if result == .success, let focusedRef = focusedElementRef {
            let element = (focusedRef as! AXUIElement)
            scheduleFocusResolution(element: element, runningApp: app)
        } else {
            // 没有获得具体输入框焦点，以窗口为基准
            var focusedWindowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
               let winRef = focusedWindowRef {
                let winElement = (winRef as! AXUIElement)
                scheduleFocusResolution(element: winElement, runningApp: app)
            }
        }
    }
    
    private func scheduleFocusResolution(element: AXUIElement, runningApp: NSRunningApplication) {
        guard !isSelfApplication(runningApp) else { return }
        
        lock.lock()
        debounceWorkItem?.cancel()
        
        let bundleID = runningApp.bundleIdentifier ?? ""
        let isBrowser = browserDetector.isBrowser(bundleID: bundleID)
        let handler = onFocusChangedHandler
        let appElement = currentAppElement
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // 防抖截止执行时，再次确认应用当前的精准焦点元素，防止窗口切换过渡期的瞬态状态污染
            var targetElement = element
            if let app = appElement {
                var focusedRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
                   let focused = focusedRef {
                    targetElement = (focused as! AXUIElement)
                }
            }
            
            // 核心增强：网页输入框弹窗/候选词保护（Previous Input Field Liveness Check）
            // 当焦点从具体的输入控件降级为顶层容器（AXApplication/AXWindow/AXWebArea）或下拉建议浮层时，
            // 探查上一个输入控件是否仍然持有光标选区或保持聚焦状态
            var finalElement = targetElement
            let isTargetInput = self.fingerprinter.determineIfInputField(
                element: targetElement,
                role: self.copyRole(from: targetElement),
                subrole: nil
            )
            
            if !isTargetInput,
               let lastInput = self.lastFocusedInputElement,
               let lastContext = self.lastFocusContext,
               lastContext.bundleID == bundleID,
               self.checkElementStillHasCaretOrFocus(lastInput) {
                finalElement = lastInput
            }
            
            let context = self.fingerprinter.resolveFocusContext(
                from: finalElement,
                runningApp: runningApp,
                isBrowserApp: isBrowser
            )
            
            if context.isInputField {
                self.lastFocusedInputElement = finalElement
                self.lastFocusContext = context
            }
            
            // 抓取现场属性快照并写入调试日志
            let snapshot = ElementAttributeSnapshot.capture(from: finalElement)
            DebugLogger.shared.logFocusEvent(context: context, snapshot: snapshot)
            
            handler?(context)
        }
        
        self.debounceWorkItem = workItem
        lock.unlock()
        
        let delay = DispatchTimeInterval.milliseconds(AppConstants.Timing.focusDebounceMilliseconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    private func copyRole(from element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let roleStr = roleRef as? String else {
            return nil
        }
        return roleStr
    }
    
    private func checkElementStillHasCaretOrFocus(_ element: AXUIElement) -> Bool {
        // 1. 检查元素是否仍持有无障碍焦点
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &focusedRef) == .success,
           let isFocused = focusedRef as? Bool, isFocused {
            return true
        }
        
        // 2. 检查元素是否仍持有文本选区/光标（CFRange）
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeValue = rangeRef {
            if CFGetTypeID(rangeValue) == AXValueGetTypeID() {
                let axVal = rangeValue as! AXValue
                if AXValueGetType(axVal) == .cfRange {
                    var range = CFRange(location: 0, length: 0)
                    if AXValueGetValue(axVal, .cfRange, &range) {
                        return true
                    }
                }
            }
        }
        
        // 3. 检查元素是否仍持有光标行号
        var lineRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXInsertionPointLineNumberAttribute as CFString, &lineRef) == .success,
           lineRef != nil {
            return true
        }
        
        return false
    }
}
