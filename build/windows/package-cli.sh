#!/usr/bin/env bash
set -e

ARCH="${1:-x64}"
BUILD_DIR="${2:-.}"

# Map architecture names (Windows uses different naming)
case "$ARCH" in
  x64)
    WIN_ARCH="x64"
    ;;
  # x86)
  #   WIN_ARCH="ia32"
  #   ;;
  arm64)
    WIN_ARCH="arm64"
    ;;
  *)
    echo "Error: Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

if [[ ! -d "${BUILD_DIR}/VSCode-win32-${WIN_ARCH}" ]]; then
  echo "Error: VSCode-win32-${WIN_ARCH} directory not found"
  exit 1
fi

APP_DIR="${BUILD_DIR}/VSCode-win32-${WIN_ARCH}"
RESOURCES_DIR="${APP_DIR}/resources"
CLI_BIN="${BUILD_DIR}/ccr-bin/cli-win-${ARCH}.exe"

if [[ ! -f "${CLI_BIN}" ]]; then
  echo "Warning: CLI binary not found at ${CLI_BIN}"
  exit 1
fi

echo "Packaging CLI binary into app..."

# Copy CLI files
cp "${CLI_BIN}" "${RESOURCES_DIR}/cli.exe"

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
const os = require('os');

let cliProcess = null;
const PID_FILE = path.join(os.tmpdir(), 'vscodium-cli.pid');
const LOG_FILE = path.join(os.tmpdir(), 'vscodium-cli.log');

function startCLIService(context) {
    const resourcesPath = path.join(__dirname, '../../..');
    const cliBinary = path.join(resourcesPath, 'cli.exe');

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

    // Set environment variables
    const env = { ...process.env };
    env.ANTHROPIC_BASE_URL = 'http://127.0.0.1:3456';
    env.ANTHROPIC_AUTH_TOKEN = 'test';
    env.ANTHROPIC_API_KEY = 'test';
    env.CLAUDE_CODE_SKIP_AUTH_LOGIN = 'true';

    // Start CLI service
    console.log('[Startup Claude] Starting CLI service...');
    console.log('[Startup Claude] CLI binary path:', cliBinary);

    try {
        cliProcess = spawn(cliBinary, ['start'], {
            detached: true,
            stdio: 'ignore',
            windowsHide: true
        });

        // Unref to allow parent process to exit independently
        if (cliProcess.unref) {
            cliProcess.unref();
        }
    } catch (err) {
        console.error('[Startup Claude] Failed to spawn CLI process:', err);
        return;
    }

    // Write PID to file
    try {
        fs.writeFileSync(PID_FILE, cliProcess.pid.toString());
        console.log('[Startup Claude] PID written to:', PID_FILE);
    } catch (err) {
        console.error('[Startup Claude] Error writing PID file:', err.message);
    }

    // Handle process errors
    cliProcess.on('error', (err) => {
        console.error('[Startup Claude] CLI process error:', err);
        try {
            fs.appendFileSync(LOG_FILE, `[ERROR] Failed to start: ${err.message}\n`);
        } catch (e) {}
    });

    cliProcess.on('exit', (code, signal) => {
        console.log('[Startup Claude] CLI process exited with code:', code, 'signal:', signal);
        try {
            if (fs.existsSync(PID_FILE)) {
                fs.unlinkSync(PID_FILE);
            }
        } catch (err) {
            console.error('[Startup Claude] Error cleaning up PID file:', err.message);
        }
    });

    if (cliProcess.stdout) {
        cliProcess.stdout.on('data', (data) => {
            try {
                fs.appendFileSync(LOG_FILE, `[${new Date().toISOString()}] ${data}\n`);
            } catch (err) {
                console.error('[Startup Claude] Error writing log:', err.message);
            }
        });
    }

    if (cliProcess.stderr) {
        cliProcess.stderr.on('data', (data) => {
            try {
                fs.appendFileSync(LOG_FILE, `[ERROR ${new Date().toISOString()}] ${data}\n`);
            } catch (err) {
                console.error('[Startup Claude] Error writing error log:', err.message);
            }
        });
    }

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

    // Start CLI service
    startCLIService(context);

    // Register cleanup on deactivate
    context.subscriptions.push({
        dispose: stopCLIService
    });

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
    stopCLIService();
}

module.exports = {
    activate,
    deactivate
};
STARTUP_EXT

echo "CLI packaging completed successfully"
