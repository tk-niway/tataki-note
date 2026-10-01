#!/bin/bash
# TatakiNote の配布物を作り、GitHub Releases に下書きとして載せる。
# 使い方: ./scripts/release.sh <コマンド> [オプション]
#   check            VERSION の版をリリースするかを判定する(release=yes / release=no を出力。
#                    GitHub Actions では GITHUB_OUTPUT にも書く)。公開済みなら no、未作成か下書きなら yes
#   select-xcode     CI 用。/Applications/Xcode_<XCODE_MAJOR>*.app の一番新しいもの(無ければ、ある中で一番新しい Xcode)を選ぶ(sudo を使う)
#   test             単体テスト(TatakiNoteTests)を署名なしで流す
#   build [--keychain <キーチェーン>]
#                    Release ビルド → 証明書で署名 → 検証 → dist/ に TatakiNote.app と
#                    TatakiNote-<版>.zip(と .sha256)を作る。キーチェーン省略時は既定の検索リスト
#   upload           dist/ の zip と release-notes/v<版>.md で、GitHub に下書きのリリースを作る
#                    (下書きがあれば本文と添付を差し替え、公開済みなら何もしない)。gh が要る
# 版は VERSION(x.y.z)、リリースノートは release-notes/v<版>.md、設定は scripts/release.conf。
set -euo pipefail
export GIT_PAGER=cat

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=release.conf
. "$APP_ROOT/scripts/release.conf"

DIST="$APP_ROOT/dist"
DERIVED="$APP_ROOT/.build/release"

die() { echo "エラー: $*" >&2; exit 1; }

read_version() {
  [ -f "$APP_ROOT/VERSION" ] || die "VERSION がありません: $APP_ROOT/VERSION"
  VERSION="$(tr -d '[:space:]' < "$APP_ROOT/VERSION")"
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION は x.y.z の形にしてください: '$VERSION'"
  TAG="v$VERSION"
  NOTES="$APP_ROOT/release-notes/$TAG.md"
  ZIP="$DIST/$APP_NAME-$VERSION.zip"
}

require_notes() {
  [ -s "$NOTES" ] || die "リリースノートがありません: release-notes/$TAG.md"
}

# release_state … GitHub 上の $TAG のリリースの状態(none / draft / published)
release_state() {
  local out err
  err="$(mktemp)"
  if out="$(gh release view "$TAG" --json isDraft --jq .isDraft 2>"$err")"; then
    rm -f "$err"
    [ "$out" = true ] && echo draft || echo published
    return 0
  fi
  if grep -qi "not found" "$err"; then
    rm -f "$err"
    echo none
    return 0
  fi
  cat "$err" >&2
  rm -f "$err"
  die "リリースの状態を取得できませんでした($TAG)"
}

cmd_check() {
  read_version
  require_notes
  local state release
  state="$(release_state)"
  if [ "$state" = published ]; then
    echo "$TAG は公開済みです。リリースしません。"
    release=no
  else
    echo "$TAG をリリースします(GitHub 上の状態: $state)。"
    release=yes
  fi
  echo "release=$release"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    { echo "release=$release"; echo "version=$VERSION"; } >> "$GITHUB_OUTPUT"
  fi
}

cmd_select_xcode() {
  local major="${XCODE_MAJOR:?XCODE_MAJOR を指定してください}" xcode
  xcode="$(ls -d /Applications/Xcode_"$major"*.app 2>/dev/null | sort -V | tail -1 || true)"
  if [ -z "$xcode" ]; then
    # ランナーの画像に新しい Xcode が入るまでは、ある中で一番新しいものを使う
    xcode="$(ls -d /Applications/Xcode_[0-9]*.app 2>/dev/null | sort -V | tail -1 || true)"
    [ -n "$xcode" ] || die "Xcode がありません"
    echo "::warning::Xcode $major がランナーにありません。$(basename "$xcode") を使います"
  fi
  sudo xcode-select -s "$xcode"
  xcodebuild -version
}

cmd_test() {
  cd "$APP_ROOT"
  xcodebuild test \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -destination 'platform=macOS' \
    -derivedDataPath "$APP_ROOT/.build/test" \
    -only-testing:"${APP_NAME}Tests" \
    -skipPackagePluginValidation -skipMacroValidation \
    CODE_SIGNING_ALLOWED=NO \
    -quiet
}

