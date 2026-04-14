# Phase 1: プロジェクト基盤構築 — 詳細実装計画

## Context

DevLaunch は macOS メニューバー常駐アプリ。Phase 0（PoC）は Go 確定済み（AppleScript approach、成功率100%）。本フェーズでは XcodeGen プロジェクト、ディレクトリ構成、メニューバーアプリの骨格を構築する。

## 設計判断

### MenuBarExtra vs NSStatusItem

**NSStatusItem 直接実装を採用する。**

理由: 完了条件「左クリック→ポップオーバー、右クリック→コンテキストメニュー」を SwiftUI の `MenuBarExtra` だけでは実現できない。`MenuBarExtra` は右クリック用コンテキストメニューの公式 API を提供していない。`NSStatusItem` + `NSPopover` の古典的実装が最も確実で、macOS アップデートにも堅牢。

### MenuBarIcon

SF Symbols `terminal.fill` をコードで直接使用。Assets.xcassets に MenuBarIcon.imageset は作成しない（不要）。

## 実装ステップ

### Step 1: ディレクトリ構造 + Assets.xcassets 作成

```
DevLaunch/
├── DevLaunchApp.swift
├── Info.plist
├── DevLaunch.entitlements
└── Assets.xcassets/
    ├── Contents.json
    └── AppIcon.appiconset/
        ├── Contents.json
        └── AppIcon.png          ← Assets/AppIcon.png からコピー（要サイズ確認）
```

- `sips -g pixelWidth -g pixelHeight Assets/AppIcon.png` でサイズ確認
- 1024x1024 でなければ `sips --resampleHeightWidth 1024 1024` でリサイズ
- AppIcon.appiconset/Contents.json: 単一 1024x1024 PNG（Xcode 自動生成方式）

### Step 2: Info.plist 作成

`DevLaunch/Info.plist`

重要設定:
- `LSUIElement = true`（Dock 非表示）
- `NSAppleEventsUsageDescription`（Phase 2 で AppleScript 使用時の説明文）
- `NSAccessibilityUsageDescription`（アクセシビリティ権限の説明文）
- `NSHighResolutionCapable = true`

### Step 3: Entitlements 作成

`DevLaunch/DevLaunch.entitlements`

- `com.apple.security.app-sandbox = false`（Sandbox OFF）
- `com.apple.security.automation.apple-events = true`（AppleScript 送信用）

### Step 4: DevLaunchApp.swift 作成

`DevLaunch/DevLaunchApp.swift`

構造:
```swift
@main
struct DevLaunchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsPlaceholderView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    // NSStatusItem + NSPopover で左クリック→ポップオーバー
    // 右クリック→コンテキストメニュー（Settings... / Quit DevLaunch）
}

struct ContentView: View {
    // 空のポップオーバー（"No projects yet" + Settings 誘導）
    // 底部にボタンバー不要（右クリックメニューで代替）
}

struct SettingsPlaceholderView: View {
    // Phase 3 で本実装。仮の "Settings coming soon" 表示
}
```

ポップオーバー仕様:
- 幅: 300pt
- `NSPopover.behavior = .transient`（クリック外で自動閉じ）
- 左クリック: togglePopover
- 右クリック: NSMenu 表示（Settings... / Quit DevLaunch）

注意事項:
- `NSApp.activate(ignoringOtherApps: true)` を Settings 表示時に呼ぶ（LSUIElement アプリではウィンドウが前面に来ない問題対策）
- `popover.contentViewController?.view.window?.makeKey()` を show 直後に呼ぶ（最前面表示対策）
- Settings の Selector は `showSettingsWindow:`（macOS 13+ 正式）

### Step 5: project.yml 作成

```yaml
name: DevLaunch
options:
  bundleIdPrefix: com.machosuke
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "16.0"

targets:
  DevLaunch:
    type: application
    platform: macOS
    sources:
      - DevLaunch
    info:
      path: DevLaunch/Info.plist
    entitlements:
      path: DevLaunch/DevLaunch.entitlements
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.machosuke.DevLaunch
        INFOPLIST_FILE: DevLaunch/Info.plist
        GENERATE_INFOPLIST_FILE: NO
        CODE_SIGN_ENTITLEMENTS: DevLaunch/DevLaunch.entitlements
        ENABLE_APP_SANDBOX: NO
        ENABLE_HARDENED_RUNTIME: YES
        SWIFT_VERSION: "5.9"
        SWIFT_STRICT_CONCURRENCY: minimal
        CODE_SIGN_STYLE: Automatic
```

注意: `GENERATE_INFOPLIST_FILE: NO` を明示しないと XcodeGen が Info.plist を上書きする。

### Step 6: xcodegen generate → ビルド → 実行確認

```bash
# XcodeGen 実行
xcodegen generate

# ビルド
xcodebuild -project DevLaunch.xcodeproj -scheme DevLaunch -configuration Debug build ONLY_ACTIVE_ARCH=YES

# 起動（DerivedData から .app を探して実行）
```

## 完了条件の検証方法

| 完了条件 | 検証方法 |
|---|---|
| xcodegen generate が成功する | exit code 0, DevLaunch.xcodeproj 生成 |
| ビルド成功 + メニューバーにアイコン表示 | xcodebuild 成功, `terminal.fill` アイコン確認 |
| ポップオーバーの表示/非表示 | 左クリックで開閉、外クリックで閉じる |
| Dock にアイコン非表示 | LSUIElement=true の動作確認 |
| 右クリックでコンテキストメニュー | Settings... / Quit DevLaunch が表示される |

## 対象ファイル一覧

| ファイルパス | 区分 |
|---|---|
| `project.yml` | 新規 |
| `DevLaunch/DevLaunchApp.swift` | 新規 |
| `DevLaunch/Info.plist` | 新規 |
| `DevLaunch/DevLaunch.entitlements` | 新規 |
| `DevLaunch/Assets.xcassets/Contents.json` | 新規 |
| `DevLaunch/Assets.xcassets/AppIcon.appiconset/Contents.json` | 新規 |
| `DevLaunch/Assets.xcassets/AppIcon.appiconset/AppIcon.png` | Assets/ からコピー |

## 既知の落とし穴

1. **Swift 6 Sendable 違反**: `SWIFT_STRICT_CONCURRENCY: minimal` で回避
2. **LSUIElement + Settings**: `NSApp.activate(ignoringOtherApps: true)` 必須
3. **NSPopover が背面に隠れる**: `makeKey()` で対処
4. **XcodeGen Info.plist 衝突**: `GENERATE_INFOPLIST_FILE: NO` 必須
