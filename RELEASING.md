# リリース(アプリの配布)

TatakiNote は、このリポジトリの GitHub Releases で配布する。CI(GitHub Actions)では AI を使わない。
リリースノートと版はマージの前に用意し、人が2回見る(PR の差分と、GitHub の下書きのリリース)。

## 流れ

1. `main` からブランチ(例: `release/v1.1.0`)を切り、次を用意する
   - `VERSION` — 次の版(下の「版の決め方」)
   - `release-notes/v<版>.md` — リリースノート(下の「リリースノートの書き方」)
   - 利用者ガイド `docs/` — 前のリリースからの変更で、書き漏れや事実と違う箇所があれば直す
     (書き方は [`update-docs` スキル](.claude/skills/update-docs/SKILL.md))
2. `main` への PR を作ってマージする
3. `.github/workflows/release.yml` が動く。`VERSION` の版が公開済みでなければ、単体テスト → Release ビルド →
   証明書で署名・検証 → zip → 下書きのリリース(本文 = リリースノート、添付 = `TatakiNote-<版>.zip` と `.sha256`)。
   `VERSION`・`release-notes/` を変えていないマージでは動かない
4. GitHub の Releases で下書きを確認・修正して Publish。タグ `v<版>` はこのときに付く

失敗したら、直して `main` に入れ直すか、Actions の画面から `Release` を手動で再実行する(workflow_dispatch)。
同じ版の下書きがあれば本文と添付を差し替え、公開済みなら何もしない。

## 版の決め方(semver)

- 利用者から見て、今までの使い方・設定・挙動が変わり、何かをし直す必要がある変更 → major
- 新しい機能・設定の追加、目に見える挙動の改善 → minor
- 不具合の修正、文言の修正、内部だけの変更 → patch

## リリースノートの書き方

- 日本語。読むのはアプリの利用者で、開発者ではない
- 実装の話(クラス名・ファイル名・リファクタリング・テスト・CI・ビルド設定など)は書かない。
  利用者に関係する変更が無いときは「内部の改善のみ」と1行で書く
- 見出しは必要なものだけ使う: `## 新機能` / `## 改善` / `## 不具合の修正` / `## 注意`
  (`## 注意` は、更新後にし直すことがあるとき・挙動が変わるときだけ)
- 各項目は1〜2文の箇条書き。何ができるようになったか・何が直ったかを、利用者の言葉で
- 最初の行に版やアプリ名の見出しは書かない(リリースのタイトルが別にある)

## ローカルで配布物を作る

`./scripts/release.sh build` で、CI と同じ手順で `dist/` に `TatakiNote.app` と zip を作る。GitHub には上げない。
署名にはログインキーチェーンの証明書 "TatakiNote Code Signing" を使う。

## 署名

- 自己署名の証明書 "TatakiNote Code Signing" で、毎回同じ証明書で署名する。macOS はアクセシビリティの許可を
  バンドル ID と証明書に結び付けるので、証明書が変わると利用者全員の許可が外れる
- `release.sh` は Xcode に署名させず(`CODE_SIGNING_ALLOWED=NO`)、ビルド後に `codesign` で署名する。
  CI の一時キーチェーンでは自己署名の証明書が信頼済みにならず、Xcode の署名 ID 探索で落ちるため
- 検証は `codesign --verify --strict -R='identifier "jp.co.woube.TatakiNote" and certificate leaf = H"<SHA-1>"'`。
  SHA-1 は `scripts/release.conf` の `CERT_SHA1`。検証には証明書の信頼設定が要る
  (CI では取り込んだ証明書をランナーのシステムキーチェーンで信頼させている)
- 証明書(秘密鍵ごと)の .p12 はリポジトリの外に保管する。失くすと作り直すしかなく、全利用者の許可が一度外れる

### 初回の準備(メンテナーが行う)

1. キーチェーンアクセスで "TatakiNote Code Signing" を秘密鍵ごと .p12 で書き出す(パスワードを付ける)
2. Secrets を登録する:

   ```bash
   base64 -i TatakiNote.p12 | gh secret set MACOS_CERT_P12_BASE64 -R tk-niway/tataki-note
   gh secret set MACOS_CERT_PASSWORD -R tk-niway/tataki-note
   ```

3. 証明書の SHA-1 が `release.conf` と同じか確かめる:
   `security find-certificate -c "TatakiNote Code Signing" -Z | grep SHA-1`

### Xcode のバージョン

ワークフロー(release.yml・test.yml)は `macos-26` ランナーの `/Applications/Xcode_<XCODE_MAJOR>*.app` を使う
(各ファイルの `XCODE_MAJOR`、今は 27)。ランナーにその版が無いときは、ある中で一番新しい Xcode を警告付きで使う。
それでビルドできなければ、ランナーの画像が追いつくのを待つ。

## 自動アップデート(Sparkle)を足すとき

今の配布物はそのまま使える形にしてある: CFBundleVersion = 版(下げない)、`ditto` の zip、ファイル名
`TatakiNote-<版>.zip`、毎回同じ証明書。`release.sh` の build と upload の間に、`sign_update` で EdDSA 署名して
appcast.xml を作る段を足す。SwiftPM の依存と Info.plist のキー(`SUFeedURL`・`SUPublicEDKey`)は Xcode で入れ、
EdDSA の秘密鍵は Secrets に置く。Sparkle の入っていない版の利用者は、一度だけ手で更新する。
