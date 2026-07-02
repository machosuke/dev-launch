# 課題管理

## オープン

（なし）

## 解決済み

### キー入力送信の失敗（VS Code にコマンドが入らない / System Events エラーバナー）

- 発見日: 2026-07-02（症状は 2026-06-22 のスクリーンショットで確認）
- 症状: エディタ起動時に「Failed to send keystrokes to editor: ... System Events でエラーが起きました」バナーが頻発し、VS Code の統合ターミナルに AI CLI コマンドが自動入力されない
- 根本原因: OSS リリース作業（2026-06-21〜23）で /Applications に ad-hoc 署名ビルド（0.1.0 build 2、DerivedData の Release ビルド）を入れてしまい、署名の指紋がビルドごとに変わるため、旧ビルドに紐づいた TCC アクセシビリティ許可が無効化された。コード変更（4a6455d はドキュメントのみ）は無関係
- 副次的問題: `IntegratedTerminalLauncher` のエラー判定が英語文言（"assistive access"）の文字列一致のみで、日本語環境では権限エラーが `accessibilityDenied` に分類されず生エラーが表示されていた
- 対処（2026-07-02 実施・確認方法付き）:
  1. Developer ID 署名 + 公証済みの 0.1.1（`build/export/DevLaunch.app`、`spctl -a` で `Notarized Developer ID` を確認）を /Applications に再インストール。旧 ad-hoc 版はゴミ箱へ
  2. `tccutil reset Accessibility/AppleEvents com.machosuke.DevLaunch` で古い権限エントリをリセットし、アクセシビリティを再付与（システム設定で確認）
  3. コード改善: `AXIsProcessTrustedWithOptions` による事前チェック（未付与ならシステムダイアログ表示）＋ロケール非依存のエラーコード判定（-25211 / 1002 / -1743）＋ Automation 拒否用の `automationDenied` ケース追加。`xcodebuild build` / `test` 成功を確認
- 再発防止: 配布・自分用インストールとも必ず Developer ID 署名の export（`build/export/`）を使う。DerivedData のビルドを /Applications にコピーしない
