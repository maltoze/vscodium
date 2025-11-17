#!/usr/bin/env bash
set -e

ARCH="${1:-x64}"
BUILD_DIR="${2:-.}"

# Map architecture names (Windows uses different naming)
case "$ARCH" in
  x64)
    WIN_ARCH="x64"
    ;;
  x86)
    WIN_ARCH="ia32"
    ;;
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
GIT_BASH_DIR="${RESOURCES_DIR}/bin/git-bash"

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

# Download and package Git Bash
echo "Downloading Git Bash Portable..."
mkdir -p "${GIT_BASH_DIR}"

GIT_BASH_URL="https://github.com/git-for-windows/git/releases/download/v2.43.0.windows.1/PortableGit-2.43.0-64-bit.7z.exe"
GIT_BASH_ARCHIVE="${BUILD_DIR}/git-bash-setup.exe"

if [[ ! -f "${GIT_BASH_ARCHIVE}" ]]; then
  curl -L -o "${GIT_BASH_ARCHIVE}" "${GIT_BASH_URL}" || { echo "Error: Failed to download Git Bash"; exit 1; }
fi

echo "Extracting Git Bash to app..."
"${GIT_BASH_ARCHIVE}" -y -o"${GIT_BASH_DIR}" > /dev/null 2>&1 || { echo "Error: Failed to extract Git Bash"; exit 1; }

# Cleanup
rm -f "${GIT_BASH_ARCHIVE}"
echo "Git Bash packaged successfully"

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

function getGitBashPath() {
    const resourcesPath = path.join(__dirname, '../../..');
    const bundledGitBash = path.join(resourcesPath, 'bin', 'git-bash', 'bin', 'bash.exe');

    // Check bundled Git Bash first
    if (fs.existsSync(bundledGitBash)) {
        console.log('[Startup Claude] Found bundled Git Bash at:', bundledGitBash);
        return bundledGitBash;
    }

    // Fall back to system Git Bash
    const commonPaths = [
        'C:\\Program Files\\Git\\bin\\bash.exe',
        'C:\\Program Files (x86)\\Git\\bin\\bash.exe',
        path.join(process.env.ProgramFiles, 'Git\\bin\\bash.exe'),
        path.join(process.env['ProgramFiles(x86)'], 'Git\\bin\\bash.exe'),
        path.join(process.env.APPDATA, '..\\Local\\Programs\\Git\\bin\\bash.exe')
    ];

    for (const bashPath of commonPaths) {
        if (fs.existsSync(bashPath)) {
            console.log('[Startup Claude] Found system Git Bash at:', bashPath);
            return bashPath;
        }
    }

    console.warn('[Startup Claude] Git Bash not found');
    return null;
}

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

    // Get Git Bash path
    const gitBashPath = getGitBashPath();

    // Build complete environment with all variables
    const env = Object.assign({}, process.env);
    env.ANTHROPIC_BASE_URL = 'http://127.0.0.1:3456';
    env.ANTHROPIC_AUTH_TOKEN = 'test';
    env.ANTHROPIC_API_KEY = 'test';
    env.CLAUDE_CODE_SKIP_AUTH_LOGIN = 'true';

    if (gitBashPath) {
        const gitBashBinDir = path.dirname(gitBashPath);
        env.PATH = gitBashBinDir + path.delimiter + (env.PATH || '');
        env.CLAUDE_CODE_GIT_BASH_PATH = gitBashPath;
        console.log('[Startup Claude] Git Bash bin dir added to PATH:', gitBashBinDir);
        console.log('[Startup Claude] CLAUDE_CODE_GIT_BASH_PATH set to:', gitBashPath);
    }

    // Start CLI service
    console.log('[Startup Claude] Starting CLI service...');
    cliProcess = spawn(cliBinary, ['start'], {
        detached: true,
        stdio: ['ignore', 'pipe', 'pipe'],
        env: env,
        windowsHide: true
    });

    // Write PID to file
    try {
        fs.writeFileSync(PID_FILE, cliProcess.pid.toString());
    } catch (err) {
        console.error('[Startup Claude] Error writing PID file:', err.message);
    }

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
