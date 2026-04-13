# DevLaunch

プロジェクトフォルダをスキャンし、ワンクリックでエディタ＋AI CLIを起動するmacOSメニューバー常駐アプリ。

## プロジェクト概要

| 項目 | 内容 |
|---|---|
| アプリ名 | DevLaunch |
| プラットフォーム | macOS 13 Ventura 以降 |
| UI フレームワーク | SwiftUI |
| 配布方式 | OSS（MIT）・GitHub Releases（DMG） |
| Sandbox | 無効（外部CLI実行のため） |

## ドキュメント

| ドキュメント | パス |
|---|---|
| 要件定義書 | `.claude/docs/requirements.md` |
| 全体実装計画書 | `.claude/docs/implementation-plan.md` |
| 課題管理 | `.claude/docs/issues.md` |

## 技術スタック

- SwiftUI（UI）
- Process クラス（外部CLI実行）
- UserDefaults / @AppStorage（設定永続化）
- XcodeGen（プロジェクト管理）
