#!/usr/bin/env bash
# Claude Code の hook から呼ぶ。Claude が書いたものを scripts/check-public.sh で確かめ、決まりに合わなければ
# Claude に差し戻す(exit 2 の標準エラーが Claude に渡る)。
#
#   claude-hook.sh post-edit   … PostToolUse(Edit・Write・MultiEdit)。書いたファイルを確かめる
#   claude-hook.sh stop        … Stop。作業ツリーで変わったファイル全体を確かめる(Bash で書いた分も拾う)
#
# hook の入力(JSON)は標準入力で受け取る。このリポジトリの外のファイルは見ない。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/scripts/check-public.sh"
INPUT="$(cat)"

# json_get <キー(. 区切り)>  … 入力の JSON から文字列を取り出す(無ければ空)
json_get() {
  if command -v plutil >/dev/null 2>&1; then
    printf '%s' "$INPUT" | plutil -extract "$1" raw -o - - 2>/dev/null || true
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$INPUT" | python3 -c '
import json, sys
v = json.load(sys.stdin)
for k in sys.argv[1].split("."):
    v = v.get(k) if isinstance(v, dict) else None
print("" if v is None else (str(v).lower() if isinstance(v, bool) else v))' "$1" 2>/dev/null || true
  fi
}

case "${1:-}" in
  post-edit)
    file="$(json_get tool_input.file_path)"
    [ -n "$file" ] || exit 0
    case "$file" in "$ROOT"/*) ;; *) exit 0 ;; esac
    if ! out="$("$CHECK" --files "$file" 2>&1)"; then
      printf '公開の決まりに合わない内容があります。直してください(決まりは CLAUDE.md の「コメント」):\n%s\n' "$out" >&2
      exit 2
    fi
    ;;
  stop)
    if ! out="$("$CHECK" --changed 2>&1)"; then
      if [ "$(json_get stop_hook_active)" = "true" ]; then
        # 一度差し戻した後も残っている。止め続けると終われないので、知らせるだけにする(commit の hook と CI が止める)
        printf '公開の決まりに合わない内容が残っています:\n%s\n' "$out" >&2
        exit 0
      fi
      printf '終える前に、公開の決まりに合わない内容を直してください(決まりは CLAUDE.md の「コメント」):\n%s\n' "$out" >&2
      exit 2
    fi
    ;;
  *)
    echo "使い方: $0 post-edit|stop" >&2
    exit 1
    ;;
esac
exit 0
