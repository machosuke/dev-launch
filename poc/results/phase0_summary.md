# Phase 0: 統合ターミナル起動 PoC — 結果サマリー

## テスト環境

- **日時**: 2026-04-13
- **macOS**: Darwin 25.3.0
- **VS Code**: Visual Studio Code
- **テスト対象プロジェクト**: `/Users/machosuke/Desktop/claude_code/bunshin-ai`（dev-launch とは別プロジェクト）

## 各アプローチの結果

| アプローチ | 結果 | 成功率 | 備考 |
|-----------|------|--------|------|
| Approach 1: VS Code URI scheme | **NOT WORKING** | 0% | `vscode://command/` URI を macOS から発行しても VS Code がターミナル操作を処理しない |
| Approach 2: AppleScript キーストローク | **GO** | 100% (10/10) | `open -n --new-window` + System Events キーストローク。安定動作 |
| Approach 3: Process + shell | 未テスト | — | Approach 2 が 100% のため省略。同じ AppleScript ロジックを Process 経由で実行する変種 |
| Fallback: External Terminal | **動作確認済** | — | Terminal.app `do script` で `cd <path> && claude` を実行。確実に動作 |

## Approach 2 安定性テスト詳細

- **テスト回数**: 10回
- **成功回数**: 10回
- **成功率**: 100%
- **実行間隔**: 30秒
- **ログ**: `poc/results/stability_20260413_211626.log`

## Go/No-Go 判定

### **VERDICT: GO**

Approach 2（AppleScript キーストローク）を採用する。

## 採用アプローチの詳細

### 手順

1. `open -n -a "Visual Studio Code" --args --new-window <projectPath>` で VS Code 新ウィンドウを開く
2. 5秒待機（VS Code ウィンドウのロード完了待ち）
3. System Events で対象ウィンドウを `AXRaise` で最前面に
4. 英数キー（key code 102）で IME を英語に切替
5. `Ctrl+Shift+`` で新規ターミナル作成（トグルではなく新規作成）
6. キーストロークでコマンド入力 + Return

### 必要な権限

- **アクセシビリティ権限**: 必須（System Events のキーストローク送信に必要）
  - System Settings > Privacy & Security > Accessibility にアプリを追加

### Cursor 互換

- 未テスト（Cursor がインストールされている場合、プロセス名 `"Cursor"` に変更して同様に動作する見込み）
- VS Code fork のため、キーボードショートカット互換性は高い

## フォールバック戦略

統合ターミナル起動が失敗した場合（アクセシビリティ権限なし等）:

1. Terminal.app で `cd <path> && <command>` を実行
2. アクセシビリティ権限不要
3. 動作確認済み
