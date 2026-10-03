# リリース(アプリの配布)

TatakiNote は、このリポジトリの GitHub Releases で配布する。CI(GitHub Actions)では AI を使わない。
リリースノートと版はマージの前に用意し、人が見る(ローカルでの作成時と、PR の差分)。マージすると自動で公開される。

## 流れ

1. `main` を最新にして、`scripts/release-prep.sh` を実行する(手元の Claude Code を使う。メンテナーが行う)
   - 前のリリース(いちばん新しいタグ `v*`)から今までの変更をもとに、利用者ガイド `docs/` の書き漏れ・
     事実と違う箇所を直す(書き方は [`update-docs` スキル](.claude/skills/update-docs/SKILL.md))。
     パイプラインを使わずに入った変更や、他の人の PR の分も、ここで追いつかせる
   - 次の版を提案し、`VERSION` と `release-notes/v<版>.md` を書く(下の「版の決め方」「リリースノートの書き方」)
   - コミットはしない。版を自分で決めるときは `--version x.y.z`、docs をもう直してあるときは `--skip-docs`
   - Claude Code が使えないときは、同じものを手で用意する
2. 読んで直し、ブランチ(例: `release/v1.1.0`)を切ってコミットし、`main` への PR を作ってマージする
3. `.github/workflows/release.yml` が動く。`VERSION` の版が公開済みでなければ、単体テスト → Release ビルド →
   証明書で署名・検証 → zip → 公開するリリース(本文 = リリースノート、添付 = `TatakiNote-<版>.zip` と `.sha256`)。
   `VERSION`・`release-notes/` を変えていないマージでは動かない
4. 公開される。タグ `v<版>` はこのときに付く。本文や添付を直すときは、GitHub の Releases で編集する

失敗したら、直して `main` に入れ直すか、Actions の画面から `Release` を手動で再実行する(workflow_dispatch)。
同じ版の下書きがあれば本文と添付を差し替えて公開し、公開済みなら何もしない。

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

## GitHub の設定(メンテナーが一度だけ行う)

`main` は PR でしか変えられない。PR には、検査(単体テストと公開の決まり)が通ることと、メンテナーの承認が要る。
自分の PR は自分で承認できないので、承認のルールだけはメンテナー(リポジトリの管理者)を例外にする。
そのため、ルールセットを2つに分ける。

1. **main: checks**(例外なし) — PR 必須、必須のチェック `Unit tests`(`.github/workflows/test.yml`)と
   `Public check`(`.github/workflows/public-check.yml`)、削除と強制 push の禁止
2. **main: approval**(管理者だけ例外) — CODEOWNERS(`.github/CODEOWNERS`)の承認が1件必須。承認の後に
   push があれば承認し直す

```bash
# 今のルールセット(名前 main)の番号を調べて、1. に置き換える
gh api repos/tk-niway/tataki-note/rulesets --jq '.[] | [.id, .name] | @tsv'
gh api -X PUT repos/tk-niway/tataki-note/rulesets/<番号> --input - <<'EOF'
{
  "name": "main: checks",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "Unit tests", "integration_id": 15368 },
          { "context": "Public check", "integration_id": 15368 } ] } }
  ]
}
EOF

# 2. を足す(actor_id 5 はリポジトリの管理者の役割)
gh api -X POST repos/tk-niway/tataki-note/rulesets --input - <<'EOF'
{
  "name": "main: approval",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [ { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" } ],
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": true,
        "require_last_push_approval": true,
        "required_review_thread_resolution": false } }
  ]
}
EOF

# マージはマージコミットだけ(squash・rebase はしない)。件名は PR のタイトル。マージしたブランチは消す
gh api -X PATCH repos/tk-niway/tataki-note \
  -F allow_merge_commit=true -F allow_squash_merge=false -F allow_rebase_merge=false \
  -f merge_commit_title=PR_TITLE -f merge_commit_message=PR_BODY -F delete_branch_on_merge=true
```

`integration_id: 15368` は GitHub Actions。ジョブ名(`name: Unit tests`・`name: Public check`)を変えたら、ルールセットも直す。
メンテナーが自分の PR をマージするときは、承認のルールだけを飛ばす(GitHub の画面の「Merge without waiting for
requirements to be met」、`gh pr merge --admin`)。検査は飛ばせない。

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
