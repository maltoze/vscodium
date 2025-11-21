#!/usr/bin/env bash

set -e

EXTENSION_ID="Anthropic.claude-code"
PUBLISHER="Anthropic"
EXTENSION_NAME="claude-code"
EXTENSION_VERSION="2.0.37"
OPEN_VSX_API="https://open-vsx.org/api"
TMP_DIR="${TMPDIR:-/tmp}"
VSIX_FILE="${TMP_DIR}/claude-code-$$.vsix"

echo "Installing Claude Code extension to VSCodium application..."

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

# Download URL for the specific platform
DOWNLOAD_URL="${OPEN_VSX_API}/${PUBLISHER}/${EXTENSION_NAME}/${PLATFORM}/${EXTENSION_VERSION}/file/${PUBLISHER}.${EXTENSION_NAME}-${EXTENSION_VERSION}@${PLATFORM}.vsix"

echo "Platform: ${PLATFORM}"
echo "App path: ${APP_PATH}"
echo "Extensions dir: ${EXTENSIONS_DIR}"
echo "Downloading from: ${DOWNLOAD_URL}"

if ! curl -L -f -o "${VSIX_FILE}" "${DOWNLOAD_URL}"; then
  echo "Warning: Failed to download Claude Code extension for platform ${PLATFORM}"
  rm -f "${VSIX_FILE}"
  exit 0
fi

# Extract the VSIX file
EXT_DIR="${EXTENSIONS_DIR}/${EXTENSION_ID}"
mkdir -p "${EXT_DIR}"

# Create a temporary directory to extract VSIX
TMP_EXTRACT_DIR="${TMP_DIR}/vsix-extract-$$"
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
  echo "Error: unzip command not found" >&2
  rm -f "${VSIX_FILE}"
  exit 1
fi

rm -f "${VSIX_FILE}"

echo "Claude Code extension installed successfully"
ls -lh "${EXTENSIONS_DIR}/${EXTENSION_ID}/"
