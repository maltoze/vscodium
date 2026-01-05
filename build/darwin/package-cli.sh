#!/usr/bin/env bash
set -e

ARCH="${1:-arm64}"
BUILD_DIR="${2:-.}"

if [[ ! -d "${BUILD_DIR}/VSCode-darwin-${ARCH}" ]]; then
  echo "Error: VSCode-darwin-${ARCH} directory not found"
  exit 1
fi

APP_DIR="${BUILD_DIR}/VSCode-darwin-${ARCH}/DeployAI Studio.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"

echo "Packaging CLI binary into app..."

# Create startup extension to open Claude Code
mkdir -p "${RESOURCES_DIR}/app/extensions/startup-claude"

cat > "${RESOURCES_DIR}/app/extensions/startup-claude/package.json" << 'STARTUP_PKG'
{
  "name": "startup-claude",
  "displayName": "Startup Claude",
  "version": "1.0.0",
  "engines": {
    "vscode": "^1.0.0"
  },
  "activationEvents": [
    "onStartupFinished"
  ],
  "main": "./extension.js",
  "contributes": {}
}
STARTUP_PKG

cat > "${RESOURCES_DIR}/app/extensions/startup-claude/extension.js" << 'STARTUP_EXT'
const vscode = require('vscode');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

let cliProcess = null;
const PID_FILE = '/tmp/vscodium-cli.pid';
const LOG_FILE = '/tmp/vscodium-cli.log';

function shouldUseLocalEnv() {
    try {
        const config = vscode.workspace.getConfiguration('deployai');
        return !config.get('useClaudeAccountLogin', false);
    } catch (err) {
        return true;
    }
}

function activate(context) {
    console.log('[Startup Claude] Activating...');

    if (shouldUseLocalEnv()) {
        process.env.ANTHROPIC_BASE_URL = 'http://127.0.0.1:38999';
        process.env.ANTHROPIC_AUTH_TOKEN = 'test';
        process.env.ANTHROPIC_API_KEY = 'test';
        process.env.CLAUDE_CODE_SKIP_AUTH_LOGIN = 'true';
    } else {
      process.env.CLAUDE_CODE_SKIP_AUTH_LOGIN = 'false';
      process.env.ANTHROPIC_BASE_URL = '';
      process.env.ANTHROPIC_AUTH_TOKEN = '';
      process.env.ANTHROPIC_API_KEY = '';
    }

    // Register cleanup on deactivate
    // context.subscriptions.push({
    //     dispose: stopCLIService
    // });

    // Give Claude Code extension time to load, then open Claude Code editor
    setTimeout(() => {
        vscode.commands.executeCommand('claude-vscode.editor.open')
            .then(() => {
                console.log('[Startup Claude] Claude Code editor opened successfully');
            })
            .catch(err => {
                console.error('[Startup Claude] Failed to open Claude Code:', err.message);
            });
    }, 100);
}

function deactivate() {
}

module.exports = {
    activate,
    deactivate
};
STARTUP_EXT

echo "CLI packaging completed successfully"
