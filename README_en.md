# IME Keeper (Intelligent macOS Input Source Memory Switcher)

<p align="center">
  <b>English</b> | <b><a href="README.md">简体中文</a></b>
</p>

---

**IME Keeper** is a lightweight, elegant native macOS menu bar utility designed to eliminate the frustration of constantly switching keyboard input methods across multi-tasking workflows. It seamlessly tracks user focus transitions, not only remembering input sources across applications, but also providing **precise input source tracking, millisecond-level switching, and state locking between distinct text fields within the same application**.

---

## 🌟 Key Features

- **Field-Level Precise Tracking**:
  - Automatically distinguishes between code editors and search bars, chat inputs and sidebar filter fields within the same application. Focus transition instantly restores the last-used input method for that specific field.
- **Seamless Inheritance (Inherit-From-App)**:
  - When opening or clicking into a newly created text field for the first time, it smoothly inherits the application's base input source without abrupt shifts.
- **Flexible Granularity Control (App Level vs. Field Level)**:
  - **App Level**: The entire application shares a unified input source across all text fields (ideal for terminal emulators or English-only tools).
  - **Field Level**: Each text field within the application is tracked and remembered independently.
  - Set a global default granularity or customize tracking depth per application in the management panel.
- **Non-Input Focus Policy & Terminal Exemption**:
  - **Always English**: Automatically and silently switches to ASCII English mode whenever focus transitions outside editable fields (e.g., clicking on window background, buttons, list views, or sliders), eliminating keystroke conflicts with app shortcuts.
  - **Smart Exemption (Exempt)**: Exempts terminal applications (Terminal, iTerm2, Ghostty, Alacritty, Kitty, WezTerm, Warp, etc.) and GPU-rendered canvas editors (such as Zed) from switching to English, preserving fluent command-line and canvas interactions.
  - Per-app customization with fallback to global default.
- **Lock Protection & Cascading Shield**:
  - **Node Locking**: Lock input sources directly at the Application level or on individual Text Fields. Once locked, temporary manual switches will not overwrite saved preferences.
  - **Cascading Inheritance**: Locking an application automatically shields all its sub-fields and prevents boundless growth of newly discovered fields.
  - **Visual Jitter Prevention**: Locking/unlocking updates items in-place without reshuffling rows; locked items are pinned to the top upon reopening the preferences panel.
- **Intelligent Sub-Item Cleanup (Redundancy Removal)**:
  - **Per-App Cleanup**: Clean sub-field records that do not match the active granularity or are no longer needed.
  - **Global One-Click Cleanup**: Scan and prune all redundant unlocked field entries across all applications with a single click. Locked items are strictly protected and never pruned.
- **Interactive Outline Settings Panel & Live Status**:
  - **Live Status Bar**: Real-time display of the frontmost application icon, app name, focused text field, lock/inherited badge, and active input source.
  - **Auto-Scroll & Focus Highlighting**: Automatically expands ancestor nodes and smoothly scrolls to the currently focused row with a left-accent indicator.
  - **Inline Field Renaming**: Double-click or click on any field identifier to rename it in place with human-readable semantic labels.
  - **Instant Search & Asynchronous Icons**: Real-time filtering by app name, bundle ID, or field identifier, backed by in-memory icon pre-warming for stutter-free 60fps/120fps scrolling.
- **Dual Anti-Loop & Anti-Oscillation State Machine**:
  - **Programmatic Anti-Loop**: Suppresses redundant system broadcasts from macOS HIToolbox during programmatic switching, eliminating cascading infinite loops.
  - **Manual Switch Grace Period (450ms)**: Distinguishes user shortcut triggers and enforces a 450ms quiet window to suppress race conditions and unwanted auto-switching, ensuring user intent retains absolute priority.
- **Security & Privacy Shield**:
  - Automatically switches to ASCII input (`ABC`) for password fields (`AXSecureTextField`) and strictly refrains from logging sensitive credentials.
- **Multi-Language Support**:
  - Fully supports **Follow System**, **Simplified Chinese**, and **English**. Toggle instantly from the menu bar or settings panel with immediate hot-reload (no restart required).
- **Launch at Login**:
  - Built on native macOS 13+ `SMAppService.mainApp`, providing one-click startup configuration without redundant background daemon helpers.
- **Pure Menu Bar Agent**:
  - Operates as an `LSUIElement = true` status bar daemon with no Dock icon clutter, negligible memory footprint, and near-zero CPU usage.

---

## 🏗 System Architecture

```
imekeeper/
├── Package.swift
├── Sources/
│   ├── IMEKeeperCore/              # Core business logic library
│   │   ├── AutoStart/              # Native SMAppService auto-start service management
│   │   ├── Constants/              # Global constants (Strict zero-magic-number policy)
│   │   ├── Focus/                  # AXObserver global focus listener, element fingerprinter & browser detector
│   │   ├── InputSource/            # Carbon HIToolbox wrapper, anti-loop & anti-oscillation state machine
│   │   ├── Localization/           # Multi-language manager & bilingual dictionaries
│   │   ├── Models/                 # Data models (FocusContext, ProfileModels, GranularityLevel, NonInputPolicy)
│   │   ├── Permission/             # macOS Accessibility permission manager & deep-linking
│   │   ├── Storage/                # Hierarchical profile store, redundancy cleaner & policy manager
│   │   ├── Utils/                  # Asynchronous app icon extraction & memory caching
│   │   └── ViewModels/             # Reactive ViewModel for Settings
│   └── imekeeper/                  # Executable application layer
│       ├── AppDelegate.swift       # Global pipeline coordinator & event dispatcher
│       ├── main.swift              # Cocoa entry point
│       └── UI/
│           ├── MenuBar/            # Status bar item & status menu controller
│           └── Settings/           # Hierarchical outline settings window & subviews (SwiftUI)
├── Tests/IMEKeeperTests/           # Comprehensive unit test suite (Storage, Granularity, Models, AutoStart, L10n)
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
