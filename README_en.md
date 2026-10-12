# IME Keeper (Intelligent macOS Input Source Memory Switcher)

<p align="center">
  <b>English</b> | <b><a href="README.md">简体中文</a></b>
</p>

---

**IME Keeper** is a lightweight, elegant native macOS menu bar utility designed to eliminate the frustration of constantly switching keyboard input methods across multi-tasking workflows. It seamlessly tracks user focus transitions, not only remembering input sources across applications and windows, but also providing **precise, millisecond-level input source tracking between distinct text fields within the same window**.

---

## 🌟 Key Features

- **Field-Level Precise Tracking**:
  - Automatically distinguishes between code editors and search bars, chat inputs and sidebar filter fields within the same window. Focus transition instantly restores the last-used input method for that specific field.
- **Seamless Window-Level Inheritance (Inherit-From-Window)**:
  - When opening or clicking into a newly created text field for the first time, it smoothly inherits the window's last-active input source without abrupt shifts.
- **Web Browser Boundary Protection**:
  - Automatically recognizes modern browsers (Safari, Google Chrome, Arc, Edge, etc.) and caps tracking at the window/tab level without penetrating complex web DOM hierarchies, ensuring peak performance and rock-solid stability.
- **Hierarchical Scope Manager**:
  - Visual tree-outline configuration interface: `App -> Window -> Field`.
  - **Per-App Custom Granularity**: Customize the tracking depth for specific applications (e.g. Xcode, Terminal) to `Window Level` or `App Level`.
  - **Inline Editing & Cleanup**: Directly modify assigned input methods or delete stale entries in the outline tree.
- **Bilingual & Instant Language Switching (Multi-Language Support)**:
  - Fully supports **Follow System**, **Simplified Chinese**, and **English**. Toggle between languages anytime from the status bar menu or settings panel with immediate hot-reload (no restart required).
- **Anti-Loop State Machine & Privacy Shield**:
  - Built-in suppression state machine distinguishes programmatic switches from manual user shortcut triggers, preventing cascading event loops.
  - Automatically switches to ASCII input (`ABC`) for password fields (`AXSecureTextField`) and strictly refrains from logging sensitive contexts.
- **Pure Menu Bar Agent**:
  - Operates as an `LSUIElement = true` status bar daemon with no Dock icon clutter, negligible memory footprint, and near-zero CPU usage.

---

## 🏗 System Architecture

```
imekeeper/
├── Package.swift
├── Sources/
│   ├── IMEKeeperCore/              # Core business logic library
│   │   ├── Constants/              # Global constants (Strict zero-magic-number policy)
│   │   ├── Localization/           # Multi-language manager & bilingual dictionaries
│   │   ├── Models/                 # Models (FocusContext, ProfileModels, GranularityLevel)
│   │   ├── InputSource/            # Carbon HIToolbox wrapper & anti-loop state machine
│   │   ├── Storage/                # Hierarchical profile store & granularity manager
│   │   ├── Focus/                  # AXObserver global focus listener & element fingerprinter
│   │   ├── Permission/             # macOS Accessibility permission manager & settings deep-linking
│   │   └── ViewModels/             # Reactive ViewModel for Settings
│   └── imekeeper/                  # Executable application layer
│       ├── AppDelegate.swift       # Global pipeline coordinator
│       ├── main.swift              # Cocoa entry point
│       └── UI/
│           ├── MenuBar/            # Menu bar item & status menu controller
│           └── Settings/           # Hierarchical outline settings window (SwiftUI)
├── Tests/IMEKeeperTests/           # Unit test suite (includes localization tests)
└── scripts/build_app.sh            # Automated release packaging script
```

---

## 🚀 Build & Run

### Prerequisites
- macOS 13.0 (Ventura) or later
- Swift 6.0+ / Xcode 15+

### 1. Run Unit Tests
```bash
swift test
```

### 2. Build & Package into `.app` Bundle
```bash
./scripts/build_app.sh
```
Upon successful build, the application bundle will be created at `dist/IMEKeeper.app`.

### 3. Launch the Application
```bash
open dist/IMEKeeper.app
```

---

## 🔐 Accessibility Permissions

Because this application relies on macOS Accessibility APIs (`AXObserver`) to detect focus changes:
1. On the first launch, macOS will present a permission prompt.
2. If authorization is not granted, click **"Check Accessibility Permission..." -> "Open System Settings"** from the menu bar item.
3. In **System Settings -> Privacy & Security -> Accessibility**, enable **IME Keeper**. The application will become active immediately without needing a restart.
