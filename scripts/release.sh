#!/bin/bash
# TatakiNote の配布物を作り、GitHub Releases に公開する。
# 使い方: ./scripts/release.sh <コマンド> [オプション]
#   check            VERSION の版をリリースするかを判定する(release=yes / release=no を出力。
#                    GitHub Actions では GITHUB_OUTPUT にも書く)。公開済みなら no、未作成か下書きなら yes
#   select-xcode     CI 用。/Applications/Xcode_<XCODE_MAJOR>*.app の一番新しいもの(無ければ、ある中で一番新しい Xcode)を選ぶ(sudo を使う)
#   test             単体テスト(TatakiNoteTests)を署名なしで流す
#   build [--keychain <キーチェーン>]
#                    Release ビルド → Developer ID で署名(hardened runtime・時刻印)→ 検証 → dist/ に
#                    TatakiNote.app と TatakiNote-<版>.dmg(署名済み・未公証)を作る。キーチェーン省略時は既定の検索リスト。
#                    時刻印に Apple のサーバーへの接続が要る
#   notarize         dist/ の .app を Apple の公証に出して結果を .app に付け(staple)、DMG を作り直して署名し、
#                    DMG も公証に出して結果を付ける。
#                    資格情報は NOTARY_KEY_PATH・NOTARY_KEY_ID・NOTARY_ISSUER_ID(App Store Connect API キー)、
#                    無ければキーチェーンのプロファイル NOTARY_KEYCHAIN_PROFILE(既定 TatakiNote)。
#                    NOTARY_SUBMISSION_ID を付けると、.app は出し直さずにその提出の結果を待つ(同じ .app のときだけ)
#   appcast [--dry-run]
#                    dist/ の DMG に EdDSA の署名をして dist/appcast.xml を作る。秘密鍵は SPARKLE_ED_PRIVATE_KEY、
#                    無ければキーチェーン。--dry-run は署名せず、appcast.xml を書かずに標準出力へ出す
#   upload           dist/ の DMG と appcast.xml、release-notes/v<版>.md で、GitHub にリリースを公開する
#                    (下書きがあれば本文と添付を差し替えて公開し、公開済みなら何もしない)。gh が要る
# 版は VERSION(x.y.z)、リリースノートは release-notes/v<版>.md、設定は scripts/release.conf。
set -euo pipefail
export GIT_PAGER=cat

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=release.conf
. "$APP_ROOT/scripts/release.conf"

DIST="$APP_ROOT/dist"
DERIVED="$APP_ROOT/.build/release"
DMGBUILD_VERSION=1.6.5
MINIMUM_SYSTEM_VERSION=14.0

die() { echo "エラー: $*" >&2; exit 1; }

read_version() {
  [ -f "$APP_ROOT/VERSION" ] || die "VERSION がありません: $APP_ROOT/VERSION"
  VERSION="$(tr -d '[:space:]' < "$APP_ROOT/VERSION")"
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION は x.y.z の形にしてください: '$VERSION'"
  TAG="v$VERSION"
  NOTES="$APP_ROOT/release-notes/$TAG.md"
  DMG="$DIST/$APP_NAME-$VERSION.dmg"
  APPCAST="$DIST/appcast.xml"
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
  # 中に入っているコード(あれば)を内側から先に、最後に .app 本体を署名する
  # (Sparkle の Updater.app と Autoupdate、XPC サービスを含む)
  local item extra_args
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    extra_args=()
    case "$item" in
      *.xpc) extra_args=(--preserve-metadata=entitlements) ;;
    esac
    codesign "${sign_args[@]}" ${extra_args[@]+"${extra_args[@]}"} "$item"
  done <<EOF
$(find "$app/Contents" -depth \( \
    -name '*.framework' -o -name '*.dylib' -o -name '*.appex' -o -name '*.xpc' \
    -o \( -name '*.app' -path '*/Contents/Frameworks/*' \) \
    -o \( -type f -name Autoupdate -path '*/Sparkle.framework/Versions/*/Autoupdate' \) \
  \) 2>/dev/null)
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

  make_dmg "$app" ${kc_args[@]+"${kc_args[@]}"}
  echo "完了(未公証。配る前に notarize を実行する):"
  echo "  $app"
  echo "  $DMG"
}

# designated_requirement … 配布物が満たすべき署名の条件(このチームの Developer ID で、このバンドル ID)
designated_requirement() {
  echo "identifier \"$BUNDLE_ID\" and anchor apple generic and certificate leaf[subject.OU] = \"$TEAM_ID\""
}

