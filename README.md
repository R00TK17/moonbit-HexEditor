# MoonBit Hex Editor

A terminal-based hex editor and binary file analyzer written in MoonBit, featuring an interactive TUI, structure parsing for 16+ file formats, search, and editing capabilities. Runs on Windows and Linux.

## Features

### Interactive TUI
- Hex dump with offset column, 16 bytes/row, and ASCII sidebar
- Navigation: Arrow keys (`↑↓` line scroll, `←→` page), Home/End, Goto offset / bookmark (`g #N`)
- Search: `/` hex pattern, `f` ASCII text, `n`/`N` next/prev match
- Highlighting: current match (green), other matches (yellow), edit cursor (inverse)
- Edit mode: hex/ASCII input, insert, delete, undo/redo (`Ctrl+Z`/`Ctrl+Y`) with depth display, save (`Ctrl+X`)
- Structure view: parsed file structure with scrollable display
- Bookmarks: 21 slots (0-20), popup list with auto-scroll, `Ctrl+B` set, `#N` goto
- Signature scan: `w` key, 20 formats with per-signature validation, confidence filtering, cached results
  - **Image:** JPEG, PNG, GIF, BMP
  - **Archive:** ZIP, RAR, 7z, GZip, Zlib, BZip2
  - **Executable:** PE (exe/dll), ELF
  - **Document:** PDF, XML
  - **Crypto:** OpenSSL, PEM, LUKS, GPG
  - **Audio:** WAV
  - **Database:** SQLite3
- Scan result caching: `w`/`s`/`h` save position when re-opened, auto-clear on edits
- Entropy analysis: `h` key, 256-byte blocks, Shannon entropy with color-coded bars
- Strings extraction: `s` key, printable ASCII sequences >= 4 chars, with caching, jump-to-offset and highlight
- Extraction: `x` key to dump selected match, trailing data detection
- mmap loading: memory-mapped file I/O for fast file opens (auto-fallback to standard I/O)

### CLI Commands
```
moon run --target native cmd/main -- view [-b 8|16] <f>  Quick hex dump
moon run --target native cmd/main -- info <file>      File info + type detection
moon run --target native cmd/main -- search [-x|-a] <f> <p>   Search (hex/text)
moon run --target native cmd/main -- struct <file>    Structure analysis
moon run --target native cmd/main -- strings <file>   String extraction
moon run --target native cmd/main -- entropy <file>   Entropy analysis
moon run --target native cmd/main -- scan <file>      Signature scan
moon run --target native cmd/main -- encode <type> <f>   Encode (base64/url/unicode/ascii)
moon run --target native cmd/main -- decode <type> <f>   Decode (base64/url/unicode/ascii)
moon run --target native cmd/main -- base64 <file>       Base64 encode (alias)
moon run --target native cmd/main -- unbase64 <file>     Base64 decode (alias)
```

### Structure Parser (16 Formats)

| Category | Formats |
|----------|---------|
| Image | JPEG, PNG, GIF, BMP |
| Audio | WAV, FLAC, MP3, OGG |
| Video | AVI, MP4, WebM/MKV |
| Archive | ZIP, RAR, TAR, ZLIB |
| Executable | PE, ELF |

Parsed details: dimensions (image/video), sample rate/channels (audio), compression method & filenames (archive), section tables (executable), encryption detection (ZIP/RAR).

## Build & Usage

```bash
# Build
moon build --target native

# Run tests
moon test

# Start TUI
moon run --target native cmd/main -- file.bin
moon run --target native cmd/main                  # empty start
```

### TUI Keys

| Normal | Action | Edit | Action |
|--------|--------|------|--------|
| `q` | Quit | `Esc` | Exit edit |
| `↑↓` | Line scroll | `↑↓←→` | Move cursor |
| `←→` | Page up/down | `0-9 a-f` | Hex input |
| `Home/End` | Start/end | `Tab` | Hex/ASCII mode |
| `g` | Goto / #N bookmark | `i` | Insert byte |
| `/` | Hex search | `Del` | Delete byte |
| `f` | Text search | `Ctrl+Z` | Undo |
| `n` | Next match | `Ctrl+Y` | Redo |
| `p` | Prev match | `Ctrl+X` | Save |
| `e` | Edit mode | | |
| `t` | Struct view | `Ctrl+B` | Set bookmark |
| `b` | Bookmark list | | |
| `w` | Signature scan | | |
| `h` | Entropy analysis | | |
| `s` | Strings extraction | | |

Struct view: `↑↓←→` scroll, `t`/`Esc` back to hex, `q` quit.

Bookmark list: `↑↓` select, `Enter` jump, `d` delete, `b`/`Esc` close, `q` quit, `Ctrl+B` set.

Signature scan: `↑↓←→` navigate, `Enter` jump, `x` extract, `w`/`Esc` close, results cached until edit.

Entropy scan: `↑↓←→` navigate, `Enter` jump to block, `h`/`Esc` close.

Strings: `↑↓←→` navigate, `Enter` jump+highlight, `s`/`Esc` close.

### Platform Notes

| Platform | Details |
|----------|---------|
| Windows | conio + ENABLE_VIRTUAL_TERMINAL_PROCESSING, alternate screen buffer, `CreateFileMapping` mmap |
| Linux | termios persistent raw mode, signal-safe restore, alt screen, direct `write()`, `mmap` (syscall) |

## Project Structure

```
hex_editor/
├── hex_editor.mbt                # HexBuffer data model, file I/O, edit primitives
├── hex_view.mbt                 # Hex dump formatting, size display, hex byte table
├── hex_search.mbt               # Boyer-Moore-Horspool search (find_all, parse_hex)
├── hex_struct.mbt               # 16+ file format parser (JPEG/PNG/ZIP/PE/ELF...)
├── hex_scan.mbt                 # Signature scanner (20 formats), Aho-Corasick
├── hex_strings.mbt              # Printable ASCII string extraction
├── hex_entropy.mbt              # Shannon entropy analysis (256-byte blocks)
├── hex_codec.mbt                # Codecs: Base64, URL, Unicode, ASCII encoding/decoding
├── hex_editor_test.mbt          # Unit tests
├── cmd/main/
│   ├── main.mbt                 # CLI entry (view/info/struct/strings/entropy/scan)
│   ├── helpers.mbt              # CLI argument parsing, file loading, type detection
│   ├── helpers_native.mbt       # Native target helpers (hex/ASCII conversion)
│   ├── tui.mbt                  # TUI main loop, FFI declarations, mmap loading
│   ├── tui_key.mbt              # Key dispatch for all modes, TuiState struct
│   ├── tui_bookmark.mbt         # Bookmark popup (21 slots), set/jump/delete
│   ├── tui_draw.mbt             # Screen rendering (hex dump, popups, status/help bars)
│   ├── tui_edit.mbt             # TUI edit mode, UndoOp-based undo/redo
│   └── tui_stub.c               # C terminal stubs (raw mode, alt screen, mmap I/O)
```

## Dependencies

- [moonbitlang/x](https://mooncakes.io/packages/moonbitlang/x) — File I/O & system APIs
- MoonBit 0.1.20260529+

## License

Apache-2.0
