#!/usr/bin/env bash
# scripts/check-public.sh の確認。一時的なリポジトリに見本を置いて、通るもの・止まるものを確かめる。
#   scripts/test-check-public.sh
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/check-public.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-check-public.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO/scripts" "$REPO/App"
cp "$SRC" "$REPO/scripts/check-public.sh"
git -C "$REPO" init -q
git -C "$REPO" config user.name test
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config commit.gpgsign false
CHECK="$REPO/scripts/check-public.sh"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); }
ng() { FAIL=$((FAIL + 1)); printf 'NG: %s\n' "$*"; }

# expect_pass <説明> <引数>…
expect_pass() {
  local name="$1" out; shift
  if out="$("$CHECK" "$@" 2>&1)"; then ok; else ng "$name: 通るはずが止まった"; printf '%s\n' "$out"; fi
}
# expect_fail <説明> <出力に含まれるべき文字列> <引数>…
expect_fail() {
  local name="$1" want="$2" out; shift 2
  if out="$("$CHECK" "$@" 2>&1)"; then
    ng "$name: 止まるはずが通った"
  elif [[ "$out" != *"$want"* ]]; then
    ng "$name: 出力に「$want」が無い"; printf '%s\n' "$out"
  else
    ok
  fi
}

# --- 通るコメント --------------------------------------------------------------------------------

cat >"$REPO/App/Good.swift" <<'EOF'
import Foundation

// MARK: - 保存

/// 設定を読み書きする。
@MainActor
final class Store {
    /// 今の値。
    private(set) var value = 0
    let url = "https://example.com//path"
    let raw = #"a // b"#
    let multi = """
    // 文字列の中
    """
    func save() {}

    /// 値を1増やす。
    @discardableResult
    func increment() -> Int { value += 1; return value }

    private func hidden() {}
}

/// 種類。
enum Kind {
    /// 1つ目。
    case one
}

func test() {
    // AC-1
}
EOF
expect_pass "決まりに合うコメント" --files "$REPO/App/Good.swift"

# --- 止まるコメント ------------------------------------------------------------------------------

cat >"$REPO/App/Free.swift" <<'EOF'
func a() {
    // 値を足す
}
EOF
expect_fail "普通のコメント" "このコメントは書けません" --files "$REPO/App/Free.swift"

cat >"$REPO/App/Header.swift" <<'EOF'
//
//  Header.swift
//  App
//
struct Header {}
EOF
expect_fail "Xcode のファイルの見出し" "Header.swift:2: このコメントは書けません" --files "$REPO/App/Header.swift"

cat >"$REPO/App/Private.swift" <<'EOF'
struct S {
    /// 中だけで使う。
    private func f() {}
}
EOF
expect_fail "private の宣言への ///" "Private.swift:2: /// は、外から呼ばれる宣言" --files "$REPO/App/Private.swift"

cat >"$REPO/App/Detached.swift" <<'EOF'
/// 離れた説明。

struct D {}
EOF
expect_fail "宣言から離れた ///" "Detached.swift:1:" --files "$REPO/App/Detached.swift"

cat >"$REPO/App/Trailing.swift" <<'EOF'
let x = 1 /// 行末の説明
EOF
expect_fail "行末の ///" "このコメントは書けません" --files "$REPO/App/Trailing.swift"

cat >"$REPO/App/Block.swift" <<'EOF'
/* まとめて */
struct B {}
EOF
expect_fail "/* */" "/* */ は使いません" --files "$REPO/App/Block.swift"

cat >"$REPO/App/Todo.swift" <<'EOF'
/// TODO: あとで直す
func later() {}
EOF
expect_fail "TODO" "予定や一時的な対応" --files "$REPO/App/Todo.swift"

cat >"$REPO/App/NoteId.swift" <<'EOF2'
// @note p3-2
struct N {}
EOF2
expect_fail "以前のコメントの ID" "このコメントは書けません" --files "$REPO/App/NoteId.swift"

cat >"$REPO/App/Plan.swift" <<'EOF'
// MARK: 今後の予定
struct P {}
EOF
expect_fail "MARK の予定" "予定や一時的な対応" --files "$REPO/App/Plan.swift"

# --- 手元の作業場所のパス ------------------------------------------------------------------------

printf 'see ai-pipeline/notes/p0.md\n' >"$REPO/README.md"
expect_fail "内部のパス" "README.md:1: 手元の作業場所のパス" --files "$REPO/README.md"
printf 'log: /Users/someone/works/x.log\n' >"$REPO/README.md"
expect_fail "ホームの下のパス" "手元の作業場所のパス" --files "$REPO/README.md"
printf 'HOME は "/Users/test" のように渡す\n' >"$REPO/README.md"
expect_pass "/Users/<名前> だけ" --files "$REPO/README.md"

expect_pass "プラン番号の入った件名" --message "パネルに閉じるボタンを付ける — タスク1/3 (plan-18)"
expect_fail "パスの入った件名" "手元の作業場所のパス" --message "実行ログ: .ai-pipeline/runs/x"
printf 'subject\n\n# .worktrees/x はコメントなので見ない\n' >"$TMP/msg"
expect_pass "コミットメッセージの # 行" --message-file "$TMP/msg"

# --- 変わったファイル・ステージ・範囲 ------------------------------------------------------------

rm -f "$REPO"/App/*.swift "$REPO/README.md"
printf 'struct Base {}\n' >"$REPO/App/Base.swift"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "base"
BASE="$(git -C "$REPO" rev-parse HEAD)"
expect_pass "変更なし" --changed

printf 'struct Base {} // 説明\n' >"$REPO/App/Base.swift"
expect_fail "--changed は作業ツリーを見る" "Base.swift:1:" --changed
expect_pass "--staged はステージした内容だけを見る" --staged
git -C "$REPO" add App/Base.swift
expect_fail "--staged" "Base.swift:1:" --staged

git -C "$REPO" commit -qm "add comment" -m "実行ログ: /Users/someone/works/run.log"
expect_fail "--range のファイル" "App/Base.swift:1:" --range "$BASE..HEAD"
expect_fail "--range のメッセージ" "コミット" --range "$BASE..HEAD"

printf '%d 件通過' "$PASS"
if [ "$FAIL" -gt 0 ]; then
  printf '、%d 件失敗\n' "$FAIL"
  exit 1
fi
printf '\n'