# make_dmg <.app> [codesign に渡す引数…] … dist/ に署名した DMG を作る(公証はしない)
make_dmg() {
  local app="$1"
  shift
  local volume_icon="$APP_ROOT/icon/VolumeIcon.icns"
  [ -s "$volume_icon" ] || die "icon/VolumeIcon.icns がありません"
  command -v python3 >/dev/null || die "python3 がありません"

  local venv="$APP_ROOT/.build/dmgbuild-venv"
  if [ ! -x "$venv/bin/dmgbuild" ]; then
    echo "==> dmgbuild $DMGBUILD_VERSION を用意する"
    python3 -m venv "$venv"
    "$venv/bin/pip" install --quiet "dmgbuild==$DMGBUILD_VERSION"
  fi

  echo "==> DMG"
  local background_dir="$APP_ROOT/.build/dmg"
  rm -rf "$background_dir"
  mkdir -p "$background_dir"
  swift "$APP_ROOT/icon/render-dmg-background.swift" "$background_dir"
  tiffutil -cathidpicheck "$background_dir/background.png" "$background_dir/background@2x.png" \
    -out "$background_dir/background.tiff"

  rm -f "$DMG"
  "$venv/bin/dmgbuild" \
    -s "$APP_ROOT/scripts/dmg-settings.py" \
    -D app_path="$app" \
    -D background="$background_dir/background.tiff" \
    -D volume_icon="$volume_icon" \
    "$APP_NAME" "$DMG"
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$@" "$DMG"
  codesign --verify --strict "$DMG"
}

# notary_submit <ファイル> [提出済みの ID] … 公証に出して結果を待つ。通らなければエラーで止まる
notary_submit() {
  local file="$1" resume_id="${2:-}"
  local work result status id notary_cmd
  work="$(mktemp -d)"
  result="$work/result.log"
  if [ -n "$resume_id" ]; then
    echo "提出済みの $resume_id の結果を待つ"
    notary_cmd=(wait "$resume_id")
  else
    notary_cmd=(submit "$file" --wait)
  fi
  if ! xcrun notarytool "${notary_cmd[@]}" "${AUTH_ARGS[@]}" 2>&1 | tee "$result"; then
    rm -rf "$work"
    die "公証に出せませんでした(資格情報とネットワークを確かめてください)"
  fi
  status="$(awk '/^ *status:/ { s = $2 } END { print s }' "$result")"
  id="$(awk '/^ *id:/ { i = $2 } END { print i }' "$result")"
  echo "公証の結果: ${status:-不明}(ID ${id:-不明})"
  if [ "$status" != "Accepted" ]; then
    [ -n "$id" ] && xcrun notarytool log "$id" "${AUTH_ARGS[@]}" >&2 || true
    rm -rf "$work"
    die "公証に通りませんでした"
  fi
  rm -rf "$work"
}

cmd_notarize() {
  read_version
  local app="$DIST/$APP_NAME.app"
  [ -d "$app" ] || die "配布物がありません。先に build を実行してください: $app"
  codesign --verify --strict --deep -R="$(designated_requirement)" "$app" \
    || die "署名が Developer ID のものではありません。build からやり直してください"

  if [ -n "${NOTARY_KEY_PATH:-}" ]; then
    [ -f "$NOTARY_KEY_PATH" ] || die "API キーのファイルがありません: $NOTARY_KEY_PATH"
    AUTH_ARGS=(--key "$NOTARY_KEY_PATH" --key-id "${NOTARY_KEY_ID:?NOTARY_KEY_ID を指定してください}" \
      --issuer "${NOTARY_ISSUER_ID:?NOTARY_ISSUER_ID を指定してください}")
  else
    AUTH_ARGS=(--keychain-profile "${NOTARY_KEYCHAIN_PROFILE:-TatakiNote}")
  fi

  echo "==> .app を公証に出す(数分、初回は数時間かかることがある)"
  local work
  work="$(mktemp -d)"
  if [ -z "${NOTARY_SUBMISSION_ID:-}" ]; then
    ditto -c -k --keepParent "$app" "$work/$APP_NAME.zip"
  fi
  notary_submit "$work/$APP_NAME.zip" "${NOTARY_SUBMISSION_ID:-}"
  rm -rf "$work"

  echo "==> 公証の結果を .app に付ける"
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose=2 "$app"

  make_dmg "$app"

  echo "==> DMG を公証に出す"
  notary_submit "$DMG"
  echo "==> 公証の結果を DMG に付ける"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

  echo "完了(公証済み):"
  echo "  $app"
  echo "  $DMG"
}

# notes_to_html … リリースノート(Markdown の見出しと箇条書きだけ)を HTML にして標準出力へ
notes_to_html() {
  awk '
    function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); return s }
    function close_list() { if (in_list) { print "</ul>"; in_list = 0 } }
    /^[[:space:]]*$/ { close_list(); next }
    /^## / { close_list(); print "<h3>" esc(substr($0, 4)) "</h3>"; next }
    /^- / {
      if (!in_list) { print "<ul>"; in_list = 1 }
      print "<li>" esc(substr($0, 3)) "</li>"
      next
    }
    { close_list(); print "<p>" esc($0) "</p>" }
    END { close_list() }
  ' "$NOTES"
}

