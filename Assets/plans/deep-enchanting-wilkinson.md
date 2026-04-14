# Phase 0: 統合ターミナル起動 PoC 実装計画

## Context

DevLaunch のコアバリューは「ワンクリックでエディタ＋AI CLIを起動」すること。その実現可能性を Phase 0 で検証する。統合ターミナル起動が技術的に不可能・不安定なら、設計を根本的に変更する必要があるため、Go/No-Go Gate として最初に実施する。

## ディレクトリ構成

```
dev-launch/
└── poc/
    ├── README.md                          # 実行手順
    ├── approach1_uri_scheme.swift         # VS Code URI scheme テスト
    ├── approach2_applescript.swift        # AppleScript キーストロークテスト
    ├── approach3_process_shell.swift      # Process + shell ハイブリッドテスト
    ├── fallback_external_terminal.swift   # Terminal.app フォールバックテスト
    ├── stability_test.sh                  # 安定性テスト（10回連続実行）
    └── results/
        └── .gitkeep
```

## 実装タスク（実行順）

### Task 1: poc/ ディレクトリ作成
- `poc/` と `poc/results/` を作成
- `poc/results/.gitkeep` を配置

### Task 2: fallback_external_terminal.swift（外部ターミナルフォールバック）
**最初に実装・検証する**（最も確実で、他のテストの前提確認になる）

Terminal.app の AppleScript `do script` で `cd <path> && claude` を実行:
```applescript
tell application "Terminal"
    activate
    do script "cd " & quoted form of "<path>" & " && claude"
end tell
```
- アクセシビリティ権限不要
- `claude` バイナリの存在確認にもなる

### Task 3: approach1_uri_scheme.swift（VS Code URI scheme）
**優先度最高のアプローチ**

手順:
1. `open -a "Visual Studio Code" <path>` で VS Code を開く
2. 3秒待機（VS Code の起動完了待ち）
3. `vscode://command/workbench.action.terminal.new` URI を発行（新規ターミナル作成）
4. 0.5秒待機
5. `vscode://command/workbench.action.terminal.sendSequence?%7B%22text%22%3A%22claude%5Cn%22%7D` URI を発行

実装ポイント:
- `NSWorkspace.shared.open(url)` で URI を発行（`import AppKit` 必要）
- PATH 不要、アクセシビリティ権限不要
- `open()` は fire-and-forget なので、成功判定は「URI発行がエラーなく完了した」のみ
- 実際の動作は目視確認が必要

### Task 4: approach2_applescript.swift（AppleScript キーストローク）

手順:
1. `code <path>` で VS Code を開く（`/usr/local/bin/code`）
2. 3秒待機
3. `osascript` で以下を実行:
```applescript
tell application "Visual Studio Code" to activate
delay 1
tell application "System Events"
    tell process "Code"
        keystroke "`" using control down
        delay 0.5
        keystroke "claude"
        keystroke return
    end tell
end tell
```

実装ポイント:
- **アクセシビリティ権限が必須**（System Events のキーストローク送信）
- 事前に System Preferences > Privacy & Security > Accessibility に Terminal.app を追加
- プロセス名は `"Code"`（VS Code）/ `"Cursor"`（Cursor）

### Task 5: approach3_process_shell.swift（Process + shell ハイブリッド）

Approach 2 と同じロジックだが、全てを単一のシェルスクリプトとして `Process` で実行:
```bash
code <path> &
sleep 3
osascript -e '...'
```
Phase 2 の `ProjectLauncher.swift` に最も近い実装形式。

### Task 6: stability_test.sh（安定性テスト）
各アプローチを10回連続実行し、成功率を計測するシェルスクリプト:
- 各実行間に30秒の待機（VS Code の安定化待ち）
- 結果を `poc/results/stability_<timestamp>.log` に記録
- 最終行に VERDICT（GO / CONDITIONAL GO / NO-GO）を出力

### Task 7: 手動テスト実行
1. fallback → approach1 → approach2 → approach3 の順に手動で1回ずつ実行
2. 動作するアプローチに対して `stability_test.sh` を実行（10回）
3. Cursor がインストールされていれば URI scheme を `cursor://` に変更してテスト

### Task 8: 結果まとめ・Go/No-Go 判定
`poc/results/phase0_summary.md` に以下を記録:
- テスト日時、macOS バージョン、VS Code バージョン
- 各アプローチの成功率
- Go/No-Go 判定
- 採用アプローチ
- 必要な権限

## Go/No-Go 判定基準

| 判定 | 条件 |
|------|------|
| **Go** | いずれかのアプローチで成功率 90%以上 |
| **条件付き Go** | 成功率 70-89%、リトライロジックで対応可能 |
| **No-Go** | 全アプローチで 70% 未満 → 外部ターミナルをデフォルトに |

## 注意事項

- Swift スクリプトから子プロセスを起動する際は絶対パスを使用（`/usr/local/bin/code`, `/usr/bin/osascript`, `/usr/bin/open`）
- macOS アプリに組み込む際は PATH が最小限になるため、PoC 段階から絶対パス前提で実装
- `NSWorkspace.shared.open(url)` の戻り値は URI の dispatch 成功のみを示し、VS Code 側の処理成功は保証しない
- 非 US キーボードでは backtick のキーコードが異なる可能性あり（`key code 50` で対応可能）

## 検証方法

1. 各 Swift スクリプトを `swift poc/<script>.swift <project_path>` で実行
2. VS Code / Terminal.app の画面を目視で確認
3. `stability_test.sh` の出力ログで成功率を確認
4. `poc/results/phase0_summary.md` で最終判定を確認

## 変更対象ファイル（すべて新規作成）

| ファイル | 説明 |
|---------|------|
| `poc/README.md` | 実行手順ドキュメント |
| `poc/approach1_uri_scheme.swift` | URI scheme テスト |
| `poc/approach2_applescript.swift` | AppleScript テスト |
| `poc/approach3_process_shell.swift` | Process + shell テスト |
| `poc/fallback_external_terminal.swift` | 外部ターミナルテスト |
| `poc/stability_test.sh` | 安定性テストスクリプト |
| `poc/results/.gitkeep` | results ディレクトリ保持 |
