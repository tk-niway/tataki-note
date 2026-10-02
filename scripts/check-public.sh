#!/usr/bin/env bash
# 公開してよい内容かを確かめる。リポジトリのファイルとコミットメッセージに、決まりに合わないコメントや
# 手元の環境の情報が入っていないかを見る。Claude Code の hook・git の hook・CI が同じこのスクリプトを呼ぶ。
#
#   scripts/check-public.sh --files <パス>…      指定したファイル
#   scripts/check-public.sh --changed            作業ツリーで変わったファイル(未追跡を含む)
#   scripts/check-public.sh --staged             ステージしたファイル(ステージした内容を見る)
#   scripts/check-public.sh --all                追跡しているすべてのファイル
#   scripts/check-public.sh --range <a>..<b>     範囲で変わったファイル(<b> の内容)と、各コミットのメッセージ
#   scripts/check-public.sh --message <文>       文(PR のタイトルなど)
#   scripts/check-public.sh --message-file <ファイル>  コミットメッセージ(# で始まる行は除く)
#
# 問題があれば「場所: 内容」を1行ずつ出して 1 を返す。
#
# 決まり
# - Swift のコメントは次だけ:
#   - `// MARK: <見出し>`
#   - 宣言の直前の `///`(private・fileprivate でない、外から呼ばれる型・メソッド・プロパティなどの説明)
#   - テストの受け入れ条件の目印 `// AC-<番号>`
#   `/* */` は使わない。コメントに TODO・今後の予定・一時的な対応の印を書かない。
# - どのファイルにも、コミットメッセージにも、手元の作業場所のパスを書かない。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF="scripts/check-public.sh"
# このスクリプトと、その確認用のスクリプトは、検出する文字列そのものを含むので内容を検査しない
EXEMPT_RE='^scripts/(check-public|test-check-public)\.sh$'

# 手元の作業場所(別の作業用リポジトリの置き場所・ホームディレクトリの下の具体的な場所)
LOCAL_PATH_RE='(^|[^A-Za-z0-9_.])(ai-pipeline/|\.ai-pipeline/|\.worktrees/|01_idea/|02_plans/|03_designs/|99_archives/)|/Users/[^/"'"'"' ]+/|/private/var/folders/'
# コメントに書かない言葉(今後の予定・一時的な対応)
COMMENT_WORDS_RE='TODO|FIXME|XXX|HACK|予定|将来|今後|暫定'