# sign_dmg … DMG の EdDSA 署名(base64)を標準出力へ
sign_dmg() {
  local tool out signature
  tool="$(find "$DERIVED/SourcePackages/artifacts" -type f -name sign_update 2>/dev/null | head -1 || true)"
  [ -n "$tool" ] || die "sign_update がありません。Sparkle のパッケージを取得して build を実行してください: $DERIVED/SourcePackages/artifacts"
  if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
    out="$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$tool" "$DMG" --ed-key-file -)" \
      || die "DMG に署名できませんでした(SPARKLE_ED_PRIVATE_KEY を確かめてください)"
  else
    out="$("$tool" "$DMG")" \
      || die "DMG に署名できませんでした(キーチェーンに EdDSA の秘密鍵が必要です)"
  fi
  signature="$(printf '%s\n' "$out" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$signature" ] || die "sign_update の出力から署名を読めませんでした: $out"
  printf '%s\n' "$signature"
}

cmd_appcast() {
  local dry_run=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry_run=1; shift ;;
      *) die "不明な引数: $1" ;;
    esac
  done
  read_version
  require_notes

  local length=0 signature_attribute=""
  if [ -f "$DMG" ]; then
    length="$(stat -f%z "$DMG")"
  elif [ "$dry_run" -eq 0 ]; then
    die "配布物がありません。先に build を実行してください: $DMG"
  fi
  if [ "$dry_run" -eq 0 ]; then
    local signature
    signature="$(sign_dmg)"
    signature_attribute=" sparkle:edSignature=\"$signature\""
  fi

  local repo="${GH_REPO:-tk-niway/tataki-note}"
  local url="https://github.com/$repo/releases/download/$TAG/$(basename "$DMG")"
  local pub_date description
  pub_date="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
  description="$(notes_to_html)"
  if [ "$dry_run" -eq 1 ]; then
    write_appcast
  else
    mkdir -p "$DIST"
    write_appcast > "$APPCAST"
    echo "appcast.xml を作りました: $APPCAST"
  fi
}

# write_appcast … cmd_appcast の変数(url・length・pub_date・description など)で appcast.xml を標準出力へ
write_appcast() {
  cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$APP_NAME</title>
    <item>
      <title>$VERSION</title>
      <pubDate>$pub_date</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM_SYSTEM_VERSION</sparkle:minimumSystemVersion>
      <description><![CDATA[
$description
]]></description>
      <enclosure url="$url" length="$length" type="application/octet-stream"$signature_attribute/>
    </item>
  </channel>
</rss>
EOF
}

# remove_stale_assets … 下書きのリリースの添付から、DMG と appcast.xml 以外を消す
remove_stale_assets() {
  local name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    case "$name" in
      "$(basename "$DMG")"|"$(basename "$APPCAST")") ;;
      *) gh release delete-asset "$TAG" "$name" -y ;;
    esac
  done <<EOF
$(gh release view "$TAG" --json assets --jq '.assets[].name')
EOF
}

cmd_upload() {
  read_version
  require_notes
  [ -f "$DMG" ] || die "配布物がありません。先に build を実行してください: $DMG"
  xcrun stapler validate -q "$DMG" \
    || die "配布物が公証されていません。先に notarize を実行してください"
  command -v gh >/dev/null || die "gh がありません"
  local target="${GITHUB_SHA:-$(git -C "$APP_ROOT" rev-parse HEAD)}"
  local state
  state="$(release_state)"
  if [ "$state" = published ]; then
    echo "$TAG は公開済みです。何もしません。"
    return 0
  fi
  cmd_appcast
  case "$state" in
    none)
      echo "==> リリースを作る(下書き): $TAG"
      gh release create "$TAG" --draft --target "$target" --title "$APP_NAME $VERSION" \
        --notes-file "$NOTES" "$DMG" "$APPCAST"
      ;;
    draft)
      echo "==> 下書きのリリースを更新する: $TAG"
      gh release edit "$TAG" --target "$target" --title "$APP_NAME $VERSION" --notes-file "$NOTES"
      remove_stale_assets
      gh release upload "$TAG" "$DMG" "$APPCAST" --clobber
      ;;
  esac
  echo "==> 添付がそろったので公開する: $TAG"
  gh release edit "$TAG" --draft=false
}

[ $# -ge 1 ] || { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
cmd="$1"; shift
case "$cmd" in
  check) cmd_check "$@" ;;
  select-xcode) cmd_select_xcode "$@" ;;
  test) cmd_test "$@" ;;
  build) cmd_build "$@" ;;
  notarize) cmd_notarize "$@" ;;
  appcast) cmd_appcast "$@" ;;
  upload) cmd_upload "$@" ;;
  *) die "不明なコマンド: $cmd(check / select-xcode / test / build / notarize / appcast / upload)" ;;
esac
