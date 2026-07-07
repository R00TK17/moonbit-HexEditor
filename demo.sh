#!/bin/bash
# MoonBit Hex Editor — Demo Script
# Run after setup: chmod +x demo.sh && ./demo.sh

set -e

echo "========================================="
echo " MoonBit Hex Editor — Demo"
echo "========================================="
echo ""

# Ensure built
if [ ! -f "_build/native/debug/test/hex_editor.internal_test.exe" ] && \
   [ ! -f "target/native/debug/build/main/main" ]; then
    echo "Building first..."
    moon build
fi

echo "--- 1. File Structure Analysis ---"
echo "$ moon run cmd/main -- struct testfile/test.png"
echo ""
moon run cmd/main -- struct testfile/test.png 2>&1 | head -20
echo ""

echo "--- 2. Signature Scan (Steganography Detection) ---"
echo "$ moon run cmd/main -- scan testfile/hidden.jpg"
echo ""
moon run cmd/main -- scan testfile/hidden.jpg 2>&1
echo ""

echo "--- 3. Hex Dump ---"
echo "$ moon run cmd/main -- view testfile/test.txt"
echo ""
moon run cmd/main -- view testfile/test.txt 2>&1
echo ""

echo "--- 4. Entropy Analysis ---"
echo "$ moon run cmd/main -- entropy testfile/test.zip"
echo ""
moon run cmd/main -- entropy testfile/test.zip 2>&1
echo ""

echo "--- 5. Base64 Encoding ---"
echo "$ moon run cmd/main -- encode base64 Hello"
echo ""
moon run cmd/main -- encode base64 "Hello" 2>&1
echo ""

echo "--- 6. Search ---"
echo "$ moon run cmd/main -- search -x testfile/test.png 89504E47"
echo ""
moon run cmd/main -- search -x testfile/test.png "89504E47" 2>&1
echo ""

echo "========================================="
echo " Demo Complete!"
echo "========================================="
echo ""
echo "For full TUI: moon run cmd/main -- testfile/test.png"
