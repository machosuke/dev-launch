# Phase 0: 統合ターミナル起動 PoC

VS Code の統合ターミナルで AI CLI を起動する技術的実現可能性を検証する。

## 前提条件

- macOS 13+
- VS Code がインストール済み（`/usr/local/bin/code`）
- `claude` CLI がインストール済み（`~/.local/bin/claude`）
- Approach 2/3 のみ: アクセシビリティ権限（System Settings > Privacy & Security > Accessibility に Terminal.app を追加）

## 各アプローチの実行

```bash
# フォールバック（最初にこれで前提確認）
swift poc/fallback_external_terminal.swift /path/to/project

# Approach 1: VS Code URI scheme（優先）
swift poc/approach1_uri_scheme.swift /path/to/project

# Approach 2: AppleScript キーストローク
swift poc/approach2_applescript.swift /path/to/project

# Approach 3: Process + shell ハイブリッド
swift poc/approach3_process_shell.swift /path/to/project
```

## 安定性テスト

```bash
chmod +x poc/stability_test.sh
poc/stability_test.sh approach1_uri_scheme.swift 10
```

結果は `poc/results/` に保存される。

## Go/No-Go 判定基準

| 判定 | 条件 |
|------|------|
| Go | いずれかのアプローチで成功率 90%以上 |
| 条件付き Go | 成功率 70-89%、リトライで対応可能 |
| No-Go | 全アプローチ 70% 未満 → 外部ターミナルをデフォルトに |
