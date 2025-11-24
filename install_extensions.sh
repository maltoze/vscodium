#!/usr/bin/env bash

set -e

OPEN_VSX_API="https://open-vsx.org/api"
TMP_DIR="${TMPDIR:-/tmp}"

# Extension list: ID|PUBLISHER|NAME|VERSION|PLATFORM_SPECIFIC (1=yes, 0=no)
EXTENSIONS=(
  "Anthropic.claude-code|Anthropic|claude-code|2.0.37|1"
  "MS-CEINTL.vscode-language-pack-zh-hans|MS-CEINTL|vscode-language-pack-zh-hans|1.106.0|0"
)

echo "Installing extensions to VSCodium application..."

# Determine the app path based on platform
if [[ -d "VSCode-darwin-arm64" ]]; then
  APP_PATH="VSCode-darwin-arm64/DeployAI Studio.app/Contents/Resources/app"
elif [[ -d "VSCode-darwin-x64" ]]; then
  APP_PATH="VSCode-darwin-x64/DeployAI Studio.app/Contents/Resources/app"
elif [[ -d "VSCode-linux-x64" ]]; then
  APP_PATH="VSCode-linux-x64/resources/app"
elif [[ -d "VSCode-linux-arm64" ]]; then
  APP_PATH="VSCode-linux-arm64/resources/app"
elif [[ -d "VSCode-win32-x64" ]]; then
  APP_PATH="VSCode-win32-x64/resources/app"
elif [[ -d "VSCode-win32-arm64" ]]; then
  APP_PATH="VSCode-win32-arm64/resources/app"
else
  echo "Could not find compiled VSCode directory"
  exit 0
fi

EXTENSIONS_DIR="${APP_PATH}/extensions"

# Create extensions directory if it doesn't exist
mkdir -p "${EXTENSIONS_DIR}"

