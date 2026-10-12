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
    
    /// 显示设置窗口并激活至最前
    public func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
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
        
        newWindow.title = "IME Keeper - 层级记忆与偏好设置"
        newWindow.contentViewController = hostingController
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
