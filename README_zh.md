# IME Keeper (macOS 智能输入法记忆切换器)

<p align="center">
  <b><a href="README_en.md">English</a></b> | <b>简体中文</b>
</p>

---

**IME Keeper** 是一款轻量优雅的 macOS 原生菜单栏应用，专注于解决多任务场景下频繁手动切换输入法的痛点。它能够无感感知用户的输入焦点转移，不仅支持跨应用、跨窗口记忆输入法，更支持在**同一窗口的不同输入框之间精确记忆与毫秒级切换**。

---

## 🌟 核心特性

- **跨输入框精准记忆 (Field-Level Tracking)**：
  - 在同一个窗口中，自动区分代码编辑区与全局搜索栏、聊天消息输入框与侧边栏过滤栏，焦点落入即可瞬时切回该输入框最后一次使用的输入法。
- **全新输入框无感继承 (Inherit-From-Window)**：
  - 初次在一个窗口中打开或点击全新输入框时，默认平滑沿用该窗口当前最后使用的输入法，绝不产生突兀跳变。
- **Web 浏览器边界保护 (Browser Boundary)**：
  - 自动识别 Safari、Google Chrome、Arc、Edge 等浏览器应用，统一限制在窗口/标签页级，完全不深入 Web 内部 DOM，兼顾极致性能与稳定性。
- **多层级配置与记忆管理面板 (Hierarchical Scope Manager)**：
  - 提供可视化的树状大纲管理界面：`App (应用) -> Window (窗口) -> Field (输入框)`。
  - **各应用粒度自由配置**：支持为特定应用（如 Xcode、终端）单独指定生效粒度为 `Window 级` 或 `App 级`。
  - **行内即时编辑与维护**：可直接在树状列表下拉框中修改绑定的输入法，或删除单个脏记录。
- **中英双语与即时切换 (Multi-Language Support)**：
  - 支持**跟随系统**、**简体中文**与**英文**，可在状态栏菜单或设置面板中随时一键切换，界面瞬时热重载无需重启应用。
- **防回环与安全模式 (Anti-Loop & Privacy Protection)**：
  - 内置防回环状态机，自动识别“程序化自动切换”与“用户快捷键手动切换”，杜绝级联事件；
  - 遇到密码输入框（`AXSecureTextField`）自动切为英文静默保护，绝不记录任何敏感上下文。
- **开机自动启动 (Launch at Login)**：
  - 基于 macOS 13+ 原生 `SMAppService.mainApp`，支持一键配置开机自启。可在状态栏菜单快速勾选，或在设置面板底部操作栏直观开关，无冗余后台 Helper 进程。
- **纯菜单栏形态 (Lightweight Agent)**：
  - `LSUIElement = true` 常驻状态栏，无 Dock 栏图标打扰，内存与 CPU 占用极低。

---

## 🏗 系统架构设计

```
imekeeper/
├── Package.swift
├── Sources/
│   ├── IMEKeeperCore/              # 核心业务逻辑库
│   │   ├── AutoStart/              # SMAppService 原生开机自启服务管理
│   │   ├── Constants/              # 全局常量定义 (严格无魔法数字)
│   │   ├── Localization/           # 本地化调度中心与中英文案字典
│   │   ├── Models/                 # 数据模型 (FocusContext, ProfileModels, GranularityLevel)
│   │   ├── InputSource/            # Carbon HIToolbox 底层封装与防回环
│   │   ├── Storage/                # 树状记忆引擎与粒度管理器
│   │   ├── Focus/                  # AXObserver 全局焦点监听与复合指纹提取
│   │   ├── Permission/             # TCC 辅助功能授权检测与跳转
│   │   └── ViewModels/             # 设置面板响应式 ViewModel
│   └── imekeeper/                  # 可执行应用层
│       ├── AppDelegate.swift       # 全局管道调度中枢
│       ├── main.swift              # Cocoa 程序入口
│       └── UI/
│           ├── MenuBar/            # 状态栏图标与下拉菜单控制器
│           └── Settings/           # 树状大纲设置面板 (SwiftUI)
├── Tests/IMEKeeperTests/           # 完备单元测试套件 (包含本地化与自启测试)
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

由于本应用依赖 macOS Accessibility API 监听焦点转移，首次启动时：
1. 系统将自动弹出无障碍权限申请；
2. 若未授权，可在菜单栏图标中点击 **"检查辅助功能权限..." -> "打开系统设置"**；
3. 在系统设置的 **"隐私与安全性" -> "辅助功能"** 中勾选 **IME Keeper** 即可立即生效，无需重启应用。
