# CLAUDE.md

このリポジトリで Claude Code が作業するときの決まり。

## このリポジトリ

TatakiNote は、メニューバーに常駐する macOS アプリ(SwiftUI、`LSUIElement = YES`、Dock に出ない)。
どこかの入力欄に文章を入れる前に、手元のパネルで書いて整えてから入れる。利用者向けの説明は
[README.md](README.md) と [docs/](docs/README.md)。

- `TatakiNote/` — アプリのターゲット。`TatakiNoteTests/` — 単体テスト(Swift Testing)。`TatakiNoteUITests/` — UI テスト(XCUITest)
- `TatakiNote.xcodeproj` — Xcode 27、同期フォルダ方式。配布の最小 OS は macOS 14.0。既定の actor は `MainActor`、Swift 5 モード
- 依存: [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)(SwiftPM)
- `docs/` — 利用者ガイド。`release-notes/` と `VERSION` — リリース
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

### 構成

| 役割 | 置き場所の目安 | 書き方 |
|---|---|---|
| 画面 | `TatakiNote/Views/` | SwiftUI の `View`。表示と、モデルへの操作の呼び出しだけ。`body` に計算・保存を書かない |
| 状態とロジック | `TatakiNote/Models/` | `@Observable final class`。画面の状態(読み込み中・エラー・入力エラー)もここに持つ |
| データ | `TatakiNote/Models/` | 値型(`struct`)。保存するものは `Codable` |
| 保存 | `TatakiNote/Storage/` | 保存先(ディレクトリ・`UserDefaults`)を**引数で受け取る**。テストで一時的な保存先に差し替えるため |
| ショートカット | `TatakiNote/Shortcuts/` | `extension KeyboardShortcuts.Name { static let … }` はここに集める |

フォルダは必要になったときに作る(同期フォルダ方式なので、作れば入る)。

### 書き方

- 既定で MainActor。重い処理はメインスレッドの外へ(`nonisolated` な関数、`Task.detached`)
- 強制アンラップ・`as!`・`try!` を使わない。`try?` で失敗を捨てるのは、失敗しても利用者に影響が無いときだけ
- 失敗は `throws` で返し、画面はモデルのエラー状態を表示する
- 名前は Swift の API Design Guidelines に従う(型は UpperCamelCase、それ以外は lowerCamelCase、
  真偽値は `is`/`has`/`should`)。コメントで補わなくても分かる名前にする
- 利用者に見える文字列は日本語。String Catalog に乗る書き方(`Text("…")`・`String(localized:)`)にする

### テスト

- 単体テストは Swift Testing。`@Test("AC-1: タイトルが空なら保存できない")` のように、確かめる条件を名前に入れる
- `@testable import TatakiNote`
- 保存のテストは、テストごとに一時ディレクトリと設定の保存先を作って渡し、最後に消す。設定の保存先は
  メモリだけの `InMemoryDefaults`(`TemporaryDefaults` が作る)。**既定の `UserDefaults.standard` や
  アプリケーションサポートのディレクトリに触れない**
- 本物の `UserDefaults(suiteName:)` を作るのは `RealUserDefaultsTests` だけ(suite の名前は固定し、前後で消す)。
  `removePersistentDomain` は中身を消すだけで `~/Library/Preferences` にファイルが残り、テストのたびに増える。
  `TestStorageRuleTests` がほかのファイルでの使用を見つける
- UI テストは XCTest の `XCUIApplication`。要素は `accessibilityIdentifier` で探す。UI テストは画面の配線だけを
  確かめ、保存・検証・並び順は単体テストで確かめる
- UI テストは流すのに時間がかかり、その間 Mac を使えないので、次のものは書かない:
  - 既存の UI テストと同じ流れのテスト(新しく作らず、既存のシナリオに手順を足す)
  - 並び順・ラベル・説明文・グループ名・余白・レイアウトだけを確かめるテスト(単体で確かめる)
  - 単体テストと同じ条件を確かめるテスト(検証・キーの規則・保存・計算)
  - アプリに無い識別子が「無いこと」を確かめるテスト(必ず通り、何も確かめない)
  - XCUITest から安定して動かせない操作(送ったキーがアプリに届かないなど)。手で確かめる
- テストを弱める書き方(`.disabled`・`withKnownIssue`・`XCTSkip`・`XCTExpectFailure`)を足さない

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
