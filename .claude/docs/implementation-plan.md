# DevLaunch 全体実装計画書

## 1. 技術設計判断

| 判断項目 | 決定 | 根拠 |
|---------|------|------|
| データ永続化方式 | UserDefaults（@AppStorage） | 設定値のみ保存。データモデル不要 |
| プロジェクトスキャン | FileManager + FSEvents | 初回フルスキャン + FSEvents で差分監視 |
| 外部プロセス起動 | Process クラス（Foundation） | シェルコマンド実行の標準手段 |
| エディタ統合ターミナル起動 | URI scheme → AppleScript → フォールバック（Phase 0 で検証） | 技術リスクあり。PoC で確定。要件定義書の優先順位に準拠 |
| グローバルショートカット | CGEvent tap / NSEvent.addGlobalMonitorForEvents | アクセシビリティ権限が必要な場合あり |
| メニューバーアプリ | MenuBarExtra（SwiftUI native, macOS 13+） | SwiftUI 標準。NSStatusItem より宣言的 |
| 設定画面 | Settings シーン（SwiftUI） | macOS 標準の設定ウィンドウ |
| ログイン時自動起動 | ServiceManagement.SMAppService | macOS 13+ の標準 API。Launch Agent 不要 |
| ビルドシステム | XcodeGen | project.yml でプロジェクト管理。.xcodeproj を .gitignore |
| 公証（Notarization） | xcodebuild archive + notarytool | Developer ID 配布に必須 |
| テスト戦略 | ユニットテスト（スキャン・設定）+ 手動 UI 確認 | UI が小規模のため UITest は費用対効果が低い |

## 2. フェーズ一覧と依存関係図

```
Phase 0: 統合ターミナル起動 PoC ← ★ Go/No-Go Gate
    ↓
Phase 1: プロジェクト基盤構築
    ↓
Phase 2: コア機能実装（スキャン + 起動）
    ↓
Phase 3: 設定画面 + ユーザー設定
    ↓
Phase 4: UI ブラッシュアップ + UX 検証
    ↓
Phase 5: 配布準備（署名・公証・DMG）
```

全フェーズが直列依存。アプリの規模が小さく、並列化の余地は限定的。

## 3. 各フェーズの詳細

---

### Phase 0: 統合ターミナル起動 PoC ← ★ Go/No-Go Gate

#### 目的

エディタ（VS Code）の統合ターミナルで AI CLI を起動する技術的実現可能性を検証する。これが DevLaunch のコアバリューであり、不可能なら設計を根本的に変更する必要がある。

#### 依存

なし（最初のフェーズ）

#### 検証アプローチ（優先度順）

**アプローチ 1: VS Code URI scheme**（優先 — 要件定義書準拠）
```
1. `code /path/to/project` でフォルダを開く
2. `open "vscode://command/workbench.action.terminal.sendSequence?%7B%22text%22%3A%22claude%5Cn%22%7D"` で統合ターミナルにコマンド送信
```
- 利点: アクセシビリティ権限不要、API ベースで安定
- リスク: VS Code の URI handler の挙動がバージョンにより異なる可能性。フォルダを開く前に URI が実行されると失敗

