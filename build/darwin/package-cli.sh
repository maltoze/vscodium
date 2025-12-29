#!/usr/bin/env bash
set -e

ARCH="${1:-arm64}"
BUILD_DIR="${2:-.}"

if [[ ! -d "${BUILD_DIR}/VSCode-darwin-${ARCH}" ]]; then
  echo "Error: VSCode-darwin-${ARCH} directory not found"
  exit 1
fi

APP_DIR="${BUILD_DIR}/VSCode-darwin-${ARCH}/Claude Code Desktop.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"
CLI_BIN="${BUILD_DIR}/ccr-bin/cli-macos-${ARCH}"

if [[ ! -f "${CLI_BIN}" ]]; then
  echo "Warning: CLI binary not found at ${CLI_BIN}"
  exit 1
fi

echo "Packaging CLI binary into app..."

# Copy CLI files
cp "${CLI_BIN}" "${RESOURCES_DIR}/cli"
chmod +x "${RESOURCES_DIR}/cli"

echo "Copying CLI dependencies..."
cp "${BUILD_DIR}/ccr-bin/tiktoken_bg.wasm" "${RESOURCES_DIR}/" 2>/dev/null || echo "Warning: tiktoken_bg.wasm not found"
cp "${BUILD_DIR}/ccr-bin/index.html" "${RESOURCES_DIR}/" 2>/dev/null || echo "Warning: index.html not found"

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

function startCLIService(context) {
    const resourcesPath = path.join(__dirname, '../../..');
    const cliBinary = path.join(resourcesPath, 'cli');

    if (!fs.existsSync(cliBinary)) {
        console.error('[Startup Claude] CLI binary not found at:', cliBinary);
        return;
    }

    // Check if CLI is already running
    if (fs.existsSync(PID_FILE)) {
        try {
            const pid = fs.readFileSync(PID_FILE, 'utf-8').trim();
            try {
                process.kill(pid, 0);
                console.log('[Startup Claude] CLI service already running (PID:', pid + ')');
                return;
            } catch (e) {
                // Process not running, clean up PID file
                fs.unlinkSync(PID_FILE);
            }
        } catch (err) {
            console.error('[Startup Claude] Error reading PID file:', err.message);
        }
    }

    // Set environment variable
    if (shouldUseLocalEnv()) {
        process.env.ANTHROPIC_BASE_URL = 'http://127.0.0.1:3456';
        process.env.ANTHROPIC_AUTH_TOKEN = 'test';
        process.env.ANTHROPIC_API_KEY = 'test';
        process.env.CLAUDE_CODE_SKIP_AUTH_LOGIN = 'true';
    }

    // Start CLI service
    console.log('[Startup Claude] Starting CLI service...');
    cliProcess = spawn(cliBinary, ['restart'], {
        detached: true,
        stdio: ['ignore', 'pipe', 'pipe'],
        env: { ...process.env }
    });

    // Write PID to file
    fs.writeFileSync(PID_FILE, cliProcess.pid.toString());

    cliProcess.stdout.on('data', (data) => {
        fs.appendFileSync(LOG_FILE, `[${new Date().toISOString()}] ${data}\n`);
    });

    cliProcess.stderr.on('data', (data) => {
        fs.appendFileSync(LOG_FILE, `[ERROR ${new Date().toISOString()}] ${data}\n`);
    });

    console.log('[Startup Claude] CLI service started with PID:', cliProcess.pid);
}

function stopCLIService() {
    if (fs.existsSync(PID_FILE)) {
        try {
            const pid = parseInt(fs.readFileSync(PID_FILE, 'utf-8').trim());
            process.kill(pid, 'SIGTERM');
            fs.unlinkSync(PID_FILE);
            console.log('[Startup Claude] CLI service stopped');
        } catch (err) {
            console.error('[Startup Claude] Error stopping CLI service:', err.message);
        }
    }
}

function activate(context) {
    console.log('[Startup Claude] Activating...');

    if (shouldUseLocalEnv()) {
        process.env.ANTHROPIC_BASE_URL = 'http://127.0.0.1:3456';
        process.env.ANTHROPIC_AUTH_TOKEN = 'test';
        process.env.ANTHROPIC_API_KEY = 'test';
        process.env.CLAUDE_CODE_SKIP_AUTH_LOGIN = 'true';
    } else {
      process.env.CLAUDE_CODE_SKIP_AUTH_LOGIN = 'false';
      process.env.ANTHROPIC_BASE_URL = '';
      process.env.ANTHROPIC_AUTH_TOKEN = '';
      process.env.ANTHROPIC_API_KEY = '';
    }

    // Start CLI service
    // startCLIService(context);

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
    // stopCLIService();
}

module.exports = {
    activate,
    deactivate
};
STARTUP_EXT

echo "CLI packaging completed successfully"
