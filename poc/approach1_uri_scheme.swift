#!/usr/bin/env swift

// MARK: - Approach 1: VS Code URI Scheme
// ステータス: ❌ NOT WORKING
//
// vscode://command/workbench.action.terminal.new および
// vscode://command/workbench.action.terminal.sendSequence は
// macOS の open コマンドおよび NSWorkspace.shared.open() で
// VS Code に送信してもターミナルが開かない。
//
// URI 自体は dispatch されるが、VS Code が command/ URI を
// 処理していない（セキュリティ上の制限の可能性）。
//
// 結論: このアプローチは使用不可。Approach 2（AppleScript）を採用。

print("SKIPPED: approach1_uri_scheme - VS Code URI scheme does not respond to command/ URIs on this environment")
print("Use approach2_applescript.swift instead")
