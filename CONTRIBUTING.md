# 開発に参加する

## 始め方

1. clone して、git の hook を有効にする

   ```bash
   git clone https://github.com/tk-niway/tataki-note.git
   cd tataki-note
   scripts/setup.sh
   ```

2. Xcode 27 で `TatakiNote.xcodeproj` を開いてビルドする(依存のパッケージは Xcode が取ってくる)
3. 単体テストは Xcode の Test(⌘U、`TatakiNoteTests`)か `./scripts/release.sh test`

アプリは、他のアプリへの文字の入力にアクセシビリティの許可を使う。開発中のビルドで試すときも、
「システム設定」→「プライバシーとセキュリティ」→「アクセシビリティ」で許可する。

## 変更を入れる流れ

1. `main` からブランチを切って作業する
2. `main` への Pull Request を作る。次のチェックが通る必要がある
   - **Unit tests** — 単体テスト(`.github/workflows/test.yml`)
   - **Public check** — 公開の決まり(下の「コメント」「コミット」)。変わったファイル・すべてのコミットのメッセージ・
     PR のタイトルを見る(`.github/workflows/public-check.yml`)
3. メンテナー(@tk-niway)の承認を受けてマージする。マージはマージコミットで行う(squash しない)

利用者から見える動きを変えたら、同じ PR で [利用者ガイド](docs/README.md) も直す
(書き方は [`update-docs` スキル](.claude/skills/update-docs/SKILL.md))。漏れた分はリリースの前にまとめて直す。

## コードの書き方

### 構成

| 役割 | 置き場所の目安 | 書き方 |
|---|---|---|
| 画面 | `TatakiNote/Views/` | SwiftUI の `View`。表示と、モデルへの操作の呼び出しだけ。`body` に計算・保存を書かない |
| 状態とロジック | `TatakiNote/Models/` | `@Observable final class`。画面の状態(読み込み中・エラー・入力エラー)もここに持つ |
| データ | `TatakiNote/Models/` | 値型(`struct`)。保存するものは `Codable` |
| 保存 | `TatakiNote/Storage/` | 保存先(ディレクトリ・`UserDefaults`)を**引数で受け取る**。テストで一時的な保存先に差し替えるため |
| ショートカット | `TatakiNote/Shortcuts/` | `extension KeyboardShortcuts.Name { static let … }` はここに集める |

フォルダは必要になったときに作る(同期フォルダ方式なので、作れば入る)。`*.xcodeproj` は手で編集しない。
ターゲット・パッケージ・Info.plist・entitlements・ビルド設定の変更は Xcode で行う。

### 書き方

- 既定で MainActor。重い処理はメインスレッドの外へ(`nonisolated` な関数、`Task.detached`)
- 強制アンラップ・`as!`・`try!` を使わない。`try?` で失敗を捨てるのは、失敗しても利用者に影響が無いときだけ
- 失敗は `throws` で返し、画面はモデルのエラー状態を表示する
- 名前は Swift の API Design Guidelines に従う(型は UpperCamelCase、それ以外は lowerCamelCase、
  真偽値は `is`/`has`/`should`)。コメントで補わなくても分かる名前にする
- 利用者に見える文字列は日本語。String Catalog に乗る書き方(`Text("…")`・`String(localized:)`)にする

### コメント

このリポジトリは公開されている。コメントに書いてよいのは次だけ:

- `// MARK: <見出し>`
- 外から呼ばれる型・メソッド・プロパティ(private・fileprivate でない宣言)の直前の、短い `///` の説明。
  **何をするか**だけを書き、なぜそうしたか・経緯・今後の予定・内部の事情は書かない
- UI テストの受け入れ条件の目印 `// AC-<番号>`(説明を付けない)

それ以外の `//`・`/* */`、Xcode が新しいファイルに入れる先頭の見出しコメント、TODO・FIXME は書かない。
コードを読めば分かることは `///` にも書かない。`scripts/check-public.sh` が確かめる(commit のときの hook と CI)。

### テスト

- 単体テストは Swift Testing。`@Test("AC-1: タイトルが空なら保存できない")` のように、確かめる条件を名前に入れる
- `@testable import TatakiNote`
- 保存のテストは、テストごとに一時ディレクトリと `UserDefaults(suiteName: UUID().uuidString)` を作って
  渡し、最後に消す。**既定の `UserDefaults.standard` やアプリケーションサポートのディレクトリに触れない**
- UI テストは XCTest の `XCUIApplication`。要素は `accessibilityIdentifier` で探す。UI テストは画面の配線だけを
  確かめ、保存・検証・並び順は単体テストで確かめる
- テストを弱める書き方(`.disabled`・`withKnownIssue`・`XCTSkip`・`XCTExpectFailure`)を足さない

## コミット

- 件名は変更の内容を日本語で短く
- 件名にも本文にも、手元の作業場所のパス(ホームディレクトリの下の場所など)を書かない

## リリース

[RELEASING.md](RELEASING.md)。
