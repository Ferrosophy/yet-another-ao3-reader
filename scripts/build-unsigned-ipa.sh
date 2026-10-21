#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# 建置未簽名的 IPA（簽名由使用者自行處理）。
# 用法：scripts/build-unsigned-ipa.sh <版本號> <建置號>
# 產物：build/YAAO3R-<版本號>-unsigned.ipa（版本號最後一位代表第幾次修改；建置號只寫入 CFBundleVersion）
set -euo pipefail

VERSION="${1:?需要版本號，例如 0.1.0}"
BUILD_NUMBER="${2:?需要建置號，例如 1}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/AO3Reader.xcarchive"
IPA_NAME="YAAO3R-${VERSION}-unsigned.ipa"

cd "$ROOT"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodegen generate

xcodebuild archive \
  -project AO3Reader.xcodeproj \
  -scheme AO3Reader \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  | tee "$BUILD_DIR/xcodebuild.log" \
  | xcbeautify --renderer github-actions

APP="$ARCHIVE/Products/Applications/AO3Reader.app"
test -d "$APP" || { echo "找不到 $APP"; exit 1; }

# IPA = Payload/<App>.app 的 zip
STAGING="$BUILD_DIR/ipa"
mkdir -p "$STAGING/Payload"
cp -R "$APP" "$STAGING/Payload/"
(cd "$STAGING" && zip -qry "$BUILD_DIR/$IPA_NAME" Payload)

# 確認寫入的版本號
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Info.plist"

echo "IPA_PATH=$BUILD_DIR/$IPA_NAME"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "ipa_path=$BUILD_DIR/$IPA_NAME" >> "$GITHUB_OUTPUT"
  echo "ipa_name=$IPA_NAME" >> "$GITHUB_OUTPUT"
fi
