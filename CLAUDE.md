# CLAUDE.md

このリポジトリで Claude Code が作業するときの決まり。人向けの同じ内容は [CONTRIBUTING.md](CONTRIBUTING.md)。

## このリポジトリ

TatakiNote は、メニューバーに常駐する macOS アプリ(SwiftUI、`LSUIElement = YES`、Dock に出ない)。
どこかの入力欄に文章を入れる前に、手元のパネルで書いて整えてから入れる。利用者向けの説明は
[README.md](README.md) と [docs/](docs/README.md)。

- `TatakiNote/` — アプリのターゲット。`TatakiNoteTests/` — 単体テスト(Swift Testing)。`TatakiNoteUITests/` — UI テスト(XCUITest)
- `TatakiNote.xcodeproj` — Xcode 27、同期フォルダ方式。配布の最小 OS は macOS 14.0。既定の actor は `MainActor`、Swift 5 モード
- 依存: [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)(SwiftPM)
- `docs/` — 利用者ガイド。`release-notes/` と `VERSION` — リリース([RELEASING.md](RELEASING.md))
- `scripts/` — リリースのスクリプト、公開の決まりの検査(`check-public.sh`)と hook

## Xcode のプロジェクト

- **`*.xcodeproj` を手で編集しない**(`project.pbxproj` は壊れやすい)。新しい Swift のファイルは、ターゲットの
  フォルダに置くだけで入る(`TatakiNote/`・`TatakiNoteTests/`・`TatakiNoteUITests/`)
- ターゲット・パッケージの追加、Info.plist・entitlements・ビルド設定の変更は、人が Xcode で行う

## ビルドとテスト

```bash
xcodebuild build -project TatakiNote.xcodeproj -scheme TatakiNote -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO -quiet
./scripts/release.sh test
```

`release.sh test` は CI と同じ単体テスト。UI テストは画面を操作するので、人がターミナルか Xcode で流す。

## コーディング規約

[CONTRIBUTING.md の「コードの書き方」](CONTRIBUTING.md#コードの書き方)に従う。

## コメント

**このリポジトリは公開されている。** コメントに書いてよいのは次だけ:

- `// MARK: <見出し>`
- 外から呼ばれる型・メソッド・プロパティ(private・fileprivate でない宣言)の直前の、短い `///` の説明。
  **何をするか**だけを書く。なぜそうしたか・経緯・今後の予定・内部の事情は書かない
- UI テストの受け入れ条件の目印 `// AC-<番号>`(説明を付けない)

それ以外の `//`・`/* */`、ファイルの先頭の見出しコメント、TODO・FIXME は書かない。コードを読めば分かることは
`///` にも書かない。

Claude が書いたファイルは hook(`.claude/settings.json` → `scripts/claude-hook.sh`)が `scripts/check-public.sh` で
確かめ、合わなければ差し戻す。手で確かめるときは `scripts/check-public.sh --changed`。

## コミット

- 件名は変更の内容を日本語で短く。番号(プラン・タスク)を入れてもよい
- 件名にも本文にも、手元の作業場所のパス(ホームディレクトリの下の場所など)を書かない
- commit のときに `.githooks/` が同じ検査をする(`scripts/setup.sh` で有効になる)

## 利用者ガイド(docs/)

利用者から見える動き(画面・メニュー・ショートカット・設定)が変わったら、`docs/` を直す。書き方は
[`update-docs` スキル](.claude/skills/update-docs/SKILL.md)。形は単体テスト `UserDocsTests` が確かめる。
