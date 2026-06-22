#!/bin/bash
# MoonBit Hex Editor — Linux 一键搭建脚本
set -e

echo "========================================="
echo " MoonBit Hex Editor — Setup Script"
echo "========================================="
echo ""

# 1. Check C compiler
echo "[1/5] Checking C compiler..."
if command -v gcc &>/dev/null; then
    echo "  ✓ gcc $(gcc --version | head -1)"
else
    echo "  ✗ No C compiler found. Installing gcc..."
    if command -v apt &>/dev/null; then
        sudo apt update && sudo apt install -y gcc
    elif command -v yum &>/dev/null; then
        sudo yum install -y gcc
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm gcc
    elif command -v brew &>/dev/null; then
        brew install gcc
    else
        echo "  Please install gcc manually (apt/yum/pacman/brew)."
        exit 1
    fi
    # Verify after install
    if command -v gcc &>/dev/null; then
        echo "  ✓ gcc installed: $(gcc --version | head -1)"
    else
        echo "  ✗ gcc installed but not found on PATH. Check your PATH or install manually."
        exit 1
    fi
fi

# 2. Check/Install MoonBit
echo ""
echo "[2/5] Checking MoonBit toolchain..."
if command -v moon &>/dev/null; then
    echo "  ✓ $(moon version 2>&1 | head -1)"
else
    echo "  Installing MoonBit..."
    if ! command -v curl &>/dev/null; then
        echo "  ✗ curl installation failed, install curl manually and retry"
        exit 1
    fi
    curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
    export PATH="$HOME/.moon/bin:$PATH"
    if command -v moon &>/dev/null; then
        echo "  ✓ MoonBit installed: $(moon version 2>&1 | head -1)"
    else
        echo "  ✗ MoonBit installation failed. Please install manually:"
        echo "    https://www.moonbitlang.com/download/"
        exit 1
    fi
fi

# 3. Install dependencies
echo ""
echo "[3/5] Installing dependencies..."
moon update 2>/dev/null || true

# 4. Build
echo ""
echo "[4/5] Building..."
moon build --target native
echo "  ✓ Native build OK"
moon build --target wasm-gc cmd/wasm
echo "  ✓ Wasm-GC build OK"

# 5. Test
echo ""
echo "[5/5] Running tests..."
RESULT=$(moon test --target native 2>&1 | tail -1)
echo "  $RESULT"

echo ""
echo "========================================="
echo " Setup Complete!"
echo "========================================="
echo ""
echo " Note: if 'moon' is not found after opening a new terminal,"
echo "   add this to your ~/.bashrc or ~/.zshrc:"
echo '     export PATH="$HOME/.moon/bin:$PATH"'
echo ""
echo " Usage:"
echo "   # TUI mode"
echo "   moon run --target native cmd/main -- <file>"
echo ""
echo "   # CLI commands"
echo "   moon run --target native cmd/main -- view <file>"
echo "   moon run --target native cmd/main -- struct <file>"
echo "   moon run --target native cmd/main -- scan <file>"
echo "   moon run --target native cmd/main -- help"
echo ""
echo "   # Wasm-GC CLI"
echo "   moon run --target wasm-gc cmd/wasm -- struct <file>"
echo ""
