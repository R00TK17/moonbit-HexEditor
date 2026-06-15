# MoonBit Hex Editor

A terminal-based hex editor and binary file analyzer written in MoonBit, featuring an interactive TUI, structure parsing for 16+ file formats, search, and editing capabilities. Runs on Windows and Linux.

## Features

### Interactive TUI
- Hex dump with offset column, 16 bytes/row, and ASCII sidebar
- Navigation: Arrow keys (`↑↓` line scroll, `←→` page), Home/End, Goto offset / bookmark (`g #N`)
- Search: `/` hex pattern, `f` ASCII text, `n`/`N` next/prev match
- Highlighting: current match (green), other matches (yellow), edit cursor (inverse)
- Edit mode: hex/ASCII input, insert, delete, undo/redo (`Ctrl+Z`/`Ctrl+Y`) with depth display, smart save prompt
- Structure view: parsed file structure with scrollable display
- Bookmarks: 21 slots (0-20), popup list with auto-scroll, `Ctrl+B` set, `#N` goto
- Signature scan: `w` key, 20 CTF-focused formats with per-signature validation, cached results
- Entropy analysis: `h` key, 256-byte blocks, Shannon entropy with color-coded bars
- Extraction: `x` key to dump selected match, trailing data detection
- mmap loading: memory-mapped file I/O for fast file opens (auto-fallback to standard I/O)

### CLI Commands
```
moon run --target native cmd/main -- view <file>     Quick hex dump
moon run --target native cmd/main -- info <file>     File info + type detection
moon run --target native cmd/main -- search <f> <p>  Pattern search
moon run --target native cmd/main -- struct <file>   Structure analysis
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
| `p` | Prev match | `Ctrl+S` | Save |
| `e` | Edit mode | | |
| `t` | Struct view | `Ctrl+B` | Set bookmark |
| `b` | Bookmark list | | |
| `w` | Signature scan | | |
| `h` | Entropy analysis | | |

Struct view: `↑↓←→` scroll, `t`/`Esc` back to hex, `q` quit.

Bookmark list: `↑↓` select, `Enter` jump, `d` delete, `b`/`Esc` close, `q` quit, `Ctrl+B` set.

Signature scan: `↑↓←→` navigate, `Enter` jump, `x` extract, `w`/`Esc` close, results cached until edit.

Entropy scan: `↑↓←→` navigate, `Enter` jump to block, `h`/`Esc` close.

### Platform Notes

| Platform | Details |
|----------|---------|
| Windows | conio + ENABLE_VIRTUAL_TERMINAL_PROCESSING, alternate screen buffer, `CreateFileMapping` mmap |
| Linux | termios persistent raw mode, signal-safe restore, alt screen, direct `write()`, `mmap` (syscall) |

## Project Structure

```
hex_editor/
├── hex_editor.mbt                # HexBuffer data model
├── hex_view.mbt                 # Hex dump formatting
├── hex_search.mbt               # Byte/string/hex search
├── hex_edit.mbt                 # Edit operations, patch, undo/redo primitives
├── hex_struct.mbt               # 16+ file format parser
├── hex_scan.mbt                 # CTF signature scanner (20 formats), entropy, extraction, per-format validators
├── hex_editor_test.mbt          # Tests
├── cmd/main/
│   ├── main.mbt                 # CLI + TUI entry
│   ├── helpers.mbt              # Argument parsing, file loading, type detection
│   ├── helpers_native.mbt       # Native-only helpers
│   ├── tui.mbt                  # Main loop, FFI, input helpers
│   ├── tui_key.mbt              # Key dispatch, TuiState (all modes)
│   ├── tui_bookmark.mbt         # Bookmark popup, set, jump, delete
│   ├── tui_draw.mbt             # Screen rendering (buffered, single-flush)
│   ├── tui_edit.mbt             # Edit mode, undo/redo operations
│   └── tui_stub.c               # C stubs (raw mode, alt screen, adaptive size, mmap I/O)
```

## Dependencies

- [moonbitlang/x](https://mooncakes.io/packages/moonbitlang/x) — File I/O & system APIs
- MoonBit 0.1.20260529+

## License

Apache-2.0