usage() { sed -n '4,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-public.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PROBLEMS="$TMP/problems"
: >"$PROBLEMS"
problem() { printf '%s\n' "$*" >>"$PROBLEMS"; }

g() { git -C "$ROOT" "$@"; }

# 検査するファイルの一覧: 「表示する名前<TAB>中身のあるパス」
LIST="$TMP/list"
: >"$LIST"

# add_file <リポジトリからの相対パス> [中身のあるパス]
add_file() {
  local rel="$1" path="${2:-$ROOT/$1}"
  [[ "$rel" =~ $EXEMPT_RE ]] && return 0
  [ -f "$path" ] || return 0
  printf '%s\t%s\n' "$rel" "$path" >>"$LIST"
}

# add_from_rev <リビジョン> <相対パス>  … その版の中身を一時ファイルに書き出して加える
add_from_rev() {
  local rev="$1" rel="$2" out
  [[ "$rel" =~ $EXEMPT_RE ]] && return 0
  out="$TMP/rev/$rel"
  mkdir -p "$(dirname "$out")"
  g show "$rev:$rel" >"$out" 2>/dev/null || return 0
  printf '%s\t%s\n' "$rel" "$out" >>"$LIST"
}

# check_message <場所> <文>
check_message() {
  local where="$1" text="$2" hit
  hit="$(printf '%s\n' "$text" | grep -nE "$LOCAL_PATH_RE" || true)"
  [ -z "$hit" ] || while IFS= read -r l; do
    problem "$where: 手元の作業場所のパスが書かれています: ${l#*:}"
  done <<<"$hit"
}

rel_of() {
  local p="$1"
  case "$p" in
    /*) ;;
    *) p="$PWD/$p" ;;
  esac
  case "$p" in
    "$ROOT"/*) printf '%s\n' "${p#"$ROOT"/}" ;;
    *) return 1 ;;
  esac
}

[ $# -gt 0 ] || usage
MODE="$1"; shift
case "$MODE" in
  --files)
    for f in "$@"; do
      rel="$(rel_of "$f")" || continue
      add_file "$rel"
    done
    ;;
  --changed)
    { g diff --name-only --diff-filter=d HEAD 2>/dev/null || true
      g ls-files --others --exclude-standard
    } | sort -u | while IFS= read -r rel; do add_file "$rel"; done
    ;;
  --staged)
    g diff --cached --name-only --diff-filter=d | while IFS= read -r rel; do add_from_rev "" "$rel"; done
    ;;
  --all)
    g ls-files | while IFS= read -r rel; do add_file "$rel"; done
    ;;
  --range)
    [ $# -eq 1 ] || usage
    range="$1"; base_rev="${range%%..*}"; head_rev="${range##*..}"
    # 分かれた所からの変更だけを見る(<a> の側が後から進んでいても、その分は含めない)
    g diff --name-only --diff-filter=d "$base_rev...$head_rev" | while IFS= read -r rel; do add_from_rev "$head_rev" "$rel"; done
    for c in $(g rev-list "$range"); do
      check_message "コミット $(g log -1 --format='%h %s' "$c")" "$(g log -1 --format='%B' "$c")"
    done
    ;;
  --message)
    [ $# -eq 1 ] || usage
    check_message "メッセージ" "$1"
    ;;
  --message-file)
    [ $# -eq 1 ] || usage
    check_message "コミットメッセージ" "$(grep -v '^#' "$1" || true)"
    ;;
  *) usage ;;
esac

# --- ファイルの中身 ------------------------------------------------------------------------------

if [ -s "$LIST" ]; then
  # 手元の作業場所のパス(テキストのファイルだけ)
  while IFS=$'\t' read -r rel path; do
    hit="$(LC_ALL=C grep -InE "$LOCAL_PATH_RE" "$path" 2>/dev/null | head -5 || true)"
    [ -z "$hit" ] || while IFS= read -r l; do
      problem "$rel:${l%%:*}: 手元の作業場所のパスが書かれています: ${l#*:}"
    done <<<"$hit"
  done <"$LIST"

  # Swift のコメント
  awk -F'\t' '$1 ~ /\.swift$/' "$LIST" >"$TMP/swift"
  if [ -s "$TMP/swift" ]; then
    swift_paths=()
    while IFS=$'\t' read -r _ path; do swift_paths+=("$path"); done <"$TMP/swift"
    # shellcheck disable=SC2016
    LC_ALL=C awk -v words="$COMMENT_WORDS_RE" '
      # lex(行) … 文字列・ブロックコメントの外で最初に現れる // の位置を CPOS に(無ければ 0)、
      #   /* を含めば HAS_BLOCK を 1 に。複数行の文字列とブロックコメントは ML / BLK で次の行へ持ち越す
      function lex(s,   i, n, c, c2, j) {
        CPOS = 0; HAS_BLOCK = 0
        n = length(s); i = 1
        while (i <= n) {
          if (BLK) { j = index(substr(s, i), "*/"); if (j == 0) return; i += j + 1; BLK = 0; continue }
          if (ML) { j = index(substr(s, i), "\"\"\""); if (j == 0) return; i += j + 2; ML = 0; continue }
          c = substr(s, i, 1)
          if (substr(s, i, 3) == "\"\"\"") { ML = 1; i += 3; continue }
          if (c == "#" && substr(s, i + 1, 1) == "\"") {
            j = index(substr(s, i + 2), "\"#"); if (j == 0) return; i += j + 3; continue
          }
          if (c == "\"") {
            j = i + 1
            while (j <= n) {
              c2 = substr(s, j, 1)
              if (c2 == "\\") { j += 2; continue }
              if (c2 == "\"") break
              j++
            }
            i = j + 1; continue
          }
          c2 = substr(s, i, 2)
          if (c2 == "//") { CPOS = i; return }
          if (c2 == "/*") { HAS_BLOCK = 1; BLK = 1; i += 2; continue }
          i++
        }
      }
      function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
      # 外から呼ばれる宣言か(属性・修飾子の後に宣言のキーワードがあり、private・fileprivate でない)
      function is_public_decl(s,   t) {
        t = " " trim(s) " "
        if (t ~ /[ \t](private|fileprivate)[ \t]/) return 0
        gsub(/@[A-Za-z_][A-Za-z0-9_.]*(\([^)]*\))?/, " ", t)
        gsub(/(private|fileprivate|internal|public|open)\(set\)/, " ", t)
        gsub(/(nonisolated|unowned)\([a-z]+\)/, " ", t)
        t = trim(t)
        while (t ~ /^(public|open|internal|package|final|static|override|required|convenience|nonisolated|mutating|nonmutating|lazy|weak|unowned|indirect|dynamic|distributed|isolated|consuming|borrowing)[ \t]/) {
          sub(/^[A-Za-z]+[ \t]+/, "", t)
        }
        return t ~ /^(class|struct|enum|protocol|extension|actor|func|var|let|init|init\?|init!|deinit|subscript|typealias|associatedtype|case|macro)([^A-Za-z0-9_]|$)/
      }
      function report(f, n, msg) { print f ":" n ": " msg }
      function flush_doc(ok,   k) {
        if (!ok) for (k = 1; k <= ndoc; k++)
          report(docf, docl[k], "/// は、外から呼ばれる宣言(private・fileprivate でないもの)の直前にだけ書きます: " doct[k])
        ndoc = 0
      }
      FNR == 1 {
        if (NR > 1) flush_doc(0)
        ML = 0; BLK = 0; ndoc = 0
        name = (FILENAME in display) ? display[FILENAME] : FILENAME
      }
      NR == FNR && FILENAME == ARGV[1] { display[$2] = $1; next }
      {
        line = $0
        lex(line)
        if (HAS_BLOCK) report(name, FNR, "/* */ は使いません")
        before = (CPOS > 0) ? substr(line, 1, CPOS - 1) : line
        code = trim(before)

        if (CPOS > 0) {
          text = substr(line, CPOS + 2); doc = 0
          if (substr(text, 1, 1) == "/") { doc = 1; text = substr(text, 2) }
          text = trim(text)
          if (!doc && text ~ /^MARK:/) {
            if (text ~ words) report(name, FNR, "コメントに予定や一時的な対応を書きません: " text)
          } else if (!doc && text ~ /^AC-[0-9]+([ ,]+AC-[0-9]+)*$/) {
            # テストの受け入れ条件の目印
          } else if (doc && code == "") {
            if (text ~ words) report(name, FNR, "コメントに予定や一時的な対応を書きません: " text)
            doct[++ndoc] = text; docl[ndoc] = FNR; docf = name
            next
          } else {
            report(name, FNR, "このコメントは書けません(MARK・宣言の直前の ///・AC-<番号> だけ): " (doc ? "///" : "//") " " text)
          }
        }

        if (ndoc > 0) {
          if (code == "") { flush_doc(0); next }
          if (code ~ /^@[A-Za-z_][A-Za-z0-9_.]*(\([^)]*\))?$/) next
          flush_doc(is_public_decl(code))
        }
      }
      END { flush_doc(0) }
    ' "$TMP/swift" "${swift_paths[@]}" >>"$PROBLEMS"
  fi
fi

if [ -s "$PROBLEMS" ]; then
  cat "$PROBLEMS"
  exit 1
fi
exit 0
