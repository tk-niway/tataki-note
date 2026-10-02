#!/usr/bin/env bash
# clone した後に一度だけ実行する。コミットのときに公開の決まりを確かめる git の hook(.githooks/)を有効にする。
#   scripts/setup.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
git -C "$ROOT" config core.hooksPath .githooks
chmod +x "$ROOT"/.githooks/* "$ROOT"/scripts/*.sh
echo "git の hook を有効にしました(core.hooksPath = .githooks)"
