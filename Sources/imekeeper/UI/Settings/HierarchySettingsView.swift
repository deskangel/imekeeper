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
                .font(.system(size: AppConstants.UI.headerIconSize))
                .foregroundColor(.accentColor)
            
            Text("IME Keeper")
                .font(.headline)
            
            Spacer()
            
            // 搜索过滤框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(L10n.searchPlaceholder, text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .frame(width: AppConstants.UI.searchFieldWidth)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: AppConstants.UI.searchFieldCornerRadius).fill(Color(nsColor: .controlBackgroundColor)))
            
            // 全局默认粒度
            Picker(L10n.defaultGranularityLabel, selection: Binding(
                get: { viewModel.globalGranularity },
                set: { viewModel.setGlobalGranularity($0) }
            )) {
                ForEach(GranularityLevel.allCases) { level in
                    Label(level.localizedName, systemImage: level.iconName).tag(level)
                }
            }
            .pickerStyle(.menu)
            .frame(width: AppConstants.UI.globalGranularityPickerWidth)
            
            // 全局非输入框行为
            Picker(L10n.globalNonInputLabel, selection: Binding(
                get: { viewModel.globalNonInputPolicy },
                set: { viewModel.setGlobalNonInputPolicy($0) }
            )) {
                Text(L10n.nonInputPolicyName(for: .alwaysEnglish)).tag(NonInputPolicy.alwaysEnglish)
                Text(L10n.nonInputPolicyName(for: .exempt)).tag(NonInputPolicy.exempt)
            }
            .pickerStyle(.menu)
            .frame(width: AppConstants.UI.globalGranularityPickerWidth)
            .help(L10n.globalNonInputHelp)
            
            // 全局启用开关
            Toggle("", isOn: $viewModel.isEnabled)
                .toggleStyle(.switch)
                .help(L10n.toggleSwitchHelp)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var liveStatusBar: some View {
        HStack(spacing: 16) {
            Label {
                Text(viewModel.isEnabled ? L10n.liveMonitoringFocus : L10n.liveFocusPaused)
                    .font(.caption.bold())
            } icon: {
                Circle()
                    .fill(viewModel.isEnabled ? Color.green : Color.orange)
                    .frame(width: AppConstants.UI.liveStatusIndicatorSize, height: AppConstants.UI.liveStatusIndicatorSize)
            }
            
            if let context = viewModel.currentFocusContext {
                Divider().frame(height: 12)
                
                HStack(spacing: 4) {
                    Text(L10n.liveFocusedPrefix)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    AppRowIconView(bundleID: context.bundleID, iconSize: AppConstants.UI.liveStatusAppIconSize)
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
                }
            }
            
            Spacer()
            
            if let current = viewModel.currentActiveSource {
                HStack(spacing: 4) {
                    Text(L10n.liveActiveSourcePrefix)
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
    
    private var treeOutlineListView: some View {
        ScrollViewReader { proxy in
            List(selection: $viewModel.selectedItemID) {
                ForEach(viewModel.hierarchyItems) { appItem in
                    if let windowItems = appItem.children, !windowItems.isEmpty {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { viewModel.isExpanded(appItem.id) },
                                set: { viewModel.setExpanded(appItem.id, isExpanded: $0) }
                            )
                        ) {
                            ForEach(windowItems) { winItem in
                                if let fieldItems = winItem.children, !fieldItems.isEmpty {
                                    DisclosureGroup(
                                        isExpanded: Binding(
                                            get: { viewModel.isExpanded(winItem.id) },
                                            set: { viewModel.setExpanded(winItem.id, isExpanded: $0) }
                                        )
                                    ) {
                                        ForEach(fieldItems) { fieldItem in
                                            rowView(for: fieldItem)
                                                .tag(fieldItem.id)
                                        }
                                    } label: {
                                        rowView(for: winItem)
                                    }
                                    .tag(winItem.id)
                                } else {
                                    rowView(for: winItem)
                                        .tag(winItem.id)
                                }
                            }
                        } label: {
                            rowView(for: appItem)
                        }
                        .tag(appItem.id)
                    } else {
                        rowView(for: appItem)
                            .tag(appItem.id)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .onChange(of: viewModel.selectedItemID) { targetID in
                scrollToTarget(targetID, proxy: proxy)
            }
            .onChange(of: viewModel.currentFocusContext) { _ in
                scrollToTarget(viewModel.selectedItemID, proxy: proxy)
            }
            .onAppear {
                viewModel.openPreferences()
                scrollToTarget(viewModel.selectedItemID, proxy: proxy)
            }
        }
    }
    
    @ViewBuilder
    private func rowView(for item: HierarchyItem) -> some View {
        HierarchyRowView(
            item: item,
            isSelected: viewModel.selectedItemID == item.id,
            availableSources: viewModel.availableSources,
            onUpdateSource: { newSourceID in
                viewModel.updateSource(for: item, newSourceID: newSourceID)
            },
            onToggleLock: {
                viewModel.toggleLock(for: item)
            },
            onClean: {
                viewModel.cleanItem(item)
            },
            onDelete: {
                viewModel.deleteItem(item)
            },
            onChangeGranularity: { bundleID, newLevel in
                viewModel.setGranularity(for: bundleID, level: newLevel)
            },
            onChangeNonInputPolicy: { bundleID, newPolicy in
                viewModel.setNonInputPolicy(for: bundleID, policy: newPolicy)
            },
            onRenameField: { newName in
                viewModel.renameField(item: item, newName: newName)
            }
        )
        .equatable()
    }
    
    private func scrollToTarget(_ targetID: String?, proxy: ScrollViewProxy) {
        guard let targetID = targetID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.UI.autoScrollDelay) {
            withAnimation(.easeInOut(duration: AppConstants.UI.autoScrollAnimationDuration)) {
                proxy.scrollTo(targetID, anchor: .center)
            }
        }
    }
    
    private var emptyPlaceholderView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: AppConstants.UI.emptyPlaceholderIconSize))
                .foregroundColor(.secondary)
            Text(L10n.emptyHistoryTitle)
                .font(.headline)
                .foregroundColor(.secondary)
            Text(L10n.emptyHistorySubtitle)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var bottomFooterBar: some View {
        HStack(spacing: AppConstants.UI.footerSpacing) {
            Toggle(L10n.launchAtLoginCheckbox, isOn: Binding(
                get: { viewModel.isAutoStartEnabled },
                set: { viewModel.setAutoStartEnabled($0) }
            ))
            .toggleStyle(.checkbox)
            .help(L10n.launchAtLoginHelp)
            
            Toggle(L10n.debugLoggingCheckbox, isOn: Binding(
                get: { viewModel.isDebugLoggingEnabled },
                set: { viewModel.setDebugLoggingEnabled($0) }
            ))
            .toggleStyle(.checkbox)
            .help(L10n.debugLoggingHelp)
            
            Spacer()
            
            Button {
                viewModel.cleanAllRedundantSubItems()
            } label: {
                Label(L10n.cleanAllRedundantButton, systemImage: AppConstants.UI.cleanButtonIconName)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.hasRedundantSubItems)
            .help(L10n.cleanAllRedundantHelp)
            
            Button(L10n.reloadInputSources) {
                viewModel.reloadInputSources()
            }
            .buttonStyle(.bordered)
            
            Button(L10n.doneButton) {
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
    case .field: return .orange
    }
}

/// 异步非阻塞应用图标视图：优先走内存 O(1) 缓存，未命中时展示占位符并后台异步加载回填，杜绝主线程卡顿
struct AppRowIconView: View {
    let bundleID: String
    var iconSize: CGFloat = AppConstants.UI.appRowIconSize
    @State private var loadedIcon: NSImage?
    
    var body: some View {
        Group {
            if let icon = displayIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
            } else {
                Image(systemName: "app.fill")
                    .foregroundColor(.blue)
                    .frame(width: iconSize, height: iconSize)
            }
        }
        .task(id: bundleID) {
            if loadedIcon == nil && AppIconProvider.shared.cachedIcon(for: bundleID) == nil {
                let resolved = await AppIconProvider.shared.asyncIcon(for: bundleID)
                await MainActor.run {
                    self.loadedIcon = resolved
                }
            }
        }
    }
    
    private var displayIcon: NSImage? {
        loadedIcon ?? AppIconProvider.shared.cachedIcon(for: bundleID)
    }
}

private struct HierarchyRowView: View, Equatable {
    let item: HierarchyItem
    let isSelected: Bool
    let availableSources: [InputSourceModel]
    let onUpdateSource: (String) -> Void
    let onToggleLock: () -> Void
    let onClean: () -> Void
    let onDelete: () -> Void
    let onChangeGranularity: (String, GranularityLevel?) -> Void
    let onChangeNonInputPolicy: (String, NonInputPolicy) -> Void
    let onRenameField: ((String) -> Void)?
    
    @State private var isLockHovered: Bool = false
    @State private var isCleanHovered: Bool = false
    @State private var isDeleteHovered: Bool = false
    @State private var isEditingTitle: Bool = false
    @State private var editingText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    nonisolated static func == (lhs: HierarchyRowView, rhs: HierarchyRowView) -> Bool {
        lhs.isSelected == rhs.isSelected &&
        lhs.item.id == rhs.item.id &&
        lhs.item.title == rhs.item.title &&
        lhs.item.subtitle == rhs.item.subtitle &&
        lhs.item.hashSubtitle == rhs.item.hashSubtitle &&
        lhs.item.itemType == rhs.item.itemType &&
        lhs.item.currentSourceID == rhs.item.currentSourceID &&
        lhs.item.isLocked == rhs.item.isLocked &&
        lhs.item.lockStatus == rhs.item.lockStatus &&
        lhs.item.canCleanSubItems == rhs.item.canCleanSubItems &&
        lhs.availableSources == rhs.availableSources
    }
    
    var body: some View {
        HStack(spacing: AppConstants.UI.rowContentSpacing) {
            // 选中指示条
            RoundedRectangle(cornerRadius: AppConstants.UI.rowSelectionIndicatorCornerRadius)
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(
                    width: AppConstants.UI.rowSelectionIndicatorWidth,
                    height: AppConstants.UI.rowSelectionIndicatorHeight
                )
            
            // 图标
            itemIcon
            
            // 标题、副标题与哈希值
            VStack(alignment: .leading, spacing: AppConstants.UI.rowTextSpacing) {
                if isEditingTitle {
                    TextField("", text: $editingText)
                        .textFieldStyle(.plain)
                        .font(.system(size: AppConstants.UI.rowTitleFontSize, weight: .regular))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: AppConstants.UI.renameFieldCornerRadius)
                                .stroke(Color.accentColor, lineWidth: AppConstants.UI.renameFieldBorderWidth)
                                .background(Color(nsColor: .controlBackgroundColor))
                        )
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            commitRename()
                        }
                        .onExitCommand {
                            cancelRename()
                        }
                        .onChange(of: isTextFieldFocused) { focused in
                            if !focused && isEditingTitle {
                                commitRename()
                            }
                        }
                } else {
                    Text(item.title)
                        .font(.system(size: AppConstants.UI.rowTitleFontSize, weight: (isAppNode || isSelected) ? .semibold : .regular))
                        .foregroundColor(isSelected ? .accentColor : .primary)
                        .lineLimit(1)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            if isFieldNode {
                                startRenaming()
                            }
                        }
                        .help(isFieldNode ? L10n.doubleClickToRenameHelp : "")
                }
                
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: AppConstants.UI.rowSubtitleFontSize))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if let hashSubtitle = item.hashSubtitle {
                    Text(hashSubtitle)
                        .font(.system(size: AppConstants.UI.rowHashFontSize, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.85))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // 如果是 App 节点，提供生效粒度调节器与非输入策略调节器
            if case .app(let bundleID, let currentGranularity, let currentPolicy) = item.itemType {
                granularityMenu(bundleID: bundleID, current: currentGranularity)
                nonInputPolicyMenu(bundleID: bundleID, current: currentPolicy)
            }
            
            // 输入法选择器
            inputSourceMenu
            
            // 锁定控制按钮（纯图标按钮，带悬停反馈）
            lockControlButton
            
            // 清理冗余下级记录按钮
            if item.isCleanActionAvailable {
                cleanControlButton
            }
            
            // 删除按钮
            deleteControlButton
        }
        .padding(.horizontal, AppConstants.UI.rowHorizontalPadding)
        .frame(height: isFieldNode ? AppConstants.UI.fieldTreeRowHeight : AppConstants.UI.treeRowHeight)
        .background(
            RoundedRectangle(cornerRadius: AppConstants.UI.rowSelectionCornerRadius)
                .fill(isSelected ? Color.accentColor.opacity(AppConstants.UI.rowSelectionBackgroundOpacity) : Color.clear)
        )
        .contentShape(Rectangle())
    }
    
    private var isAppNode: Bool {
        if case .app = item.itemType { return true }
        return false
    }
    
    private var isFieldNode: Bool {
        if case .field = item.itemType { return true }
        return false
    }
    
    private func startRenaming() {
        editingText = item.title
        isEditingTitle = true
        isTextFieldFocused = true
    }
    
    private func commitRename() {
        guard isEditingTitle else { return }
        isEditingTitle = false
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != item.title {
            onRenameField?(trimmed)
        }
    }
    
    private func cancelRename() {
        isEditingTitle = false
        editingText = ""
    }
    
    private var lockControlButton: some View {
        Button {
            onToggleLock()
        } label: {
            Image(systemName: lockIconName)
                .font(.system(size: AppConstants.LockUI.lockIconSize, weight: .medium))
                .foregroundColor(lockButtonForegroundColor)
                .frame(width: AppConstants.UI.actionButtonSize, height: AppConstants.UI.actionButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: AppConstants.UI.actionButtonCornerRadius)
                        .fill(lockButtonHoverBackground)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isLockHovered = hovering
        }
        .help(lockHelpText)
    }
    
    private var cleanControlButton: some View {
        Button {
            onClean()
        } label: {
            Image(systemName: AppConstants.UI.cleanButtonIconName)
                .font(.system(size: AppConstants.UI.cleanButtonFontSize, weight: .medium))
                .foregroundColor(cleanButtonForegroundColor)
                .frame(width: AppConstants.UI.actionButtonSize, height: AppConstants.UI.actionButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: AppConstants.UI.actionButtonCornerRadius)
                        .fill(cleanButtonHoverBackground)
                )
        }
        .buttonStyle(.plain)
        .disabled(!item.canCleanSubItems)
        .onHover { hovering in
            isCleanHovered = hovering
        }
        .help(cleanHelpText)
    }
    
    private var deleteControlButton: some View {
        Button {
            onDelete()
        } label: {
            Image(systemName: "trash")
                .font(.system(size: AppConstants.UI.deleteButtonFontSize, weight: .medium))
                .foregroundColor(deleteButtonForegroundColor)
                .frame(width: AppConstants.UI.actionButtonSize, height: AppConstants.UI.actionButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: AppConstants.UI.actionButtonCornerRadius)
                        .fill(deleteButtonHoverBackground)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isDeleteHovered = hovering
        }
        .help(L10n.deleteItemHelp)
    }
    
    private var lockButtonHoverBackground: Color {
        if isLockHovered {
            switch item.lockStatus {
            case .locked(let level):
                return isSelected
                    ? Color.white.opacity(AppConstants.UI.selectedRowButtonHoverBackgroundOpacity)
                    : levelColor(for: level).opacity(AppConstants.UI.lockButtonHoverOpacity)
            case .inherited:
                return isSelected
                    ? Color.white.opacity(AppConstants.UI.selectedRowButtonHoverBackgroundOpacity)
                    : Color.secondary.opacity(AppConstants.UI.actionButtonHoverBackgroundOpacity)
            case .unlocked:
                return isSelected
                    ? Color.white.opacity(AppConstants.UI.selectedRowButtonHoverBackgroundOpacity)
                    : Color.primary.opacity(AppConstants.UI.actionButtonHoverBackgroundOpacity)
            }
        }
        
        switch item.lockStatus {
        case .locked(let level):
            return isSelected
                ? Color.clear
                : levelColor(for: level).opacity(AppConstants.UI.lockButtonActiveOpacity)
        case .inherited:
            return isSelected
                ? Color.clear
                : Color.secondary.opacity(AppConstants.UI.lockButtonInheritedOpacity)
        case .unlocked:
            return Color.clear
        }
    }
    
    private var lockButtonForegroundColor: Color {
        switch item.lockStatus {
        case .locked(let level):
            if isLockHovered {
                return isSelected ? .white : levelColor(for: level)
            }
            return isSelected ? Color.white.opacity(0.95) : levelColor(for: level)
            
        case .inherited:
            if isLockHovered {
                return isSelected ? .white : .primary
            }
            return isSelected ? Color.white.opacity(0.85) : .secondary
            
        case .unlocked:
            if isLockHovered {
                return isSelected ? .white : Color(nsColor: .controlAccentColor)
            }
            return isSelected ? Color.white.opacity(0.85) : .secondary.opacity(AppConstants.UI.unlockedButtonNormalOpacity)
        }
    }
    
    private var cleanButtonHoverBackground: Color {
        guard isCleanHovered && item.canCleanSubItems else {
            return (item.canCleanSubItems && !isSelected)
                ? Color.blue.opacity(AppConstants.UI.actionButtonActiveBackgroundOpacity)
                : Color.clear
        }
        return isSelected
            ? Color.white.opacity(AppConstants.UI.selectedRowButtonHoverBackgroundOpacity)
            : Color.blue.opacity(AppConstants.UI.cleanButtonHoverBackgroundOpacity)
    }
    
    private var cleanButtonForegroundColor: Color {
        guard item.canCleanSubItems else {
            return isSelected
                ? Color.white.opacity(AppConstants.UI.disabledCleanButtonOpacity)
                : Color.secondary.opacity(AppConstants.UI.disabledCleanButtonOpacity)
        }
        if isCleanHovered {
            return isSelected ? .white : Color.blue
        }
        return isSelected ? Color.white.opacity(0.9) : Color.blue.opacity(AppConstants.UI.cleanButtonNormalOpacity)
    }
    
    private var deleteButtonHoverBackground: Color {
        guard isDeleteHovered else { return Color.clear }
        return isSelected
            ? Color.red.opacity(AppConstants.UI.selectedRowButtonHoverBackgroundOpacity)
            : Color.red.opacity(AppConstants.UI.deleteButtonHoverBackgroundOpacity)
    }
    
    private var deleteButtonForegroundColor: Color {
        if isDeleteHovered {
            return isSelected ? .white : .red
        }
        return isSelected ? Color.white.opacity(0.85) : Color.red.opacity(AppConstants.UI.deleteButtonNormalOpacity)
    }
    
    private var lockIconName: String {
        switch item.lockStatus {
        case .locked:
            return AppConstants.LockUI.lockedIconName
        case .inherited:
            return AppConstants.LockUI.lockShieldIconName
        case .unlocked:
            return AppConstants.LockUI.unlockedIconName
        }
    }
    
    private var lockHelpText: String {
        switch item.lockStatus {
        case .locked(let level):
            switch level {
            case .app: return L10n.appLockHelpText
            case .field: return L10n.fieldLockHelpText
            }
        case .inherited:
            return L10n.inheritedLockHelpText
        case .unlocked:
            return L10n.unlockedHelpText
        }
    }
    
    private var cleanHelpText: String {
        if item.isLocked {
            return L10n.lockedAppCannotCleanHelp
        }
        switch item.itemType {
        case .app(_, let granularity, _):
            switch granularity {
            case .app:
                return item.canCleanSubItems ? L10n.cleanAppSubItemsHelp : L10n.noSubItemsToCleanHelp
            case .field:
                return item.canCleanSubItems ? L10n.cleanUnlockedFieldsHelp : L10n.noUnlockedFieldsToCleanHelp
            }
        case .field:
            return L10n.noSubItemsToCleanHelp
        }
    }
    
    @ViewBuilder
    private var itemIcon: some View {
        switch item.itemType {
        case .app(let bundleID, _, _):
            AppRowIconView(bundleID: bundleID, iconSize: AppConstants.UI.appRowIconSize)
        case .field:
            Image(systemName: "character.cursor.ibeam")
                .foregroundColor(.orange)
        }
    }
    
    private func granularityMenu(bundleID: String, current: GranularityLevel) -> some View {
        Menu {
            ForEach(GranularityLevel.allCases) { level in
                Button {
                    onChangeGranularity(bundleID, level)
                } label: {
                    if level == current {
                        Label(level.localizedName, systemImage: "checkmark")
                    } else {
                        Text(level.localizedName)
                    }
                }
            }
        } label: {
            HStack(spacing: AppConstants.UI.menuContentSpacing) {
                Text(current.localizedName)
                    .font(.system(size: AppConstants.UI.menuFontSize))
                    .lineLimit(1)
                Spacer(minLength: AppConstants.UI.menuSpacerMinLength)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: AppConstants.UI.menuChevronFontSize, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, AppConstants.UI.menuHorizontalPadding)
            .frame(height: AppConstants.UI.menuControlHeight)
            .background(
                RoundedRectangle(cornerRadius: AppConstants.UI.menuCornerRadius)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppConstants.UI.menuCornerRadius)
                    .stroke(Color.secondary.opacity(AppConstants.UI.menuBorderOpacity), lineWidth: AppConstants.UI.menuBorderLineWidth)
            )
        }
        .menuStyle(.borderlessButton)
        .frame(width: AppConstants.UI.rowGranularityPickerWidth)
        .help(L10n.granularityHelp)
    }
    
    private func nonInputPolicyMenu(bundleID: String, current: NonInputPolicy) -> some View {
        Menu {
            ForEach(NonInputPolicy.allCases) { policy in
                Button {
                    onChangeNonInputPolicy(bundleID, policy)
                } label: {
                    if policy == current {
                        Label(L10n.nonInputPolicyName(for: policy), systemImage: "checkmark")
                    } else {
                        Text(L10n.nonInputPolicyName(for: policy))
                    }
                }
            }
        } label: {
            HStack(spacing: AppConstants.UI.menuContentSpacing) {
                Image(systemName: nonInputPolicyIcon(for: current))
                    .font(.system(size: AppConstants.UI.menuFontSize))
                    .foregroundColor(nonInputPolicyColor(for: current))
                Text(L10n.nonInputPolicyName(for: current))
                    .font(.system(size: AppConstants.UI.menuFontSize))
                    .lineLimit(1)
                Spacer(minLength: AppConstants.UI.menuSpacerMinLength)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: AppConstants.UI.menuChevronFontSize, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, AppConstants.UI.menuHorizontalPadding)
            .frame(height: AppConstants.UI.menuControlHeight)
            .background(
                RoundedRectangle(cornerRadius: AppConstants.UI.menuCornerRadius)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppConstants.UI.menuCornerRadius)
                    .stroke(Color.secondary.opacity(AppConstants.UI.menuBorderOpacity), lineWidth: AppConstants.UI.menuBorderLineWidth)
            )
        }
        .menuStyle(.borderlessButton)
        .frame(width: AppConstants.UI.rowNonInputPolicyPickerWidth)
        .help(L10n.nonInputPolicyDetail(for: current))
    }
    
    private func nonInputPolicyIcon(for policy: NonInputPolicy) -> String {
        switch policy {
        case .followGlobal: return "globe"
        case .alwaysEnglish: return "character"
        case .exempt: return "shield.lefthalf.filled"
        }
    }
    
    private func nonInputPolicyColor(for policy: NonInputPolicy) -> Color {
        switch policy {
        case .followGlobal: return .secondary
        case .alwaysEnglish: return .blue
        case .exempt: return .orange
        }
    }
    
    private var inputSourceMenu: some View {
        Menu {
            ForEach(availableSources) { source in
                Button {
                    onUpdateSource(source.id)
                } label: {
                    if source.id == item.currentSourceID {
                        Label(source.localizedName, systemImage: "checkmark")
                    } else {
                        Text(source.localizedName)
                    }
                }
            }
            if !availableSources.contains(where: { $0.id == item.currentSourceID }) {
                Button {
                    onUpdateSource(item.currentSourceID)
                } label: {
                    Label(item.currentSourceID, systemImage: "checkmark")
                }
            }
        } label: {
            HStack(spacing: AppConstants.UI.menuContentSpacing) {
                Text(selectedSourceName)
                    .font(.system(size: AppConstants.UI.menuFontSize))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: AppConstants.UI.menuSpacerMinLength)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: AppConstants.UI.menuChevronFontSize, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, AppConstants.UI.menuHorizontalPadding)
            .frame(height: AppConstants.UI.menuControlHeight)
            .background(
                RoundedRectangle(cornerRadius: AppConstants.UI.menuCornerRadius)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppConstants.UI.menuCornerRadius)
                    .stroke(Color.secondary.opacity(AppConstants.UI.menuBorderOpacity), lineWidth: AppConstants.UI.menuBorderLineWidth)
            )
        }
        .menuStyle(.borderlessButton)
        .frame(width: AppConstants.UI.rowInputSourcePickerWidth)
    }
    
    private var selectedSourceName: String {
        availableSources.first(where: { $0.id == item.currentSourceID })?.localizedName ?? item.currentSourceID
    }
}
