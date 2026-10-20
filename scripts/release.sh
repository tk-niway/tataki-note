#!/bin/bash
# TatakiNote の配布物を作り、GitHub Releases に公開する。
# 使い方: ./scripts/release.sh <コマンド> [オプション]
#   check            VERSION の版をリリースするかを判定する(release=yes / release=no を出力。
#                    GitHub Actions では GITHUB_OUTPUT にも書く)。公開済みなら no、未作成か下書きなら yes
#   select-xcode     CI 用。/Applications/Xcode_<XCODE_MAJOR>*.app の一番新しいもの(無ければ、ある中で一番新しい Xcode)を選ぶ(sudo を使う)
#   test             単体テスト(TatakiNoteTests)を署名なしで流す
#   build [--keychain <キーチェーン>]
#                    Release ビルド → Developer ID で署名(hardened runtime・時刻印)→ 検証 → dist/ に
#                    TatakiNote.app と TatakiNote-<版>.zip(と .sha256)を作る。キーチェーン省略時は既定の検索リスト。
#                    時刻印に Apple のサーバーへの接続が要る
#   notarize         dist/ の .app を Apple の公証に出し、結果を .app に付けて(staple)zip を作り直す。
#                    資格情報は NOTARY_KEY_PATH・NOTARY_KEY_ID・NOTARY_ISSUER_ID(App Store Connect API キー)、
#                    無ければキーチェーンのプロファイル NOTARY_KEYCHAIN_PROFILE(既定 TatakiNote)。
#                    NOTARY_SUBMISSION_ID を付けると、出し直さずにその提出の結果を待つ(同じ .app のときだけ)
#   upload           dist/ の zip と release-notes/v<版>.md で、GitHub にリリースを公開する
#                    (下書きがあれば本文と添付を差し替えて公開し、公開済みなら何もしない)。gh が要る
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
  # 署名は後で codesign で行う(Xcode に任せると、ビルド設定の開発用の署名 ID と CI の一時キーチェーンに左右されるため)
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
  local sign_args=(--force --options runtime --timestamp --sign "$SIGN_IDENTITY" ${kc_args[@]+"${kc_args[@]}"})
  # 中に入っているコード(あれば)を先に、最後に .app 本体を署名する
  local item
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    codesign "${sign_args[@]}" "$item"
  done <<EOF
$(find "$app/Contents" -depth \( -name '*.framework' -o -name '*.dylib' -o -name '*.appex' -o -name '*.xpc' \) 2>/dev/null)
EOF
  codesign "${sign_args[@]}" "$app"

  echo "==> 検証"
  if ! codesign --verify --strict --deep -R="$(designated_requirement)" "$app"; then
    echo "署名を検証できませんでした。次を確かめてください:" >&2
    echo "  - Developer ID Application 証明書(SHA-1 $SIGN_IDENTITY)が秘密鍵ごとキーチェーンにあること" >&2
    echo "  - scripts/release.conf の TEAM_ID($TEAM_ID)が、その証明書のチームのものであること" >&2
    exit 1
  fi
  codesign -d --verbose=2 "$app" 2>&1 | grep -E '^(Authority|TeamIdentifier|Timestamp|CodeDirectory)' || true
  local plist="$app/Contents/Info.plist" short bundle_version
  short="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
  bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
  [ "$short" = "$VERSION" ] && [ "$bundle_version" = "$VERSION" ] \
    || die "Info.plist の版が VERSION と違います(CFBundleShortVersionString=$short, CFBundleVersion=$bundle_version)"
  codesign -d -r- "$app" 2>&1 | grep designated || true

  make_zip "$app"
  echo "完了(未公証。配る前に notarize を実行する):"
  echo "  $app"
  echo "  $ZIP"
}

# designated_requirement … 配布物が満たすべき署名の条件(このチームの Developer ID で、このバンドル ID)
designated_requirement() {
  echo "identifier \"$BUNDLE_ID\" and anchor apple generic and certificate leaf[subject.OU] = \"$TEAM_ID\""
}

