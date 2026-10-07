#!/usr/bin/env bash
set -euo pipefail

HARMONY_PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HARMONY_PROJECT_DIR"

if [[ -n "${HVIGORW:-}" ]]; then
  HARMONY_HVIGOR_BIN="$HVIGORW"
elif command -v hvigorw >/dev/null 2>&1; then
  HARMONY_HVIGOR_BIN="$(command -v hvigorw)"
elif [[ -n "${DEVECO_COMMANDLINE_HOME:-}" && -x "$DEVECO_COMMANDLINE_HOME/bin/hvigorw" ]]; then
  HARMONY_HVIGOR_BIN="$DEVECO_COMMANDLINE_HOME/bin/hvigorw"
else
  echo '缺少 hvigorw：请安装华为官方 HarmonyOS 26.0.0 Command Line Tools，或在 DevEco Studio 26.0.0 中构建。' >&2
  exit 2
fi

if [[ ! -x "$HARMONY_HVIGOR_BIN" ]]; then
  echo 'HVIGORW 必须指向可执行的官方 hvigorw。' >&2
  exit 2
fi
if [[ -z "${DEVECO_SDK_HOME:-}" && ! -f local.properties ]]; then
  echo '缺少 SDK 路径：请设置 DEVECO_SDK_HOME 指向官方工具的 sdk 目录，或用 DevEco Studio 配置 local.properties。' >&2
  exit 2
fi

node tools/check-project.mjs
node --test tests/*.test.mjs
"$HARMONY_HVIGOR_BIN" --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon
echo '构建输出位于 entry/build/default/outputs/default/；未配置签名时产物不能用于真机安装。'
