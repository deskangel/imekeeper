# IME Keeper (macOS 智能输入法记忆切换器)

<p align="center">
  <b><a href="README_en.md">English</a></b> | <b>简体中文</b>
</p>

---

**IME Keeper** 是一款轻量优雅的 macOS 原生菜单栏应用，专注于解决多任务场景下频繁手动切换输入法的痛点。它能够无感感知用户的输入焦点转移，不仅支持跨应用记忆输入法，更支持在**同一应用的不同输入框之间精确记忆、毫秒级切换与状态锁定**。

---

## 🌟 核心特性

- **跨输入框精准记忆 (Field-Level Precise Tracking)**：
  - 在同一个应用中，自动区分代码编辑区与全局搜索栏、聊天消息输入框与侧边栏过滤栏，焦点落入即可瞬时切回该输入框最后一次使用的输入法。
- **全新输入框无感继承 (Inherit-From-App)**：
  - 初次在应用中打开或点击全新输入框时，默认平滑沿用该应用当前基准输入法，绝不产生突兀跳变。
- **应用级 / 输入框级粒度自由控制 (Flexible Granularity Levels)**：
  - **App 级**：整个应用所有输入框统一共享同一输入法（适合纯英文应用或终端）。
  - **Field 级**：应用内每个输入框深度独立追踪记忆。
  - 支持设置全局默认粒度，亦可在管理面板中为特定应用单独覆盖配置。
- **非输入框行为策略与终端豁免 (Non-Input Policy & Terminal Exemption)**：
  - **非输入框切英文 (Always English)**：焦点离开可编辑区域（如点击窗口空白处、按钮、列表等非输入控件）时，自动静默切为英文模式，避免打字干扰和快捷键冲突。
  - **智能豁免保护 (Exempt)**：针对终端应用（Terminal、iTerm2、Ghostty、Alacritty、Kitty、WezTerm、Warp 等）及纯 GPU 自绘编辑器（如 Zed），整视口保持输入上下文，豁免非输入区切英，彻底保护键盘交互流。
  - 支持按应用单独指定策略或跟随全局默认。
- **状态锁定与级联继承保护 (Lock Protection & Cascading Shield)**：
  - **节点锁定**：支持在应用级或单个输入框级一键加锁。锁定后，临时手动切换输入法仅作用于当下，不污染已固化的偏好设置。
  - **级联继承**：应用级锁定后，其下所有输入框自动继承保护状态，且不再无限制收录新输入框，杜绝配置膨胀。
  - **视觉防跳动**：加锁/解锁操作就地更新，不打乱当前列表视觉顺序；再次打开面板时自动置顶锁定项。
- **冗余记录智能清理 (Redundant Sub-Items Cleaner)**：
  - **单应用清理**：一键清理指定应用下不符合当前生效粒度或不再需要的下级输入框记录。
  - **全局一键清理**：底部操作栏一键扫描并清理所有未锁定应用下的冗余输入框条目。处于锁定保护状态的节点享有绝对豁免，绝不被误删。
- **树状大纲设置面板与实时看板 (Interactive Outline & Live Status)**：
  - **实时状态看板 (Live Status Bar)**：实时监测当前前台应用图标、应用名、聚焦输入框、锁定状态及当前生效输入法。
  - **焦点自动定位与平滑滚动**：随着焦点切换，大纲列表自动展开并平滑跟随滚动至当前元素行，辅以醒目的选中高亮指示条。
  - **行内就地重命名**：双击或点击输入框标识即可直接就地重命名，为复杂的控件指纹赋予直观业务名称。
  - **搜索与异步渲染**：支持按应用名、Bundle ID 及输入框名称即时过滤；图标内存预热与异步回填，确保 60fps/120fps 丝滑滚动。
- **双重防回环与防回弹机制 (Anti-Loop & Anti-Oscillation)**：
  - **程序切换防回环**：程序化切换输入法时启动抑制窗口，过滤 macOS HIToolbox 重复派发的系统通知，杜绝级联死循环。
  - **手动切换防回弹 (450ms 冷静保护期)**：识别用户快捷键手动切换，在冷静期内阻断伴随焦点事件的纠偏与非输入区切英，确保用户意图拥有最高裁决权。
- **安全保护与隐私合规 (Security & Privacy Shield)**：
  - 遇到密码输入框（`AXSecureTextField`）自动切为英文模式并静默保护，绝不提取或记录任何密码输入框上下文。
- **中英双语即时切换 (Multi-Language Support)**：
  - 支持**跟随系统**、**简体中文**与**英文**，菜单栏与设置面板随时无缝切换，界面瞬时热重载无需重启。
- **开机自动启动 (Launch at Login)**：
  - 基于 macOS 13+ 原生 `SMAppService.mainApp`，无冗余后台 Helper 守护进程。
- **纯菜单栏形态 (Lightweight Agent)**：
  - `LSUIElement = true` 常驻状态栏，无 Dock 栏图标打扰，极低内存与 CPU 占用。

---

## 🏗 系统架构设计

```
imekeeper/
├── Package.swift
├── Sources/
│   ├── IMEKeeperCore/              # 核心业务逻辑库
│   │   ├── AutoStart/              # SMAppService 原生开机自启服务管理
│   │   ├── Constants/              # 全局常量定义 (严禁魔法数字与硬编码)
│   │   ├── Focus/                  # AXObserver 全局焦点监听、复合指纹提取与浏览器识别
│   │   ├── InputSource/            # Carbon HIToolbox 底层封装、防回环与防回弹状态机
│   │   ├── Localization/           # 本地化调度中心与中英文案字典
│   │   ├── Models/                 # 数据模型 (FocusContext, ProfileModels, GranularityLevel, NonInputPolicy)
│   │   ├── Permission/             # macOS 辅助功能权限检测与系统设置跳转
│   │   ├── Storage/                # 树状记忆引擎、冗余清理与粒度/策略持久化
│   │   ├── Utils/                  # 异步应用图标提取与高效内存缓存
│   │   └── ViewModels/             # 设置面板响应式 ViewModel
│   └── imekeeper/                  # 可执行应用层
│       ├── AppDelegate.swift       # 全局管道调度中枢与事件分发
│       ├── main.swift              # Cocoa 程序入口
│       └── UI/
│           ├── MenuBar/            # 状态栏图标与下拉菜单控制器
│           └── Settings/           # 树状大纲设置面板与子视图 (SwiftUI)
├── Tests/IMEKeeperTests/           # 完备单元测试套件 (覆盖存储、粒度、模型、自启与本地化)
└── scripts/build_app.sh            # 一键 App Bundle 打包脚本
```

---

## 🚀 构建与运行

### 环境要求
- macOS 13.0 (Ventura) 及以上
- Swift 6.0+ / Xcode 15+

### 1. 运行自动化单元测试
```bash
swift test
```

### 2. 编译并打包为 `.app`
```bash
./scripts/build_app.sh
```
打包成功后，应用将输出至 `dist/IMEKeeper.app`。

### 3. 启动应用
```bash
open dist/IMEKeeper.app
```

---

## 🔐 辅助功能权限设置

由于本应用依赖 macOS Accessibility API (`AXObserver`) 监听系统全局焦点转移，首次启动时：
1. 系统将自动弹出无障碍权限申请提示；
2. 若未授权，可在菜单栏图标下拉菜单中点击 **"检查辅助功能权限..." -> "打开系统设置"**；
3. 在系统设置的 **"隐私与安全性" -> "辅助功能"** 中勾选 **IME Keeper** 即可立即生效，无需重启应用。
