#!/usr/bin/env bash
# リリースの準備。前のリリースから今(HEAD)までの変更をもとに、手元の Claude に次の2つをさせる。
# どちらもコミットはしない(人が読んで直してから、ブランチを切ってコミットし、PR にする)。
#   1. 利用者ガイド(docs/)の書き漏れ・事実と違う箇所を直す(.claude/skills/update-docs/SKILL.md の決まりで)。
#      パイプラインを使わない変更や、他の人の PR の分も、ここで追いつかせる
#   2. 次の版を提案し、VERSION と release-notes/v<版>.md を書く(直した後の docs も材料にする)
#
#   scripts/release-prep.sh [--version x.y.z] [--force] [--skip-docs]
#     --version    版を自分で決める(Claude の提案より優先。リリースノートは Claude が書く)
#     --force      同じ版のリリースノートが既にあっても書き直す
#     --skip-docs  1. を飛ばす(docs をもう直してあるとき)
#
# 前のリリース = いちばん新しいタグ v*(GitHub で Publish したときに付く)。タグが無ければ、
# release-notes/ でいちばん新しい版のファイルを追加したコミット。どちらも無ければ初回のリリース。
# 材料にするのはコミット済みの変更だけ。claude(Claude Code)に、ログインしてある必要がある。
set -euo pipefail
export GIT_PAGER=cat

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NOTES_DIR="$ROOT/release-notes"
VERSION_FILE="$ROOT/VERSION"
PROMPT="$ROOT/scripts/release-notes-prompt.md"
g() { git -C "$ROOT" "$@"; }

WANT=""
FORCE=0
SKIP_DOCS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --version) WANT="${2:?--version には x.y.z を指定してください}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --skip-docs) SKIP_DOCS=1; shift ;;
    *) echo "不明な引数: $1" >&2; exit 2 ;;
  esac
done
semver_re='^[0-9]+\.[0-9]+\.[0-9]+$'
if [ -n "$WANT" ] && ! [[ "$WANT" =~ $semver_re ]]; then
  echo "版は x.y.z の形で指定してください: $WANT" >&2
  exit 2
fi
command -v claude >/dev/null || { echo "claude(Claude Code)がありません" >&2; exit 1; }

CURRENT="$(tr -d '[:space:]' < "$VERSION_FILE" 2>/dev/null || true)"
[[ "$CURRENT" =~ $semver_re ]] || { echo "VERSION が x.y.z の形ではありません: '$CURRENT'" >&2; exit 1; }

# ---- 前のリリース ----
g fetch -q --tags origin >/dev/null 2>&1 || true
PREV_TAG="$(g describe --tags --abbrev=0 --match 'v[0-9]*' HEAD 2>/dev/null || true)"
PREV_VERSION=""
BASE=""
if [ -n "$PREV_TAG" ]; then
  PREV_VERSION="${PREV_TAG#v}"
  BASE="$PREV_TAG"
else
  PREV_FILE="$(ls "$NOTES_DIR"/v*.md 2>/dev/null | sed 's|.*/v||; s|\.md$||' | sort -V | tail -1 || true)"
  if [ -n "$PREV_FILE" ]; then
    PREV_VERSION="$PREV_FILE"
    BASE="$(g log -1 --diff-filter=A --format=%H -- "release-notes/v$PREV_VERSION.md")"
    [ -n "$BASE" ] || { echo "前のリリースノート v$PREV_VERSION.md がコミットされていません。先にコミットしてください。" >&2; exit 1; }
  fi
fi

if [ -n "$BASE" ] && [ -z "$(g log --no-merges --format=%H "$BASE..HEAD" -- . ':!release-notes' ':!VERSION')" ]; then
  echo "v$PREV_VERSION の後に変更がありません。" >&2
  exit 1
fi
if [ -n "$(g status --porcelain -- . ':!VERSION' ':!release-notes')" ]; then
  echo "注意: 未コミットの変更があります。材料にするのはコミット済みの内容だけです。"
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/release-prep.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
limit() { head -c "$1"; }

# ---- 1. 利用者ガイド ----
if [ "$SKIP_DOCS" = 1 ]; then
  echo "==> 利用者ガイドの見直しは飛ばします(--skip-docs)"
elif [ -z "$BASE" ]; then
  echo "==> 初回のリリースなので、利用者ガイドの見直しは飛ばします"
else
  if [ -n "$(g status --porcelain -- docs)" ]; then
    echo "docs/ に未コミットの変更があります。コミットするか取り消してから実行してください(--skip-docs で飛ばせます)。" >&2
    exit 1
  fi
  BEFORE="$TMP/status-before"
  g status --porcelain > "$BEFORE"
  cat > "$TMP/docs-prompt.md" <<EOF
