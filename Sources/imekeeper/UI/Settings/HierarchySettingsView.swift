import SwiftUI
import IMEKeeperCore

/// 多层级输入法记忆管理与生效粒度控制设置面板
public struct HierarchySettingsView: View {
    @ObservedObject public var viewModel: HierarchySettingsViewModel
    
    public init(viewModel: HierarchySettingsViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部操作栏与全局控制
            topControlBar
            
            Divider()
            
            // 2. 实时焦点状态看板 (Live Status Bar)
            liveStatusBar
            
            Divider()
            
            // 3. 树状大纲层级视图
            if viewModel.hierarchyItems.isEmpty {
                emptyPlaceholderView
            } else {
                treeOutlineListView
            }
            
            Divider()
            
            // 4. 底部说明与操作栏
            bottomFooterBar
        }
        .frame(
            minWidth: AppConstants.UI.minSettingsWindowWidth,
            idealWidth: AppConstants.UI.settingsWindowWidth,
            minHeight: AppConstants.UI.minSettingsWindowHeight,
            idealHeight: AppConstants.UI.settingsWindowHeight
        )
    }
    
    // MARK: - Subviews
    
    private var topControlBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("IME Keeper")
                    .font(.headline)
                Text("按层级组织管理各窗口与输入框的输入法记忆")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 搜索过滤框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索应用或窗口...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .frame(width: 160)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            
            // 全局默认粒度
            Picker("全局默认粒度:", selection: Binding(
                get: { viewModel.globalGranularity },
                set: { viewModel.setGlobalGranularity($0) }
            )) {
                ForEach(GranularityLevel.allCases) { level in
                    Label(level.localizedName, systemImage: level.iconName).tag(level)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 180)
            
            // 全局启用开关
            Toggle("", isOn: $viewModel.isEnabled)
                .toggleStyle(.switch)
                .help("启用/暂停自动切换输入法")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var liveStatusBar: some View {
        HStack(spacing: 16) {
            Label {
                Text(viewModel.isEnabled ? "正在监控焦点" : "已暂停")
                    .font(.caption.bold())
            } icon: {
                Circle()
                    .fill(viewModel.isEnabled ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
            }
            
            if let context = viewModel.currentFocusContext {
                Divider().frame(height: 12)
                
                HStack(spacing: 4) {
                    Text("当前聚焦:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let icon = AppIconProvider.shared.icon(for: context.bundleID) {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: AppConstants.UI.liveStatusAppIconSize, height: AppConstants.UI.liveStatusAppIconSize)
                    }
                    Text(context.appName)
                        .font(.caption.bold())
                    Text("›")
                        .foregroundColor(.secondary)
                    Text(context.windowTitle)
                        .font(.caption)
                        .lineLimit(1)
                    if let field = context.fieldDescription {
                        Text("›")
                            .foregroundColor(.secondary)
                        Text(field)
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .lineLimit(1)
                    }
                    
                    // 实时焦点锁定状态徽标
                    liveFocusLockBadge
                }
            }
            
            Spacer()
            
            if let current = viewModel.currentActiveSource {
                HStack(spacing: 4) {
                    Text("活跃输入法:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(current.localizedName)
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    @ViewBuilder
    private var liveFocusLockBadge: some View {
        switch viewModel.currentFocusLockStatus {
        case .locked(let level):
            HStack(spacing: 2) {
                Image(systemName: AppConstants.LockUI.lockedIconName)
                    .font(.system(size: AppConstants.LockUI.lockIconSize))
                Text(level.localizedName + AppConstants.LockUI.lockActionText)
                    .font(.system(size: AppConstants.LockUI.lockTextSize, weight: .semibold))
            }
            .padding(.horizontal, AppConstants.LockUI.badgePaddingHorizontal)
            .padding(.vertical, AppConstants.LockUI.badgePaddingVertical)
            .background(levelColor(for: level).opacity(0.15))
            .foregroundColor(levelColor(for: level))
            .clipShape(Capsule())
        case .inherited(let level):
            HStack(spacing: 2) {
                Image(systemName: AppConstants.LockUI.lockedIconName)
                    .font(.system(size: AppConstants.LockUI.lockIconSize))
                Text(AppConstants.LockUI.inheritedLockBadgeTextPrefix + level.localizedName + AppConstants.LockUI.lockActionText)
                    .font(.system(size: AppConstants.LockUI.lockTextSize))
            }
            .padding(.horizontal, AppConstants.LockUI.badgePaddingHorizontal)
            .padding(.vertical, AppConstants.LockUI.badgePaddingVertical)
            .background(Color.secondary.opacity(0.12))
            .foregroundColor(.secondary)
            .clipShape(Capsule())
        case .unlocked:
            EmptyView()
        }
    }
    
    private var treeOutlineListView: some View {
        List {
            OutlineGroup(viewModel.hierarchyItems, children: \.children) { item in
                HierarchyRowView(
                    item: item,
                    availableSources: viewModel.availableSources,
                    onUpdateSource: { newSourceID in
                        viewModel.updateSource(for: item, newSourceID: newSourceID)
                    },
                    onToggleLock: {
                        viewModel.toggleLock(for: item)
                    },
                    onDelete: {
                        viewModel.deleteItem(item)
                    },
                    onChangeGranularity: { bundleID, newLevel in
                        viewModel.setGranularity(for: bundleID, level: newLevel)
                    }
                )
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }
    
    private var emptyPlaceholderView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("暂无捕获到的输入框记忆记录")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("在其他应用中点击输入框或切换输入法后，将在此自动按层级记录。")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var bottomFooterBar: some View {
        HStack {
            Button(role: .destructive) {
                viewModel.clearAllHistory()
            } label: {
                Label("清空所有历史", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            
            Spacer()
            
            Button("刷新可用输入法") {
                viewModel.reloadInputSources()
            }
            .buttonStyle(.bordered)
            
            Button("完成") {
                NSApp.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Row View

private func levelColor(for level: GranularityLevel) -> Color {
    switch level {
    case .app: return .blue
    case .window: return .purple
    case .field: return .orange
    }
}

private struct HierarchyRowView: View {
    let item: HierarchyItem
    let availableSources: [InputSourceModel]
    let onUpdateSource: (String) -> Void
    let onToggleLock: () -> Void
    let onDelete: () -> Void
    let onChangeGranularity: (String, GranularityLevel?) -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // 图标
            itemIcon
            
            // 标题与副标题
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13, weight: isAppNode ? .semibold : .regular))
                    .lineLimit(1)
                
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // 锁定控制按钮与状态
            lockControlButton
            
            // 如果是 App 节点，提供生效粒度调节器
            if case .app(let bundleID, let currentGranularity) = item.itemType {
                granularityPicker(bundleID: bundleID, current: currentGranularity)
            }
            
            // 输入法选择器
            inputSourcePicker
            
            // 删除按钮
            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("删除此项记忆")
        }
        .frame(height: AppConstants.UI.treeRowHeight)
    }
    
    private var isAppNode: Bool {
        if case .app = item.itemType { return true }
        return false
    }
    
    private var lockControlButton: some View {
        Button {
            onToggleLock()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: lockIconName)
                    .font(.system(size: AppConstants.LockUI.lockIconSize))
                Text(lockBadgeText)
                    .font(.system(size: AppConstants.LockUI.lockTextSize, weight: item.isLocked ? .semibold : .regular))
                    .lineLimit(1)
            }
            .frame(width: AppConstants.LockUI.lockButtonWidth)
            .padding(.vertical, AppConstants.LockUI.badgePaddingVertical)
            .background(lockBadgeBackground)
            .foregroundColor(lockBadgeForeground)
            .cornerRadius(AppConstants.UI.badgeCornerRadius)
        }
        .buttonStyle(.plain)
        .help(lockHelpText)
    }
    
    private var lockIconName: String {
        if item.isLocked || item.lockStatus.isProtected {
            return AppConstants.LockUI.lockedIconName
        }
        return AppConstants.LockUI.unlockedIconName
    }
    
    private var lockBadgeText: String {
        switch item.lockStatus {
        case .locked(let level):
            switch level {
            case .app: return AppConstants.LockUI.appLockBadgeText
            case .window: return AppConstants.LockUI.windowLockBadgeText
            case .field: return AppConstants.LockUI.fieldLockBadgeText
            }
        case .inherited(let level):
            return AppConstants.LockUI.inheritedLockBadgeTextPrefix + level.localizedName
        case .unlocked:
            return AppConstants.LockUI.unlockedActionText
        }
    }
    
    private var lockBadgeForeground: Color {
        switch item.lockStatus {
        case .locked(let level):
            return levelColor(for: level)
        case .inherited:
            return .secondary
        case .unlocked:
            return .secondary.opacity(0.8)
        }
    }
    
    private var lockBadgeBackground: Color {
        switch item.lockStatus {
        case .locked(let level):
            return levelColor(for: level).opacity(0.15)
        case .inherited:
            return Color.secondary.opacity(0.12)
        case .unlocked:
            return Color(nsColor: .controlBackgroundColor)
        }
    }
    
    private var lockHelpText: String {
        switch item.lockStatus {
        case .locked(let level):
            switch level {
            case .app: return AppConstants.LockUI.appLockHelpText
            case .window: return AppConstants.LockUI.windowLockHelpText
            case .field: return AppConstants.LockUI.fieldLockHelpText
            }
        case .inherited:
            return AppConstants.LockUI.inheritedLockHelpText
        case .unlocked:
            return AppConstants.LockUI.unlockedHelpText
        }
    }
    
    @ViewBuilder
    private var itemIcon: some View {
        switch item.itemType {
        case .app(let bundleID, _):
            if let icon = AppIconProvider.shared.icon(for: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: AppConstants.UI.appRowIconSize, height: AppConstants.UI.appRowIconSize)
            } else {
                Image(systemName: "app.fill")
                    .foregroundColor(.blue)
                    .frame(width: AppConstants.UI.appRowIconSize, height: AppConstants.UI.appRowIconSize)
            }
        case .window:
            Image(systemName: "macwindow")
                .foregroundColor(.purple)
        case .field:
            Image(systemName: "character.cursor.ibeam")
                .foregroundColor(.orange)
        }
    }
    
    private func granularityPicker(bundleID: String, current: GranularityLevel) -> some View {
        Picker("", selection: Binding(
            get: { current },
            set: { newLevel in
                onChangeGranularity(bundleID, newLevel)
            }
        )) {
            ForEach(GranularityLevel.allCases) { level in
                Text(level.localizedName).tag(level)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 135)
        .help("设置该应用允许生效的最大追踪粒度")
    }
    
    private var inputSourcePicker: some View {
        Picker("", selection: Binding(
            get: { item.currentSourceID },
            set: { newID in
                onUpdateSource(newID)
            }
        )) {
            ForEach(availableSources) { source in
                Text(source.localizedName).tag(source.id)
            }
            // 若不在列表中，保留原 ID 项
            if !availableSources.contains(where: { $0.id == item.currentSourceID }) {
                Text(item.currentSourceID).tag(item.currentSourceID)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 150)
    }
}
