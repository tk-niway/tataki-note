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

アプリのソース(`TatakiNote/`)は機能ごとのフォルダに分け、1つの機能の画面・状態・保存は同じフォルダに置く。

| フォルダ | 機能 |
|---|---|
| `TatakiNote/App/` | 起動・終了の確認・Dock・メニューバーのアイコンとメニュー・アプリケーションフォルダへの移動・ログイン時に開く |
| `TatakiNote/Panel/` | 入力パネルの窓・状態・画面(タイトルバー・帯・トースト・保存の動き・揺れ) |
| `TatakiNote/Panel/Editor/` | パネルの入力欄(行の編集・入力欄のキー) |
| `TatakiNote/Panel/Frame/` | パネルの大きさ・位置・出す画面・開閉の動き |
| `TatakiNote/Drafts/` | 下書きと履歴・サイドバー・その保存・履歴の設定 |
| `TatakiNote/Export/` | ファイルへの書き出しと共有 |
| `TatakiNote/Keys/` | ホットキー・パネルのキー・キーの記録と表示・キーの設定のページ。`extension KeyboardShortcuts.Name { static let … }` はここに集める |
| `TatakiNote/AutoShow/` | 自動表示(フォーカスの見張り・対象のアプリ・その設定) |
| `TatakiNote/Insertion/` | 挿入(クリップボードの退避と戻し・貼り付け・送信のキー・Web の中身を見えるようにする) |
| `TatakiNote/InsertionTarget/` | 挿入先(前面のアプリの見張り・挿入先の表示と枠線) |
| `TatakiNote/Permission/` | アクセシビリティの許可と案内 |
| `TatakiNote/Tutorial/` | チュートリアルと練習用のチャット |
| `TatakiNote/Settings/` | 設定の窓と、複数の機能にまたがるページ(一般・パネル・情報) |
| `TatakiNote/Updates/` | アップデートの確認と印 |
| `TatakiNote/Storage/` | 設定の保存(`AppSettings`・`AppState`・設定の定義と保存先) |
| `TatakiNote/Shared/` | 複数の機能で使う部品 |

直下は `MyApp.swift`・`AppDelegate.swift`(と `Info.plist`・`Assets.xcassets`)だけ。1つの機能だけの設定のページはその機能のフォルダに、
複数の機能にまたがるページは `Settings/` に置く。新しい機能はフォルダを作ってこの表に足す(同期フォルダ方式なので、作れば入る。
表とフォルダは単体テスト `ProjectLayoutTests` が突き合わせる)。

| 役割 | 書き方 |
|---|---|
| 画面 | SwiftUI の `View`。表示と、モデルへの操作の呼び出しだけ。`body` に計算・保存を書かない |
| 状態とロジック | `@Observable final class`。画面の状態(読み込み中・エラー・入力エラー)もここに持つ |
| データ | 値型(`struct`)。保存するものは `Codable` |
| 保存 | 保存先(ディレクトリ・`UserDefaults`)を**引数で受け取る**。テストで一時的な保存先に差し替えるため |

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
- 単体テストのファイルは `TatakiNoteTests/` の直下に置き、名前は確かめる型の名前で始める(`<型の名前>Tests.swift`、観点で分けるなら `<型の名前><観点>Tests.swift`)。スイートの名前はファイル名と同じにする
- テスト用の偽物と補助のうち、複数のファイルから使うものは `TatakiNoteTests/TestDoubles/` に置く。同じ役割の偽物を新しく作らず、そこにあるものを使う
- **単体テストは、Mac で共有する保存先に書かない。** 単体テストは並行に何本も流れ(複数のブランチで同時に)、
  共有の保存先を取り合うと不安定になり、残ったものは消えずにたまる
  - 設定はメモリだけの `InMemoryDefaults`(`TemporaryDefaults` が作る)を渡す。本物の `UserDefaults`
    (`UserDefaults(suiteName:)`・`.standard`)は使わない。`removePersistentDomain` は中身を消すだけで、
    `~/Library/Preferences` にファイルが残る
  - ファイルに書くことを確かめるときは、テストごとに一時ディレクトリ(`FileManager.default.temporaryDirectory`
    の下に UUID)を作って渡し、最後に消す。アプリケーションサポートなど、本物の保存場所に触れない
  - 共有のクリップボード(`NSPasteboard.general`)に書かない。名前付きのクリップボードを作って渡し、`releaseGlobally()` で消す
  - 本物の保存先でしか確かめられないことは、単体テストにしない(アプリを動かして確かめる)
  - `TestStorageRuleTests` が、テストのファイルでの本物の `UserDefaults`・共有のクリップボードへの書き込みを見つける
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