次のリリースの前に、利用者ガイド(docs/README.md と docs/features/*.md)を、今のアプリに合わせて直してください。

- まず .claude/skills/update-docs/SKILL.md を読み、その決まり(書くこと・書かないこと、事実の確かめ方、目次とページの形、ファイルの決まり)に従ってください。
- 材料は、前のリリース($BASE)から HEAD までの変更です。\`git log --no-merges $BASE..HEAD\` と \`git diff $BASE..HEAD -- <パス>\` で確かめられます。パイプラインを使わずに入った変更や、他の人の変更で、ガイドに書かれていない機能や、事実と違うようになった記述が無いかを見てください。
- 直すのは docs/ の中だけです。コードやほかのファイルは変えないでください。
- 終わったら、直したページと、直さなかった理由を短く報告してください。
EOF
  echo "==> Claude が利用者ガイドを見直しています(前のリリース: v$PREV_VERSION)"
  (cd "$ROOT" && claude -p --output-format text --strict-mcp-config --permission-mode dontAsk \
    --allowedTools "Read,Edit,Write,Grep,Glob,Bash(git log:*),Bash(git diff:*),Bash(git show:*)" \
    < "$TMP/docs-prompt.md") | tee "$TMP/docs-report.md"
  OUTSIDE="$(comm -13 <(sort "$BEFORE") <(g status --porcelain | sort) | awk 'substr($0, 4, 5) != "docs/"' || true)"
  if [ -n "$OUTSIDE" ]; then
    echo "" >&2
    echo "docs/ の外が変わりました。確かめて、不要なら取り消してください(リリースノートは書かずに止めます):" >&2
    printf '%s\n' "$OUTSIDE" >&2
    exit 1
  fi
fi

# ---- 2. リリースノート ----
MAT="$TMP/materials.md"
{
  if [ -n "$BASE" ]; then
    echo "### 前のリリース(v$PREV_VERSION)からのコミットの件名"
    g log --no-merges --reverse --format='- %s' "$BASE..HEAD" -- . ':!release-notes' ':!VERSION' | limit 30000
    echo
    echo "### 変更されたファイル"
    g diff --stat=200 "$BASE..HEAD" -- . ':!release-notes' ':!VERSION' | limit 20000
    echo
    echo "### 利用者向けの説明(README・docs)の差分(1. で直した分を含む)"
    echo '```diff'
    g diff "$BASE" -- README.md docs | limit 60000
    echo '```'
  else
    echo "### 初回のリリース。アプリの説明(README)"
    cat "$ROOT/README.md"
    echo
    echo "### 機能ごとの説明(docs/README.md)"
    cat "$ROOT/docs/README.md"
  fi
} > "$MAT"

sed -e "s|{{PREV_VERSION}}|${PREV_VERSION:-なし}|g" -e "s|{{CURRENT_VERSION}}|$CURRENT|g" "$PROMPT" \
  | awk -v mat="$MAT" '$0 == "{{MATERIALS}}" { while ((getline l < mat) > 0) print l; next } { print }' \
  > "$TMP/prompt.md"

echo
echo "==> Claude がリリースノートを書いています(前の版: ${PREV_VERSION:-なし})"
claude -p --output-format text --strict-mcp-config < "$TMP/prompt.md" > "$TMP/out.md"

# VERSION: / REASON: / --- / 本文 に分ける(コードブロックで囲まれていたら外す)
sed -e '/^```/d' "$TMP/out.md" > "$TMP/clean.md"
PROPOSED="$(sed -n 's/^VERSION:[[:space:]]*//p' "$TMP/clean.md" | head -1 | tr -d '[:space:]')"
REASON="$(sed -n 's/^REASON:[[:space:]]*//p' "$TMP/clean.md" | head -1)"
awk 'f { print } /^---[[:space:]]*$/ && !f { f = 1 }' "$TMP/clean.md" | sed -e '/./,$!d' > "$TMP/body.md"
if ! [[ "$PROPOSED" =~ $semver_re ]] || ! [ -s "$TMP/body.md" ]; then
  echo "Claude の出力を読み取れませんでした:" >&2
  cat "$TMP/out.md" >&2
  exit 1
fi

VERSION="${WANT:-$PROPOSED}"
echo "提案: $PROPOSED — $REASON"
[ -z "$WANT" ] || echo "指定された版を使います: $WANT"
if [ -n "$PREV_VERSION" ] && { [ "$(printf '%s\n%s\n' "$PREV_VERSION" "$VERSION" | sort -V | tail -1)" != "$VERSION" ] \
  || [ "$VERSION" = "$PREV_VERSION" ]; }; then
  echo "版 $VERSION は前の版 $PREV_VERSION より大きくありません。--version で指定し直してください。" >&2
  exit 1
fi

OUT="$NOTES_DIR/v$VERSION.md"
if [ -e "$OUT" ] && [ "$FORCE" != 1 ]; then
  echo "既にあります: release-notes/v$VERSION.md(書き直すときは --force)" >&2
  exit 1
fi
mkdir -p "$NOTES_DIR"
cp "$TMP/body.md" "$OUT"
echo "$VERSION" > "$VERSION_FILE"

echo
echo "==> 書いたもの(コミットはしていません)"
echo "  VERSION: $VERSION"
echo "  release-notes/v$VERSION.md"
[ "$SKIP_DOCS" = 1 ] || [ -z "$BASE" ] || echo "  docs/: $(g status --porcelain -- docs | wc -l | tr -d ' ') ファイル"
echo "----"
cat "$OUT"
echo "----"
if ! "$ROOT/scripts/check-public.sh" --files "$OUT" $(g status --porcelain -- docs | cut -c4- | sed "s|^|$ROOT/|") >&2; then
  echo "注意: 公開の決まりに合わない内容があります(上の表示)。直してからコミットしてください。" >&2
fi
echo "読んで直したら:"
echo "  git switch -c release/v$VERSION && git add VERSION release-notes docs && git commit -m \"$VERSION のリリースの準備\""
echo "  git push -u origin release/v$VERSION && gh pr create --base main --fill"
echo "  → main にマージすると Release のワークフローが下書きのリリースを作る → GitHub の Releases で確かめて Publish"
