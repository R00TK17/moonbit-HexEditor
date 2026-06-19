**English** | [中文](README_CN.md)

# MoonBit Hex Editor

A terminal-based hex editor and binary file analyzer written in MoonBit, featuring an interactive TUI, structure parsing for 16+ file formats, search, and editing capabilities. Runs on Windows and Linux.

## Features

### Interactive TUI
- Hex dump with offset column, 16 bytes/row, and ASCII sidebar
- Navigation: Arrow keys (`↑↓` line scroll, `←→` page), Home/End, Goto offset / bookmark (`g #N`)
- Search: `/` hex pattern, `f` ASCII text, `n`/`N` next/prev match
  - Hex wildcards: `??` any byte, `*` any length, `*N` skip N bytes (e.g. `FF ?? 00`, `89 *3 0D 0A`)
  - Text wildcards: `?` any char, `*` any length, `*N` skip N chars, `\` escape (e.g. `He*ld`, `\?`)
- Highlighting: current match (green), other matches (yellow), edit cursor (inverse)
- Edit mode: hex/ASCII input, `Ins` toggle insert/overwrite, delete, undo/redo (`Ctrl+Z`/`Ctrl+R`), save (`Ctrl+X`)
  - Visual selection: `Ctrl+Y` start/cancel, `Ctrl+N` copy, `Ctrl+L` paste (compound undo)
  - Gap Buffer: O(1) insert/delete at cursor, gap = file allocation / 16
- Structure view: parsed file structure with scrollable display
- Bookmarks: 21 slots (0-20), popup list with auto-scroll, `Ctrl+B` set, `#N` goto, **persistent** (auto save/load to `~/.hexedit/`)
- Signature scan: `w` key, 14 formats with per-signature validation, confidence filtering, cached results
  - **Image:** JPEG, PNG, GIF, BMP
  - **Archive:** ZIP, RAR, 7z, GZip, Zlib, BZip2, TAR
  - **Executable:** PE (exe/dll), ELF
  - **Audio:** WAV
- Scan result caching: `w`/`s`/`h` save position when re-opened, auto-clear on edits
- Entropy analysis: `h` key, 256-byte blocks, Shannon entropy with color-coded bars
- Strings extraction: `s` key, printable ASCII sequences >= 4 chars, with caching, jump-to-offset and highlight
- Extraction: `x` key to dump selected match, trailing data detection
- Export: `e` key in struct/strings views — structure as JSON, strings as text
- Codec popup: `c` key, interactive Base64/URL/Unicode/Hex encode/decode with live preview
- Multi-file: open multiple files, `Tab` file list popup, switch/close files independently
- File browser: `o` key opens directory browser with navigation, `Enter` open/enter, `o` type path directly
- Bookmark persistence: bookmarks + scroll position auto-saved to `~/.hexedit/`, restored on next open
- UTF-8 support: Chinese filenames display correctly (Windows Wide API + UTF-8 console)
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
moon run --target native cmd/main -- encode <type> <f>   Encode (base64/url/unicode/hex)
moon run --target native cmd/main -- decode <type> <f>   Decode (base64/url/unicode/hex)
moon run --target native cmd/main -- base64 <file>       Base64 encode (alias)
moon run --target native cmd/main -- unbase64 <file>     Base64 decode (alias)
```

### Structure Parser (19 Formats)

| Category | Formats |
|----------|---------|
| Image | JPEG, PNG, GIF, BMP |
| Audio | WAV, FLAC, MP3, OGG |
| Video | AVI, MP4, WebM/MKV |
| Archive | ZIP, RAR, TAR, ZLIB, GZip, 7z, BZip2 |
| Executable | PE, ELF |

Parsed details: dimensions (image/video), sample rate/channels (audio), compression method & filenames (archive), section tables (executable), encryption detection (ZIP/RAR).

## Build & Usage

```bash
# Build
moon build --target native

# Run tests
moon test --target native

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
| `g` | Goto / #N bookmark | `Ins` | Insert/Overwrite toggle |
| `/` | Hex search | `Del` | Delete byte |
| `f` | Text search | `Ctrl+Z` | Undo |
| `n` | Next match | `Ctrl+R` | Redo |
| `p` | Prev match | `Ctrl+X` | Save |
| `e` | Edit mode | `Ctrl+Y` | Select |
| `t` | Struct view | `Ctrl+N` | Copy |
| `b` | Bookmark list | `Ctrl+L` | Paste |
| `w` | Signature scan | `Ctrl+B` | Set bookmark |
| `h` | Entropy analysis | | |
| `s` | Strings extraction | | |
| `c` | Codec (encode/decode) | | |
| `o` | File browser | | |
| `Tab` | File list (multi-file) | | |

Struct view: `↑↓←→` scroll, `t`/`Esc` back to hex, `q` quit.

Bookmark list: `↑↓` select, `Enter` jump, `d` delete, `b`/`Esc` close, `q` quit, `Ctrl+B` set.

Signature scan: `↑↓←→` navigate, `Enter` jump, `x` extract, `w`/`Esc` close, results cached until edit.

Entropy scan: `↑↓←→` navigate, `Enter` jump to block, `h`/`Esc` close.

Strings: `↑↓←→` navigate, `Enter` jump+highlight, `s`/`Esc` close.

Codec: `←→` switch type (Base64/URL/Unicode/Hex), `Tab` toggle encode/decode, type text, `Esc` close.

File browser (`o`): `↑↓` navigate, `Enter` open file / enter dir, `o` type path, `Esc` cancel.

File list (`Tab`): `↑↓` select, `Enter` switch, `d` close file, `Tab`/`Esc` back.

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
├── hex_search.mbt               # Search: BMH exact, wildcard (?? * *N), text pattern (? * \)
├── hex_struct.mbt               # 16+ file format parser (JPEG/PNG/ZIP/PE/ELF...)
├── hex_scan.mbt                 # Signature scanner (20 formats), Aho-Corasick
├── hex_strings.mbt              # Printable ASCII string extraction
├── hex_entropy.mbt              # Shannon entropy analysis (256-byte blocks)
├── hex_codec.mbt                # Codecs: Base64, URL, Unicode, Hex encoding/decoding
├── hex_editor_test.mbt          # 85 unit + integration tests
├── cmd/main/
│   ├── main.mbt                 # CLI entry (view/info/struct/strings/entropy/scan)
│   ├── helpers.mbt              # CLI argument parsing, file loading, type detection
│   ├── helpers_native.mbt       # Native target helpers (hex/ASCII conversion)
│   ├── tui.mbt                  # TUI main loop, FFI declarations, mmap loading
│   ├── tui_key.mbt              # Key dispatch for all modes, TuiState struct
│   ├── tui_bookmark.mbt         # Bookmark popup (21 slots), set/jump/delete
│   ├── tui_files.mbt            # File browser, multi-file management, bookmark persistence
│   ├── tui_draw.mbt             # Screen rendering (hex dump, popups, status/help bars)
│   ├── tui_edit.mbt             # TUI edit mode, UndoOp-based undo/redo
│   └── tui_stub.c               # C stubs (terminal, mmap, directory listing, UTF-8)
```

## Dependencies

- [moonbitlang/x](https://github.com/moonbitlang/x) — File I/O & system APIs
- MoonBit 0.1.20260529+

## License

Apache-2.0
