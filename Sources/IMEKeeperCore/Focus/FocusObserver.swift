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
    }
    
    // MARK: - Notification Handling & Debounce
    
    private func handleAXNotification(element: AXUIElement, notification: String) {
        guard let runningApp = NSRunningApplication(processIdentifier: currentPid) else { return }
        scheduleFocusResolution(element: element, runningApp: runningApp)
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
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let context = self.fingerprinter.resolveFocusContext(
                from: element,
                runningApp: runningApp,
                isBrowserApp: isBrowser
            )
            handler?(context)
        }
        
        self.debounceWorkItem = workItem
        lock.unlock()
        
        let delay = DispatchTimeInterval.milliseconds(AppConstants.Timing.focusDebounceMilliseconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