cmd_build() {
  local keychain=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --keychain) keychain="${2:?--keychain にはキーチェーンを指定してください}"; shift 2 ;;
      *) die "不明な引数: $1" ;;
    esac
  done
  read_version
  local kc_args=()
  [ -n "$keychain" ] && kc_args=(--keychain "$keychain")

  echo "==> ビルド (Release, $VERSION)"
  cd "$APP_ROOT"
  # 署名は後で codesign で行う(Xcode の署名は、信頼設定の無い自己署名証明書を使えないため)
  xcodebuild build \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED" \
    -skipPackagePluginValidation -skipMacroValidation \
    CODE_SIGNING_ALLOWED=NO \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$VERSION" \
    -quiet
  local built="$DERIVED/Build/Products/Release/$APP_NAME.app"
  [ -d "$built" ] || die "ビルド成果物が見つかりません: $built"

  rm -rf "$DIST"
  mkdir -p "$DIST"
  local app="$DIST/$APP_NAME.app"
  ditto "$built" "$app"

  echo "==> 署名"
  # 中に入っているコード(あれば)を先に、最後に .app 本体を署名する
  local item
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    codesign --force --timestamp=none --sign "$CERT_SHA1" ${kc_args[@]+"${kc_args[@]}"} "$item"
  done <<EOF
$(find "$app/Contents" -depth \( -name '*.framework' -o -name '*.dylib' -o -name '*.appex' -o -name '*.xpc' \) 2>/dev/null)
EOF
  codesign --force --timestamp=none --sign "$CERT_SHA1" ${kc_args[@]+"${kc_args[@]}"} "$app"

  echo "==> 検証"
  local sha1 req
  sha1="$(echo "$CERT_SHA1" | tr '[:upper:]' '[:lower:]')"
  req="identifier \"$BUNDLE_ID\" and certificate leaf = H\"$sha1\""
  if ! codesign --verify --strict --deep -R="$req" "$app"; then
    echo "署名を検証できませんでした。次を確かめてください:" >&2
    echo "  - 証明書(SHA-1 $CERT_SHA1)がキーチェーンにあり、コード署名用に信頼されていること" >&2
    echo "    (CSSMERR_TP_NOT_TRUSTED のときは信頼設定が無い)" >&2
    echo "  - scripts/release.conf の CERT_SHA1 が、配布に使ってきた証明書のものであること" >&2
    exit 1
  fi
  local plist="$app/Contents/Info.plist" short bundle_version
  short="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
  bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
  [ "$short" = "$VERSION" ] && [ "$bundle_version" = "$VERSION" ] \
    || die "Info.plist の版が VERSION と違います(CFBundleShortVersionString=$short, CFBundleVersion=$bundle_version)"
  codesign -d -r- "$app" 2>&1 | grep designated || true

  echo "==> zip"
  ditto -c -k --keepParent "$app" "$ZIP"
  (cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
  echo "完了:"
  echo "  $app"
  echo "  $ZIP"
}

cmd_upload() {
  read_version
  require_notes
  [ -f "$ZIP" ] && [ -f "$ZIP.sha256" ] || die "配布物がありません。先に build を実行してください: $ZIP"
  command -v gh >/dev/null || die "gh がありません"
  local target="${GITHUB_SHA:-$(git -C "$APP_ROOT" rev-parse HEAD)}"
  local state
  state="$(release_state)"
  case "$state" in
    published)
      echo "$TAG は公開済みです。何もしません。"
      ;;
    none)
      echo "==> 下書きのリリースを作る: $TAG"
      gh release create "$TAG" --draft --target "$target" --title "$APP_NAME $VERSION" \
        --notes-file "$NOTES" "$ZIP" "$ZIP.sha256"
      ;;
    draft)
      echo "==> 下書きのリリースを更新する: $TAG"
      gh release edit "$TAG" --draft --target "$target" --title "$APP_NAME $VERSION" --notes-file "$NOTES"
      gh release upload "$TAG" "$ZIP" "$ZIP.sha256" --clobber
      ;;
  esac
  [ "$state" = published ] || echo "GitHub の Releases で下書きを確認し、Publish してください。"
}

[ $# -ge 1 ] || { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
cmd="$1"; shift
case "$cmd" in
  check) cmd_check "$@" ;;
  select-xcode) cmd_select_xcode "$@" ;;
  test) cmd_test "$@" ;;
  build) cmd_build "$@" ;;
  upload) cmd_upload "$@" ;;
  *) die "不明なコマンド: $cmd(check / select-xcode / test / build / upload)" ;;
esac