# Function to install a single extension
install_extension() {
  local EXTENSION_ID="$1"
  local PUBLISHER="$2"
  local EXTENSION_NAME="$3"
  local EXTENSION_VERSION="$4"
  local PLATFORM_SPECIFIC="$5"
  local VSIX_FILE="${TMP_DIR}/${EXTENSION_NAME}-$$.vsix"

  echo ""
  echo "Installing ${EXTENSION_ID}..."

  # Download URL - different format for platform-specific vs universal extensions
  if [[ "$PLATFORM_SPECIFIC" == "1" ]]; then
    DOWNLOAD_URL="${OPEN_VSX_API}/${PUBLISHER}/${EXTENSION_NAME}/${PLATFORM}/${EXTENSION_VERSION}/file/${PUBLISHER}.${EXTENSION_NAME}-${EXTENSION_VERSION}@${PLATFORM}.vsix"
  else
    DOWNLOAD_URL="${OPEN_VSX_API}/${PUBLISHER}/${EXTENSION_NAME}/${EXTENSION_VERSION}/file/${PUBLISHER}.${EXTENSION_NAME}-${EXTENSION_VERSION}.vsix"
  fi

  echo "  Downloading from: ${DOWNLOAD_URL}"

  if ! curl -L -f -o "${VSIX_FILE}" "${DOWNLOAD_URL}"; then
    echo "  Warning: Failed to download ${EXTENSION_ID}"
    rm -f "${VSIX_FILE}"
    return 1
  fi

  # Extract the VSIX file
  EXT_DIR="${EXTENSIONS_DIR}/${EXTENSION_ID}"
  mkdir -p "${EXT_DIR}"

  # Create a temporary directory to extract VSIX
  TMP_EXTRACT_DIR="${TMP_DIR}/vsix-extract-${EXTENSION_NAME}-$$"
  mkdir -p "${TMP_EXTRACT_DIR}"

  # On macOS, unzip is available; on Linux and Windows, we should also have it
  if command -v unzip &> /dev/null; then
    unzip -q "${VSIX_FILE}" -d "${TMP_EXTRACT_DIR}"

    # Move the extension directory contents directly to EXT_DIR
    if [[ -d "${TMP_EXTRACT_DIR}/extension" ]]; then
      cp -r "${TMP_EXTRACT_DIR}/extension"/* "${EXT_DIR}/" 2>/dev/null || true
    fi

    # Also copy the manifest and other VSIX files
    cp -r "${TMP_EXTRACT_DIR}"/* "${EXT_DIR}/" 2>/dev/null || true

    # Clean up temp directory
    rm -rf "${TMP_EXTRACT_DIR}"
  else
    echo "  Error: unzip command not found" >&2
    rm -f "${VSIX_FILE}"
    return 1
  fi

  rm -f "${VSIX_FILE}"

  echo "  ${EXTENSION_ID} installed successfully"

  # Inject custom translations if this is the Chinese language pack
  if [[ "$EXTENSION_ID" == "MS-CEINTL.vscode-language-pack-zh-hans" ]]; then
    inject_chinese_translations "${EXT_DIR}"
  fi

  return 0
}

# Function to inject custom Chinese translations
inject_chinese_translations() {
  local LANG_PACK_DIR="$1"
  local TRANSLATIONS_FILE="${LANG_PACK_DIR}/translations/main.i18n.json"

  if [[ ! -f "$TRANSLATIONS_FILE" ]]; then
    echo "  Warning: Translation file not found at $TRANSLATIONS_FILE"
    return 1
  fi

  echo "  Injecting custom translations..."

  # Use jq if available, otherwise use python
  if command -v jq &> /dev/null; then
    # Create temporary file with custom translations
    local TEMP_FILE="${TMP_DIR}/custom_translations_$$.json"
    cat > "$TEMP_FILE" << 'EOF'
{
  "viewBalance": "查看余额",
  "lowBalance": "余额不足，请充值",
  "myAccount": "我的账户",
  "login": "登录",
  "logout": "退出登录",
  "toggleLanguage": "切换语言",
  "launchClaudeCode": "启动 Claude Code",
  "loading": "加载中...",
  "notLoggedIn": "未登录",
  "clickToLogin": "(点击登录)",
  "loggedIn": "已登录",
  "insufficientBalance": "余额不足，请充值",
  "insufficientBalanceDetail": "您的账户余额不足，点击确定前往充值页面。",
  "ok": "确定",
  "cancel": "取消"
}
EOF

    # Merge translations into multiple sections
    jq --slurpfile custom "$TEMP_FILE" \
       '.contents["vs/workbench/browser/parts/titlebar/titlebarActions"] += $custom[0] |
        .contents["vs/workbench/contrib/startupSplash/browser/startupSplash"] += $custom[0]' \
       "$TRANSLATIONS_FILE" > "${TRANSLATIONS_FILE}.tmp" && \
    mv "${TRANSLATIONS_FILE}.tmp" "$TRANSLATIONS_FILE"

    rm -f "$TEMP_FILE"
    echo "  ✓ Custom translations injected successfully"
  else
    # Fallback to python if jq is not available
    python3 << 'PYEOF'
import json
import sys

translations_file = sys.argv[1]

try:
    with open(translations_file, 'r', encoding='utf-8') as f:
        data = json.load(f)

    if 'contents' not in data:
        data['contents'] = {}

    custom_translations = {
        "viewBalance": "查看余额",
        "lowBalance": "余额不足，请充值",
        "myAccount": "我的账户",
        "login": "登录",
        "logout": "退出登录",
        "toggleLanguage": "切换语言",
        "launchClaudeCode": "启动 Claude Code",
        "loading": "加载中...",
        "notLoggedIn": "未登录",
        "clickToLogin": "(点击登录)",
        "loggedIn": "已登录",
        "insufficientBalance": "余额不足，请充值",
        "insufficientBalanceDetail": "您的账户余额不足，点击确定前往充值页面。",
        "ok": "确定",
        "cancel": "取消"
    }

    # Inject into titlebar actions
    titlebar_key = 'vs/workbench/browser/parts/titlebar/titlebarActions'
    if titlebar_key not in data['contents']:
        data['contents'][titlebar_key] = {}
    data['contents'][titlebar_key].update(custom_translations)

    # Inject into startup splash
    splash_key = 'vs/workbench/contrib/startupSplash/browser/startupSplash'
    if splash_key not in data['contents']:
        data['contents'][splash_key] = {}
    data['contents'][splash_key].update(custom_translations)

    with open(translations_file, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=8)

    print("  ✓ Custom translations injected successfully")
except Exception as e:
    print(f"  Error injecting translations: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

    if ! python3 -c "$(cat << 'PYSCRIPT'
import json
import sys

translations_file = sys.argv[1]

try:
    with open(translations_file, 'r', encoding='utf-8') as f:
        data = json.load(f)

    if 'contents' not in data:
        data['contents'] = {}

    custom_translations = {
        "viewBalance": "查看余额",
        "lowBalance": "余额不足，请充值",
        "myAccount": "我的账户",
        "login": "登录",
        "logout": "退出登录",
        "toggleLanguage": "切换语言",
        "launchClaudeCode": "启动 Claude Code",
        "loading": "加载中...",
        "notLoggedIn": "未登录",
        "clickToLogin": "(点击登录)",
        "loggedIn": "已登录",
        "insufficientBalance": "余额不足，请充值",
        "insufficientBalanceDetail": "您的账户余额不足，点击确定前往充值页面。",
        "ok": "确定",
        "cancel": "取消"
    }

    # Inject into titlebar actions
    titlebar_key = 'vs/workbench/browser/parts/titlebar/titlebarActions'
    if titlebar_key not in data['contents']:
        data['contents'][titlebar_key] = {}
    data['contents'][titlebar_key].update(custom_translations)

    # Inject into startup splash
    splash_key = 'vs/workbench/contrib/startupSplash/browser/startupSplash'
    if splash_key not in data['contents']:
        data['contents'][splash_key] = {}
    data['contents'][splash_key].update(custom_translations)

    with open(translations_file, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=8)

    print("  ✓ Custom translations injected successfully")
except Exception as e:
    print(f"  Error injecting translations: {e}", file=sys.stderr)
    sys.exit(1)
PYSCRIPT
)" "$TRANSLATIONS_FILE"; then
      echo "  Warning: Failed to inject translations"
      return 1
    fi
  fi

  return 0
}

# Determine platform for download
PLATFORM="linux-x64"
if [[ "$OSTYPE" == "darwin"* ]]; then
  PLATFORM="darwin-arm64"
  if [[ $(uname -m) == "x86_64" ]]; then
    PLATFORM="darwin-x64"
  fi
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
  PLATFORM="win32-x64"
  if [[ $(uname -m) == "arm64" ]]; then
    PLATFORM="win32-arm64"
  fi
elif [[ $(uname -m) == "arm64" ]]; then
  PLATFORM="linux-arm64"
fi

echo "Platform: ${PLATFORM}"
echo "App path: ${APP_PATH}"
echo "Extensions dir: ${EXTENSIONS_DIR}"

# Install all extensions
INSTALLED_COUNT=0
FAILED_COUNT=0

for EXTENSION_INFO in "${EXTENSIONS[@]}"; do
  IFS='|' read -r EXTENSION_ID PUBLISHER EXTENSION_NAME EXTENSION_VERSION PLATFORM_SPECIFIC <<< "$EXTENSION_INFO"

  if install_extension "$EXTENSION_ID" "$PUBLISHER" "$EXTENSION_NAME" "$EXTENSION_VERSION" "$PLATFORM_SPECIFIC"; then
    ((INSTALLED_COUNT++))
  else
    ((FAILED_COUNT++))
  fi
done

echo ""
echo "=========================================="
echo "Installation Summary:"
echo "  Successfully installed: ${INSTALLED_COUNT}"
echo "  Failed: ${FAILED_COUNT}"
echo "=========================================="

if [[ $INSTALLED_COUNT -gt 0 ]]; then
  echo ""
  echo "Installed extensions:"
  ls -lh "${EXTENSIONS_DIR}/"
fi
