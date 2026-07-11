# 課題管理

## オープン

（なし）

## 解決済み

### 既存セッションへの二重キー入力・新規起動でコマンドが入らない（0.1.3〜0.1.5 の一連の対応）

- 経緯: 下記「Claude 起動後に〜」の 0.1.3 対応（ウィンドウ事前検出）後も再発。原因は AX ツリーがコールド状態だと precheck のウィンドウ列挙が空になり "none" と誤判定し、後続のキー送信スクリプトが wake 後にウィンドウを発見して稼働中セッションへ打鍵する時間差レース
- 0.1.4 対応: ウィンドウ検出と独立したプロセスレベルのガード `isAICliRunning` を追加（proc_listallpids + PROC_PIDVNODEPATHINFO cwd + proc_pidpath / KERN_PROCARGS2 argv[0]）。キー送信フローを find-window / prepare-terminal / type-command の3段に分割し、各段直前に再チェック
- 0.1.4 の逆症状: claude のデーモン・IDE 連携・ヘッドレスセッション等の常駐プロセス（プロジェクトを cwd に持つ）を誤検知し、新規起動でコマンドが入らなくなった（2026-07-11 ユーザー報告）
- 0.1.5 対応（確認方法付き）:
  1. 制御端末（PROC_FLAG_CONTROLT = 0x80。0x2 は TRACED なので注意）を持つプロセスのみ対話セッションと判定。実環境で対話2件検出・常駐8件除外を実測確認
  2. 診断ログ `~/Library/Logs/DevLaunch.log` を新設。起動フローの全分岐（precheck 結果・ガードのマッチ内容・どのステップで終了したか）を記録し、以後の報告はログで原因を確定できる
  3. テスト14件全パス（pty 付きフィクスチャは script(1) で作成。プラットフォームバイナリのコピー実行は AMFI に SIGKILL されるため argv[0] 偽装 exec -a を使用）
- 関連する経緯の記録: 数ヶ月安定稼働していた4月版が壊れた起点は 2026-06-21〜23 の OSS 公開作業（ad-hoc ビルドの上書きインストールによる TCC 無効化。下記別項）。二重入力のコード経路自体は4月版から存在

### Claude 起動後に「claude」コマンドが再入力される（既存セッションへの二重キー入力）

- 発見日: 2026-07-10（ユーザー報告「Claudeが立ち上がった後、また /claude のようなコマンドが自動的に入る」）
- 症状: すでにエディタで開いている（AI CLI 稼働中の）プロジェクトを DevLaunch から再度起動すると、稼働中の Claude セッションの入力欄に `claude` + Enter が打ち込まれる
- 根本原因: VS Code / Cursor は同一フォルダを `--new-window` 指定でも既存ウィンドウに集約する。旧実装は「ウィンドウが存在する＝新規ウィンドウが開いた」とみなしてキーストローク送信フェーズへ進むため、既存ウィンドウ（ターミナルで AI CLI 稼働中）にコマンドが二重入力された
- 対処（2026-07-11 実施）:
  1. `IntegratedTerminalLauncher` に既存ウィンドウの事前検出を追加。パス確認済み（AXDocument 一致）のウィンドウが既にあれば前面化のみ行い、キーストローク送信をスキップ（osascript 実測で "reused" 経路を確認）
  2. ウィンドウタイトル照合を `contains` の部分一致から境界付き照合（完全一致 / "ファイル名 — フォルダ名" 形式）＋ AXDocument によるパス検証に変更し、類似名プロジェクト（例: "dev" と "dev-launch"）や同名フォルダの別プロジェクトへの誤送信を防止（AppleScript の照合ロジック7ケース＋実機で reused / foreign 経路をテストし全件期待どおりを確認）
  3. タイトル一致だがパス未確認（"ambiguous"、AXDocument 欠落時）のウィンドウは、Codex レビュー指摘を受けて「再利用成功」扱いをやめ、`open` で正しいプロジェクトパスを開いた上でキー送信のみスキップする動作に変更（エディタ自身がパスベースで正しいウィンドウに集約するため誤爆せず、稼働中セッションへの二重入力も起きない）
- 関連修正（同時実施）:
  - `ProjectLauncher` のコマンド解決（`/bin/zsh -l` による PATH 取得）がメインスレッドをブロックしていた問題 → detached タスク内へ移動し、PATH は初回のみ取得してキャッシュ
  - `Project.id` が再スキャンごとに UUID 再生成されていた問題 → path ベースの ID に変更
  - README の削除済み Zed 対応の記述を除去、既存ウィンドウ再利用の挙動を追記

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
