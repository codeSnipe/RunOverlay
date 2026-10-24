#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

command -v xcodebuild >/dev/null
command -v jq >/dev/null
command -v pkgbuild >/dev/null

configuration="${PACKAGE_CONFIGURATION:-Release}"
if [[ "$configuration" != "Debug" && "$configuration" != "Release" ]]; then
    printf '不支持的构建配置：%s（仅支持 Debug 或 Release）\n' "$configuration" >&2
    exit 1
fi

base_version="$(
    xcodebuild -project RunOverlay.xcodeproj -scheme RunOverlay \
        -configuration "$configuration" -showBuildSettings -json |
        jq -r '.[] | select(.target == "RunOverlay") | .buildSettings.MARKETING_VERSION'
)"
if [[ ! "$base_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '无效的应用基础版本号：%s\n' "$base_version" >&2
    exit 1
fi

highest_sequence=0
for existing in \
    "$project_dir"/RunOverlay-"$base_version"-[0-9][0-9][0-9].pkg \
    "$project_dir"/RunOverlay-"$base_version"-[0-9][0-9][0-9]-Debug.pkg; do
    [[ -f "$existing" ]] || continue
    file_name="${existing##*/}"
    sequence="${file_name#RunOverlay-$base_version-}"
    sequence="${sequence%-Debug.pkg}"
    sequence="${sequence%.pkg}"
    if (( 10#$sequence > highest_sequence )); then
        highest_sequence=$((10#$sequence))
    fi
done

# 安装包被移走时，仍以最近构建的应用版本继续递增。
for built_app in \
    "$project_dir"/.build/PackageDerivedData/Build/Products/{Debug,Release}/RunOverlay.app \
    "$project_dir"/.build/CardPropertiesDerivedData/Build/Products/Debug/RunOverlay.app; do
    info_plist="$built_app/Contents/Info.plist"
    [[ -f "$info_plist" ]] || continue
    built_base="$(plutil -extract CFBundleShortVersionString raw -o - "$info_plist")"
    built_number="$(plutil -extract CFBundleVersion raw -o - "$info_plist")"
    if [[ "$built_base" == "$base_version" && "$built_number" =~ ^[0-9]{1,3}$ ]] &&
       (( 10#$built_number > highest_sequence )); then
        highest_sequence=$((10#$built_number))
    fi
done

next_sequence=$((highest_sequence + 1))
if (( next_sequence > 999 )); then
    printf '构建号已达到 999，请先更新项目基础版本号。\n' >&2
    exit 1
fi
build_number="$(printf '%03d' "$next_sequence")"
display_version="$base_version-$build_number"
package_suffix=""
if [[ "$configuration" == "Debug" ]]; then
    package_suffix="-Debug"
fi
package_path="$project_dir/RunOverlay-$display_version$package_suffix.pkg"
if [[ -e "$package_path" ]]; then
    printf '安装包已存在，未覆盖：%s\n' "$package_path" >&2
    exit 1
fi

derived_data="$project_dir/.build/PackageDerivedData"
xcodebuild -project RunOverlay.xcodeproj -scheme RunOverlay \
    -configuration "$configuration" -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived_data" \
    CURRENT_PROJECT_VERSION="$build_number" build -quiet

application="$derived_data/Build/Products/$configuration/RunOverlay.app"
info_plist="$application/Contents/Info.plist"
actual_base="$(plutil -extract CFBundleShortVersionString raw -o - "$info_plist")"
actual_build="$(plutil -extract CFBundleVersion raw -o - "$info_plist")"
actual_display="$(plutil -extract RunOverlayDisplayVersion raw -o - "$info_plist")"
if [[ "$actual_base" != "$base_version" ||
      "$actual_build" != "$build_number" ||
      "$actual_display" != "$display_version" ]]; then
    printf '应用版本信息不一致：%s / %s / %s\n' \
        "$actual_base" "$actual_build" "$actual_display" >&2
    exit 1
fi

codesign --verify --deep --strict "$application"
COPYFILE_DISABLE=1 pkgbuild --component "$application" \
    --install-location /Applications \
    --identifier com.runoverlay.app.pkg \
    --version "$base_version.$build_number" \
    "$package_path"
printf '已生成 %s（%s 构建，应用版本 %s，安装包版本 %s.%s）\n' \
    "$package_path" "$configuration" "$actual_display" "$base_version" "$build_number"
