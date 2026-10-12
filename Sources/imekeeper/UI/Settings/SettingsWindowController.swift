import AppKit
import SwiftUI
import IMEKeeperCore

/// 设置窗口控制器
@MainActor
public final class SettingsWindowController {
    
    private var window: NSWindow?
    private let viewModel: HierarchySettingsViewModel
    
    public init(viewModel: HierarchySettingsViewModel) {
        self.viewModel = viewModel
    }
    
    /// 动态刷新窗口标题
    public func updateTitle() {
        window?.title = L10n.settingsWindowTitle
    }
    
    /// 显示设置窗口并激活至最前
    public func showWindow() {
        if let existing = window {
            existing.title = L10n.settingsWindowTitle
            existing.level = .floating
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let contentView = HierarchySettingsView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: contentView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: AppConstants.UI.settingsWindowWidth,
                height: AppConstants.UI.settingsWindowHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = L10n.settingsWindowTitle
        newWindow.contentViewController = hostingController
        newWindow.level = .floating
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        newWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}
