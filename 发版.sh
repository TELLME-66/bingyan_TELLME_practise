#!/usr/bin/env bash
#
# 归位 App · 发版与日常维护助手
#
# 把常用的编译、提交、改版本号、发版、回滚都收进一条命令，
# 免得每次都要回忆一长串参数。
#
# 用法：
#   ./发版.sh status              看当前状态（改了哪些文件、和远程差多少）
#   ./发版.sh build               编译（iOS 模拟器版）
#   ./发版.sh run                 编译 + 装到模拟器并启动
#   ./发版.sh save "改了什么"      提交并推送到 GitHub
#   ./发版.sh log                 看最近 10 条提交
#   ./发版.sh ver 1.1 2           把版本号设成 1.1，构建号设成 2
#   ./发版.sh release 1.1.0 "说明" 改版本 + 提交 + 打标签 + 推送
#   ./发版.sh undo                撤销最近一次提交（改动保留，不会丢代码）
#   ./发版.sh tags                看所有版本标签

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$ROOT/GuiWei"
PBX="$PROJ/GuiWei.xcodeproj/project.pbxproj"
BUNDLE_ID="com.tianhaoming.guiwei"
SIM_DEMO="44AC8C7F-EF4D-4A43-B271-3B003DEC8C0F"   # iPhone 17 Pro（带演示数据）
SIM_BLANK="40E477DB-D7C8-4218-97B2-D54C6F30786B"  # iPhone 18 Pro（空数据）

蓝() { printf "\033[1;34m%s\033[0m\n" "$*"; }
绿() { printf "\033[1;32m%s\033[0m\n" "$*"; }
黄() { printf "\033[1;33m%s\033[0m\n" "$*"; }
红() { printf "\033[1;31m%s\033[0m\n" "$*"; }

# ---------------------------------------------------------------- 编译

do_build() {
  蓝 "▶ 正在编译（首次会慢一些，之后有缓存）…"
  cd "$PROJ"
  export CLANG_MODULE_CACHE_PATH="$PROJ/.build/modulecache"
  export SWIFT_MODULECACHE_PATH="$PROJ/.build/modulecache"
  xcodebuild build \
    -project GuiWei.xcodeproj \
    -scheme GuiWei \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$PROJ/.build" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    OTHER_SWIFT_FLAGS="-disable-sandbox" \
    2>&1 | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" | sort -u || true
  cd "$ROOT"
  if [ -d "$PROJ/.build/Build/Products/Debug-iphonesimulator/GuiWei.app" ]; then
    绿 "✔ 编译成功"
  else
    红 "✘ 编译失败，请看上面的 error"
    return 1
  fi
}

do_run() {
  do_build || return 1
  local app="$PROJ/.build/Build/Products/Debug-iphonesimulator/GuiWei.app"
  local sim="${1:-$SIM_DEMO}"
  蓝 "▶ 装到模拟器并启动…"
  xcrun simctl bootstatus "$sim" -b >/dev/null 2>&1 || true
  xcrun simctl terminate "$sim" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$sim" "$app"
  xcrun simctl launch "$sim" "$BUNDLE_ID" -skipOnboarding 1 >/dev/null
  绿 "✔ 已启动（模拟器 $sim）"
}

# ---------------------------------------------------------------- 版本号

do_ver() {
  local version="${1:?用法: ./发版.sh ver 1.1 2}"
  local build="${2:-1}"
  [ -f "$PBX" ] || { 红 "找不到 $PBX"; return 1; }

  # MARKETING_VERSION 与 CURRENT_PROJECT_VERSION 在 App 和扩展两个 target 里
  # 各出现多次，必须全部改掉，否则两边版本不一致。
  /usr/bin/sed -i '' -E \
    -e "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = ${version};/g" \
    -e "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = ${build};/g" \
    "$PBX"

  绿 "✔ 版本号已设为 ${version}（构建号 ${build}）"
  grep -n "MARKETING_VERSION\|CURRENT_PROJECT_VERSION" "$PBX" | sed 's/^/    /'
}