**アプローチ 2: AppleScript キーストローク送信**
```
1. `code /path/to/project` でフォルダを開く
2. sleep で VS Code の起動完了を待機
3. osascript で VS Code にフォーカス
4. osascript で Ctrl+` キーストロークを送信（統合ターミナルを開く）
5. osascript でコマンド文字列をキーストローク送信（例: "claude\n"）
```
- 利点: 実装がシンプル
- リスク: アクセシビリティ権限必須、タイミング依存、VS Code 以外のエディタでは動作保証なし

**アプローチ 3: シェルスクリプト経由（Process で実行）**
```
1. `code /path/to/project` を実行
2. 一定時間待機（2-3秒）
3. AppleScript で VS Code の統合ターミナルにコマンドを送信
```
- 利点: Process クラスで完結
- リスク: 待機時間の調整が難しい

#### タスク一覧

1. 最小限の Swift コマンドラインツールを作成（Xcode プロジェクト不要、Swift スクリプトで十分）
2. アプローチ 1 を検証: osascript でのキーストローク送信が VS Code で動作するか確認
3. アプローチ 2 を検証: VS Code URI scheme でターミナルコマンド送信が動作するか確認
4. 安定性テスト: 10回連続実行して成功率を計測
5. Cursor でも同様に動作するか確認（VS Code fork のため高確率で互換）
6. 外部ターミナル起動のフォールバック実装を確認（Terminal.app で `cd [path] && claude` を実行）

#### Go/No-Go 判定基準

| 判定 | 条件 |
|------|------|
| **Go** | いずれかのアプローチで成功率 90% 以上（10回中9回成功） |
| **条件付き Go** | 成功率 70-89%。リトライロジック追加で対応可能と判断 |
| **No-Go** | 全アプローチで成功率 70% 未満。外部ターミナル起動をデフォルトに変更 |

#### 完了条件

```
[ ] 少なくとも1つのアプローチで統合ターミナル起動が動作する
[ ] 成功率が計測され、Go/No-Go 判定が完了している
[ ] 採用するアプローチが決定し、必要な権限（アクセシビリティ等）が明確になっている
[ ] フォールバック（外部ターミナル起動）が動作確認済み
```

---

### Phase 1: プロジェクト基盤構築

#### 目的

XcodeGen プロジェクト、ディレクトリ構成、メニューバーアプリの骨格を構築する。

#### 依存

Phase 0（Go 判定後）

#### 実装ファイル一覧

| ファイルパス | 区分 | 説明 |
|---|---|---|
| project.yml | 新規 | XcodeGen プロジェクト定義 |
| DevLaunch/DevLaunchApp.swift | 新規 | アプリエントリポイント。MenuBarExtra 定義 |
| DevLaunch/Info.plist | 新規 | LSUIElement=true（Dock非表示） |
| DevLaunch/DevLaunch.entitlements | 新規 | Hardened Runtime 設定 |
| DevLaunch/Assets.xcassets/ | 新規 | アプリアイコン、メニューバーアイコン |
| .gitignore | 既存 | staging からコピー |
| .claudeignore | 既存 | staging からコピー |
| CLAUDE.md | 既存 | staging からコピー |

#### タスク一覧

1. project.yml を作成（macOS 13+, SwiftUI, Sandbox OFF）
2. DevLaunchApp.swift を作成（MenuBarExtra + 空のポップオーバー）
3. Info.plist に LSUIElement=true を設定
4. Entitlements に Hardened Runtime を設定
5. Assets.xcassets にプレースホルダーアイコンを配置
6. メニューバーアイコンを SF Symbols（`terminal.fill` or `arrow.up.right.square`）で仮設定
7. xcodegen generate でプロジェクト生成 → ビルド → 実行確認
8. Git 初期コミット

#### 完了条件

```
[ ] xcodegen generate が成功する
[ ] ビルドが成功し、メニューバーにアイコンが表示される
[ ] ポップオーバーをクリックで表示/非表示できる
[ ] Dock にアイコンが表示されない（LSUIElement 動作確認）
[ ] 右クリックでコンテキストメニュー（Settings... / Quit DevLaunch）が表示される
```

---

### Phase 2: コア機能実装（スキャン + 起動）

#### 目的

プロジェクトスキャン、一覧表示、ワンクリック起動の3つのコア機能を実装する。

#### 依存

Phase 1

#### 実装ファイル一覧

| ファイルパス | 区分 | 説明 |
|---|---|---|
| DevLaunch/Services/ProjectScanner.swift | 新規 | フォルダスキャン + FSEvents 監視 |
| DevLaunch/Services/ProjectLauncher.swift | 新規 | エディタ + AI CLI 起動ロジック |
| DevLaunch/Services/IntegratedTerminalLauncher.swift | 新規 | 統合ターミナル起動（Phase 0 で確定した方式） |
| DevLaunch/Services/ExternalTerminalLauncher.swift | 新規 | 外部ターミナル起動（フォールバック） |
| DevLaunch/Models/Project.swift | 新規 | プロジェクトデータ構造体 |
| DevLaunch/ViewModels/ProjectListViewModel.swift | 新規 | プロジェクト一覧の状態管理 |
| DevLaunch/Views/ProjectListView.swift | 新規 | ポップオーバー内のプロジェクト一覧 |
| DevLaunch/Views/ProjectRowView.swift | 新規 | プロジェクト行（名前 + クリック起動） |
| DevLaunch/Views/EmptyStateView.swift | 新規 | スキャンフォルダ未設定時の空状態 |
| DevLaunch/Views/ErrorBannerView.swift | 新規 | エラーメッセージ表示（インライン） |
| Tests/ProjectScannerTests.swift | 新規 | スキャンロジックのユニットテスト |

#### タスク一覧

1. Project 構造体を定義（name, path, lastLaunchedAt）
2. ProjectScanner を実装
   - 指定フォルダ直下の .git 存在チェック
   - 隠しフォルダ除外
   - FSEvents 監視でリアルタイム更新
   - スキャン結果をキャッシュ
3. ProjectListViewModel を実装
   - スキャン結果の保持
   - ソート切り替え（最近使った順 / アルファベット順）
   - 最終起動日時の記録（UserDefaults）
4. ProjectLauncher を実装
   - エディタコマンド実行（Process クラス）
   - AI CLI 起動（統合ターミナル or 外部ターミナル、設定に応じて分岐）
   - コマンド未検出時のエラーハンドリング
5. IntegratedTerminalLauncher を実装（Phase 0 の PoC 成果を組み込む）
6. ExternalTerminalLauncher を実装（Terminal.app で cd + コマンド実行）
7. ProjectListView / ProjectRowView を実装
8. EmptyStateView を実装（「Select a scan folder」+ フォルダ選択ボタン）
9. ErrorBannerView を実装（エラーメッセージのインライン表示）
10. ProjectScanner のユニットテストを作成
11. ビルド実行で動作確認（スキャン → 一覧表示 → クリック起動）

#### 完了条件

```
[ ] フォルダ選択後、.git があるサブディレクトリが一覧に表示される
[ ] プロジェクトクリックでエディタが開き、AI CLI が起動する
[ ] 統合ターミナル起動（Phase 0 で Go の場合）が動作する
[ ] 外部ターミナル起動が動作する
[ ] コマンド未検出時にエラーメッセージが表示される
[ ] スキャンフォルダ未設定時に空状態画面が表示される
[ ] FSEvents でフォルダ追加/削除が自動反映される
[ ] ProjectScanner のユニットテストがパスする
[ ] ソート切り替え（最近使った順 / アルファベット順）が動作する
```

---

### Phase 3: 設定画面 + ユーザー設定

#### 目的

全設定項目の UI と永続化を実装する。グローバルショートカット、ログイン時自動起動も含む。

#### 依存

Phase 2

#### 実装ファイル一覧

| ファイルパス | 区分 | 説明 |
|---|---|---|
| DevLaunch/Views/Settings/SettingsView.swift | 新規 | 設定画面のルート |
| DevLaunch/Views/Settings/GeneralSettingsView.swift | 新規 | スキャンフォルダ、ソート順、自動起動 |
| DevLaunch/Views/Settings/EditorSettingsView.swift | 新規 | エディタ選択、AI CLI 選択、オプション |
| DevLaunch/Views/Settings/ShortcutSettingsView.swift | 新規 | グローバルショートカット設定 |
| DevLaunch/Services/GlobalShortcutManager.swift | 新規 | グローバルショートカットの登録・監視 |
| DevLaunch/Services/LoginItemManager.swift | 新規 | SMAppService でのログイン時自動起動 |
| DevLaunch/Models/AppSettings.swift | 新規 | 設定値の型定義 + UserDefaults キー |
| DevLaunch/Models/EditorPreset.swift | 新規 | エディタプリセット（VS Code, Cursor, Zed） |
| DevLaunch/Models/AICliPreset.swift | 新規 | AI CLI プリセット（Claude Code, Codex） |

#### タスク一覧

1. AppSettings を定義（全設定項目の UserDefaults キーとデフォルト値）
2. EditorPreset / AICliPreset 列挙型を定義（プリセット名 + コマンド）
3. GeneralSettingsView を実装
   - スキャンフォルダ選択（NSOpenPanel）
   - ソート順選択（Picker）
   - ログイン時自動起動トグル
4. EditorSettingsView を実装
   - エディタプリセット選択（VS Code / Cursor / Zed / Custom）
   - カスタムコマンド入力フィールド
   - AI CLI プリセット選択（Claude Code / Codex / Custom）
   - AI CLI オプション入力フィールド
   - 起動先選択（統合ターミナル / 外部ターミナル）
5. ShortcutSettingsView を実装
   - キーコンビネーション記録 UI
   - 現在の設定表示 + クリア機能
6. GlobalShortcutManager を実装（CGEvent tap）
7. LoginItemManager を実装（SMAppService.mainApp）
8. SettingsView で Tab 構成（General / Editor / Shortcut）
9. Settings シーンを DevLaunchApp に追加
10. ビルド実行で全設定項目の動作確認

#### 完了条件

```
[ ] Settings... メニューから設定画面が開く
[ ] 全設定項目が変更・保存でき、アプリ再起動後も保持される
[ ] エディタ・AI CLI のプリセット選択が動作する
[ ] カスタムコマンド入力が動作する
[ ] グローバルショートカットの設定・動作が確認できる
[ ] ログイン時自動起動の ON/OFF が動作する
[ ] スキャンフォルダの変更がプロジェクト一覧に即反映される
```

---

### Phase 4: UI ブラッシュアップ + UX 検証

#### 目的

デザインガイドラインに準拠した最終的な UI 品質を確保し、ユーザーフローを端から端まで検証する。

#### 依存

Phase 3

#### 実装ファイル一覧

| ファイルパス | 区分 | 説明 |
|---|---|---|
| DevLaunch/Views/ProjectListView.swift | 改修 | キーボードナビゲーション追加 |
| DevLaunch/DevLaunchApp.swift | 改修 | 初回起動フロー統合 |

#### タスク一覧

1. ポップオーバーのサイズ調整（幅 300pt, 最大高 400pt）
2. キーボードナビゲーション実装（↑/↓/Enter/Esc）
3. ダークモード / ライトモード両方で表示確認
4. 初回起動フロー確認（フォルダ選択ダイアログ → 一覧表示）
5. エラー状態の UX 確認
   - エディタ未インストール時
   - AI CLI 未インストール時
   - スキャンフォルダ削除時
6. VoiceOver 基本対応（リスト項目のアクセシビリティラベル設定）
7. メニューバーアイコンのデザイン最終調整
8. プロジェクト数 50+ での表示パフォーマンス確認

#### ユーザーフロー検証チェックリスト

```
[ ] 初回起動: アプリ起動 → フォルダ選択 → プロジェクト一覧表示
[ ] 通常起動: メニューバークリック → 一覧表示 → プロジェクト起動
[ ] ショートカット: グローバルショートカット → 一覧表示 → Enter で起動
[ ] 設定変更: エディタ変更 → 起動で反映される
[ ] エラー回復: コマンド未検出エラー → 設定画面で修正 → 正常起動
```

#### 完了条件

```
[ ] デザインガイドライン（.claude/docs/design-guidelines.md）のレイアウト仕様を満たしている（ポップオーバー幅 300pt, 最大高 400pt, リスト行高 36pt）
[ ] キーボードナビゲーションが動作する
[ ] ダーク/ライト両モードで表示が正常
[ ] VoiceOver で全要素が操作可能
[ ] 上記ユーザーフロー検証チェックリストが全てパス
[ ] パフォーマンス目標を満たしている（ポップオーバー 0.3秒以内, スキャン 1秒以内）
```

---

### Phase 5: 配布準備（署名・公証・DMG）

#### 目的

Developer ID 署名、Apple 公証、DMG 作成、GitHub Releases への配布準備を完了する。

#### 依存

Phase 4

#### 実装ファイル一覧

| ファイルパス | 区分 | 説明 |
|---|---|---|
| scripts/build-and-notarize.sh | 新規 | ビルド・署名・公証・DMG 作成の自動化スクリプト |
| scripts/create-dmg.sh | 新規 | DMG パッケージ作成 |
| README.md | 新規 | プロジェクト概要、スクリーンショット、インストール方法 |
| LICENSE | 新規 | MIT ライセンス |
| .github/workflows/release.yml | 新規 | GitHub Actions でのリリース自動化（オプション） |

#### タスク一覧

1. Developer ID 証明書の確認・準備
2. ビルドスクリプト作成（xcodebuild archive → export）
3. 公証スクリプト作成（notarytool submit → staple）
4. DMG 作成スクリプト作成（create-dmg or hdiutil）
5. DMG のカスタム背景・アイコン配置（Applications フォルダへのドラッグ誘導）
6. ローカルでの公証テスト（DMG を別 Mac or 別ユーザーで開けるか確認）
7. README.md 作成（スクリーンショット GIF、インストール手順、ビルド手順）
8. LICENSE ファイル作成（MIT）
9. GitHub Releases へのアップロードテスト
10. リポジトリをパブリックに変更

#### 完了条件

```
[ ] Developer ID 署名済みの .app がビルドできる
[ ] Apple 公証が通過する
[ ] 公証済み DMG が別環境で正常にインストール・起動できる
[ ] README.md にスクリーンショット・インストール方法・ビルド方法が記載されている
[ ] GitHub Releases に DMG がアップロードされている
[ ] リポジトリがパブリックに設定されている
```

---

## 4. リスクと対策

### 技術的リスク

| リスク | 影響度 | 発生確率 | 対策 |
|---|---|---|---|
| 統合ターミナル起動が不安定 | 高 | 中 | Phase 0 で PoC。No-Go なら外部ターミナルをデフォルトに |
| AppleScript キーストロークのタイミング依存 | 中 | 中 | リトライロジック + 適切な待機時間の調整 |
| FSEvents の通知漏れ | 低 | 低 | ポップオーバー表示時のリフレッシュボタンを検討 |
| macOS バージョンによる API 差異 | 低 | 低 | macOS 13+ のみサポート。MenuBarExtra は 13+ で安定 |

### 配布リスク

| リスク | 影響度 | 発生確率 | 対策 |
|---|---|---|---|
| 公証（Notarization）失敗 | 中 | 低 | Hardened Runtime 有効、禁止 API 不使用の確認 |
| Gatekeeper による実行ブロック | 中 | 低 | Stapling で公証チケットを DMG に埋め込み |

### 外部依存リスク

| リスク | 影響度 | 発生確率 | 対策 |
|---|---|---|---|
| VS Code の URI scheme 仕様変更 | 中 | 低 | アプローチ複数用意、外部ターミナルフォールバック |
| Raycast が同等機能を出す | 低 | 中 | OSS・スタンドアロンとしての独自価値を維持 |

## 5. ディレクトリ構成

```
DevLaunch/
├── DevLaunchApp.swift              # エントリポイント（MenuBarExtra）
├── Info.plist
├── DevLaunch.entitlements
├── Assets.xcassets/
│   ├── AppIcon.appiconset/
│   └── MenuBarIcon.imageset/
├── Models/
│   ├── Project.swift               # プロジェクトデータ構造体
│   ├── AppSettings.swift           # 設定値の型定義
│   ├── EditorPreset.swift          # エディタプリセット
│   └── AICliPreset.swift           # AI CLI プリセット
├── ViewModels/
│   └── ProjectListViewModel.swift  # プロジェクト一覧の状態管理
├── Views/
│   ├── ProjectListView.swift       # ポップオーバー内の一覧
│   ├── ProjectRowView.swift        # プロジェクト行
│   ├── EmptyStateView.swift        # 空状態
│   ├── ErrorBannerView.swift       # エラー表示
│   └── Settings/
│       ├── SettingsView.swift      # 設定画面ルート
│       ├── GeneralSettingsView.swift
│       ├── EditorSettingsView.swift
│       └── ShortcutSettingsView.swift
├── Services/
│   ├── ProjectScanner.swift        # フォルダスキャン + FSEvents
│   ├── ProjectLauncher.swift       # 起動ロジック（統合/外部の分岐）
│   ├── IntegratedTerminalLauncher.swift  # 統合ターミナル起動
│   ├── ExternalTerminalLauncher.swift    # 外部ターミナル起動
│   ├── GlobalShortcutManager.swift      # グローバルショートカット
│   └── LoginItemManager.swift           # ログイン時自動起動
├── Utilities/
│   └── Extensions/
└── Tests/
    └── ProjectScannerTests.swift