make_zip() {
  local app="$1"
  echo "==> zip"
  rm -f "$ZIP" "$ZIP.sha256"
  ditto -c -k --keepParent "$app" "$ZIP"
  (cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
}

cmd_notarize() {
  read_version
  local app="$DIST/$APP_NAME.app"
  [ -d "$app" ] || die "配布物がありません。先に build を実行してください: $app"
  codesign --verify --strict --deep -R="$(designated_requirement)" "$app" \
    || die "署名が Developer ID のものではありません。build からやり直してください"

  local auth_args
  if [ -n "${NOTARY_KEY_PATH:-}" ]; then
    [ -f "$NOTARY_KEY_PATH" ] || die "API キーのファイルがありません: $NOTARY_KEY_PATH"
    auth_args=(--key "$NOTARY_KEY_PATH" --key-id "${NOTARY_KEY_ID:?NOTARY_KEY_ID を指定してください}" \
      --issuer "${NOTARY_ISSUER_ID:?NOTARY_ISSUER_ID を指定してください}")
  else
    auth_args=(--keychain-profile "${NOTARY_KEYCHAIN_PROFILE:-TatakiNote}")
  fi

  echo "==> 公証に出す(数分、初回は数時間かかることがある)"
  local work submission result status id
  work="$(mktemp -d)"
  submission="$work/$APP_NAME.zip"
  [ -n "${NOTARY_SUBMISSION_ID:-}" ] || ditto -c -k --keepParent "$app" "$submission"
  result="$work/result.log"
  local notary_cmd
  if [ -n "${NOTARY_SUBMISSION_ID:-}" ]; then
    echo "提出済みの $NOTARY_SUBMISSION_ID の結果を待つ"
    notary_cmd=(wait "$NOTARY_SUBMISSION_ID")
  else
    notary_cmd=(submit "$submission" --wait)
  fi
  if ! xcrun notarytool "${notary_cmd[@]}" "${auth_args[@]}" 2>&1 | tee "$result"; then
    rm -rf "$work"
    die "公証に出せませんでした(資格情報とネットワークを確かめてください)"
  fi
  status="$(awk '/^ *status:/ { s = $2 } END { print s }' "$result")"
  id="$(awk '/^ *id:/ { i = $2 } END { print i }' "$result")"
  echo "公証の結果: ${status:-不明}(ID ${id:-不明})"
  if [ "$status" != "Accepted" ]; then
    [ -n "$id" ] && xcrun notarytool log "$id" "${auth_args[@]}" >&2 || true
    rm -rf "$work"
    die "公証に通りませんでした"
  fi
  rm -rf "$work"

  echo "==> 公証の結果を .app に付ける"
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose=2 "$app"

  make_zip "$app"
  echo "完了(公証済み):"
  echo "  $app"
  echo "  $ZIP"
}

cmd_upload() {
  read_version
  require_notes
  [ -f "$ZIP" ] && [ -f "$ZIP.sha256" ] || die "配布物がありません。先に build を実行してください: $ZIP"
  xcrun stapler validate -q "$DIST/$APP_NAME.app" \
    || die "配布物が公証されていません。先に notarize を実行してください"
  command -v gh >/dev/null || die "gh がありません"
  local target="${GITHUB_SHA:-$(git -C "$APP_ROOT" rev-parse HEAD)}"
  local state
  state="$(release_state)"
  case "$state" in
    published)
      echo "$TAG は公開済みです。何もしません。"
      ;;
    none)
      echo "==> リリースを公開する: $TAG"
      gh release create "$TAG" --target "$target" --title "$APP_NAME $VERSION" \
        --notes-file "$NOTES" "$ZIP" "$ZIP.sha256"
      ;;
    draft)
      echo "==> 下書きのリリースを更新して公開する: $TAG"
      gh release edit "$TAG" --draft=false --target "$target" --title "$APP_NAME $VERSION" --notes-file "$NOTES"
      gh release upload "$TAG" "$ZIP" "$ZIP.sha256" --clobber
      ;;
  esac
}

[ $# -ge 1 ] || { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
cmd="$1"; shift
case "$cmd" in
  check) cmd_check "$@" ;;
  select-xcode) cmd_select_xcode "$@" ;;
  test) cmd_test "$@" ;;
  build) cmd_build "$@" ;;
  notarize) cmd_notarize "$@" ;;
  upload) cmd_upload "$@" ;;
  *) die "不明なコマンド: $cmd(check / select-xcode / test / build / notarize / upload)" ;;
esac