# ---------------------------------------------------------------- 提交

do_save() {
  local msg="${1:?用法: ./发版.sh save \"这次改了什么\"}"
  cd "$ROOT"

  if [ -z "$(git status --porcelain)" ]; then
    黄 "没有需要提交的改动。"
    return 0
  fi

  蓝 "▶ 将要提交这些文件："
  git status --short | sed 's/^/    /'

  # 安全检查：确认安卓版和本地资料没有被误加
  if git status --short | grep -q "安卓\|本地资料"; then
    红 "✘ 检测到安卓版或本地资料，已中止。请检查 .gitignore。"
    return 1
  fi

  git add -A
  git commit -q -m "$msg"
  git push -q origin main
  绿 "✔ 已提交并推送到 GitHub"
  git log --oneline -1 | sed 's/^/    /'
}

do_release() {
  local version="${1:?用法: ./发版.sh release 1.1.0 \"说明\"}"
  local msg="${2:-发布 $version}"
  do_ver "$version" "${BUILD_NUM:-1}"
  do_build || { 红 "✘ 编译没过，先别发版"; return 1; }
  do_save "$msg"
  git tag -a "v$version" -m "$msg"
  git push -q origin "v$version"
  绿 "✔ 已发布 v$version"
}

# ---------------------------------------------------------------- 查看与回滚

do_status() {
  cd "$ROOT"
  蓝 "▶ 当前分支与远程差距："
  git status -sb | head -1 | sed 's/^/    /'
  蓝 "▶ 改动的文件："
  if [ -z "$(git status --porcelain)" ]; then
    echo "    （工作区干净，没有未提交的改动）"
  else
    git status --short | sed 's/^/    /'
  fi
  蓝 "▶ 当前版本号："
  grep -m1 "MARKETING_VERSION" "$PBX" | sed 's/^/    /' || true
  蓝 "▶ 最近 3 条提交："
  git log --oneline -3 | sed 's/^/    /'
}

do_log() {
  cd "$ROOT"
  git log --oneline -10 | sed 's/^/  /'
}

do_undo() {
  cd "$ROOT"
  黄 "▶ 即将撤销最近一次提交（代码改动会保留在文件里，不会丢）"
  git log --oneline -1 | sed 's/^/    /'
  read -r -p "确认？(y/N) " ans
  [ "$ans" = "y" ] || { echo "已取消"; return 0; }
  git reset --soft HEAD~1
  绿 "✔ 已撤销提交，改动还在，可以继续修改后重新提交"
  git status --short | sed 's/^/    /'
}

# ---------------------------------------------------------------- 入口

case "${1:-}" in
  build)   do_build ;;
  run)     do_run "${2:-}" ;;
  ver)     do_ver "${2:-}" "${3:-1}" ;;
  save)    do_save "${2:-}" ;;
  release) do_release "${2:-}" "${3:-}" ;;
  status)  do_status ;;
  log)     do_log ;;
  tags)    git tag -l | sed 's/^/  /' ;;
  undo)    do_undo ;;
  *)
    cat <<'USAGE'
归位 App · 发版与日常维护助手

  ./发版.sh status                看当前状态
  ./发版.sh build                 编译
  ./发版.sh run [模拟器UDID]       编译并装到模拟器启动
  ./发版.sh save "改了什么"        提交并推送到 GitHub
  ./发版.sh log                   看最近 10 条提交
  ./发版.sh ver 1.1 2             设置版本号 1.1 / 构建号 2
  ./发版.sh release 1.1.0 "说明"   改版本 + 编译 + 提交 + 打标签 + 推送
  ./发版.sh tags                  看所有版本标签
  ./发版.sh undo                  撤销最近一次提交（保留改动）
USAGE
    ;;
esac
