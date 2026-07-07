# R00TK17/hex_editor

[![CI](https://github.com/R00TK17/moonbit-HexEditor/actions/workflows/ci.yml/badge.svg)](https://github.com/R00TK17/moonbit-HexEditor/actions/workflows/ci.yml)

Terminal hex editor and binary file analysis toolkit written in MoonBit.

## Features

- **Hex Editor TUI** — interactive terminal UI with gap-buffer O(1) editing, undo/redo, clipboard
- **20 Format Parsers** — JPEG, PNG, GIF, BMP, WAV, FLAC, MP3, OGG, AVI, MP4, WebM/MKV, ZIP, RAR, TAR, ZLIB, GZip, 7z, BZip2, PE, ELF
- **Wildcard Search** — BMH exact, Shift-Or bit-parallel (??), greedy segment (*, *N)
- **Signature Scanner** — Aho-Corasick multi-pattern matching with 18 per-format validators
- **Entropy Analysis** — Shannon entropy on 256-byte blocks (precomputed lookup table)
- **Codecs** — Base64, URL percent-encoding, Unicode escape, Hex encode/decode
- **Strings Extraction** — printable ASCII sequences ≥ 4 chars
- **File Browser** — UTF-8 path support, multi-file switching, persistent bookmarks
- **Steganography Detection** — embedded file extraction, trailing data detection

## Quick Start

```bash
# Clone and setup (auto-installs MoonBit, GCC, builds, tests)
git clone https://github.com/R00TK17/moonbit-HexEditor.git
cd moonbit-HexEditor
chmod +x setup.sh && ./setup.sh   # Linux
# .\setup.ps1                     # Windows

# CLI usage
moon run cmd/main -- struct file.bin
moon run cmd/main -- scan file.bin
moon run cmd/main -- entropy file.bin

# TUI mode
moon run cmd/main -- file.bin
```

## Usage as a Library

```moonbit nocheck
// Parse binary file structure

///|
let fields = @R00TK17/hex_editor.parse_structure(bytes)

// Scan for embedded file signatures

///|
let matches = @R00TK17/hex_editor.scan_signatures(bytes)

// Shannon entropy analysis (256-byte blocks)

///|
let blocks = @R00TK17/hex_editor.entropy_scan(bytes)

// Search with wildcards

///|
let result = @R00TK17/hex_editor.find_hex_pattern(bytes, "FF ?? ?? EE")

///|
let result = @R00TK17/hex_editor.find_text_pattern(bytes, "He*ld")

// Codecs

///|
let b64 = @R00TK17/hex_editor.base64_encode(bytes)

///|
let decoded = @R00TK17/hex_editor.base64_decode(b64)
```

## Platform Support

| Platform | Native | Wasm-GC |
|----------|--------|---------|
| Windows | ✓ TUI + CLI | N/A |
| Linux | ✓ TUI + CLI | N/A |
| Browser | — | ✓ CLI only |

## Links

- [Full Documentation](https://github.com/R00TK17/moonbit-HexEditor)
- [Technical Report](https://github.com/R00TK17/moonbit-HexEditor/blob/main/TECHNICAL_REPORT.md)
- [CI Pipeline](https://github.com/R00TK17/moonbit-HexEditor/actions)
