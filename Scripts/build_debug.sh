#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="$project_dir/.build/SmartEditDerivedData"
legacy_derived_data="$project_dir/.build/SmartEditDerived"
application="$derived_data/Build/Products/Debug/RunOverlay.app"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

cd "$project_dir"
xcodebuild -project RunOverlay.xcodeproj -scheme RunOverlay \
    -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" CODE_SIGNING_ALLOWED=NO build

if [[ ! -f "$application/Contents/MacOS/RunOverlay" ]]; then
    printf 'Debug 应用不存在，未清理构建缓存：%s\n' "$application" >&2
    exit 1
fi

# 仅清理此项目已确认的 Xcode 临时缓存；保留 Build/Products 中可直接启动的 App。
for cache in \
    "$derived_data/Build/Intermediates.noindex" \
    "$derived_data/CompilationCache.noindex" \
    "$derived_data/Index.noindex" \
    "$derived_data/Logs" \
    "$derived_data/ModuleCache.noindex" \
    "$derived_data/SDKStatCaches.noindex" \
    "$project_dir/.build/arm64-apple-macosx" \
    "$project_dir/.build/out" \
    "$legacy_derived_data"; do
    [[ -d "$cache" ]] || continue
    rm -r -- "$cache"
done

printf 'Debug 构建成功，旧构建缓存已清理；可打开：%s\n' "$application"