```

## 6. macOS 固有の設計考慮事項

### 6.1 メニューバー設計

DevLaunch はメニューバー常駐アプリ（LSUIElement=true）のため、標準的なメニューバー（File, Edit, etc.）は表示されない。代わりに以下の操作手段を提供する。

| 操作 | 手段 |
|------|------|
| ポップオーバー表示 | メニューバーアイコン左クリック / グローバルショートカット |
| 設定画面表示 | 右クリック → Settings... / ポップオーバー内歯車アイコン |
| アプリ終了 | 右クリック → Quit DevLaunch |

### 6.2 ウィンドウ管理

- ポップオーバー: macOS 標準の NSPopover 動作（クリック外で自動閉じ）
- 設定画面: 単一ウィンドウ。複数の設定ウィンドウは開かない
- フルスクリーン: 非対応（不要）

### 6.3 キーボードショートカット

| ショートカット | アクション | スコープ |
|---|---|---|
| ユーザー設定 | ポップオーバー表示/非表示 | グローバル |
| ↑/↓ | プロジェクト選択 | ポップオーバー内 |
| Enter/Return | 選択プロジェクト起動 | ポップオーバー内 |
| Esc | ポップオーバーを閉じる | ポップオーバー内 |
| ⌘, | 設定画面を開く | アプリ内（LSUIElement でも動作させるため要実装） |

### 6.4 公証・署名

- Hardened Runtime 有効
- Developer ID Application 証明書で署名
- notarytool で Apple に送信 → staple で DMG にチケット埋め込み
- 配布スクリプト（scripts/build-and-notarize.sh）で自動化

### 6.5 権限要件

| 権限 | 条件 | 用途 |
|------|------|------|
| アクセシビリティ | Phase 0 の結果次第 | AppleScript キーストローク送信（統合ターミナル起動） |
| フルディスクアクセス | 不要 | — |
| ネットワーク | 不要 | — |
