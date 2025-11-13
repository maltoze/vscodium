# Claude Code Router - Standalone Executables

## Files

- `cli-macos-arm64` - macOS Apple Silicon executable
- `cli-macos-x64` - macOS Intel executable  
- `cli-linux-x64` - Linux x64 executable
- `cli-win-x64.exe` - Windows x64 executable
- `cli-win-arm64.exe` - Windows ARM64 executable
- `tiktoken_bg.wasm` - Required WASM file (must be in same directory)
- `index.html` - Web UI (must be in same directory)

## Usage

Make sure all files are in the same directory, then run:

### macOS/Linux
```bash
./cli-macos-arm64 -v
./cli-macos-arm64 start
```

### Windows
```cmd
cli-win-x64.exe -v
cli-win-x64.exe start
```

### Windows ARM64
```cmd
cli-win-arm64.exe -v
cli-win-arm64.exe start
```

## Important

**The executable must be in the same directory as `tiktoken_bg.wasm` and `index.html`.**

Do not rename or move files separately - keep them together.
