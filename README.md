# MoonBit Hex Editor

A terminal-based hex editor and binary file analyzer written in MoonBit, featuring an interactive TUI, structure parsing for 16+ file formats, search, and editing capabilities. Runs on Windows and Linux.

## Features

### Interactive TUI
- Hex dump with offset column, 16 bytes/row, and ASCII sidebar
- Navigation: Arrow keys (`↑↓` line scroll, `←→` page), Home/End, Goto offset
- Search: `/` hex pattern, `f` ASCII text, `n`/`N` next/prev match
- Highlighting: current match (green), other matches (yellow), edit cursor (inverse)
- Edit mode: hex/ASCII input, insert, delete, undo/redo (`Ctrl+Z`/`Ctrl+Y`) with depth display, smart save prompt
- Structure view: parsed file structure with scrollable display
- Display: adaptive rows fill the terminal, file info on open, status bar + help bar

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
| `g` | Goto offset | `i` | Insert byte |
| `/` | Hex search | `Del` | Delete byte |
| `f` | Text search | `Ctrl+Z` | Undo |
| `n/N` | Next/prev match | `Ctrl+Y` | Redo |
| `e` | Edit mode | `Ctrl+S` | Save |
| `t` | Struct view | | |

Struct view: `↑↓←→` scroll, `t` back to hex, `q` quit.

### Platform Notes

| Platform | Details |
|----------|---------|
| Windows | conio + ENABLE_VIRTUAL_TERMINAL_PROCESSING, alternate screen buffer |
| Linux | termios persistent raw mode, signal-safe restore, alt screen, direct `write()` |

## Project Structure

```
hex_editor/
├── hex_editor.mbt / hex_view.mbt / hex_search.mbt / hex_edit.mbt / hex_struct.mbt
├── hex_editor_test.mbt           # Tests
├── cmd/main/
│   ├── main.mbt                  # CLI + TUI entry
│   ├── helpers.mbt / helpers_native.mbt  # Shared utilities
│   ├── tui.mbt                   # TUI main loop & input
│   ├── tui_draw.mbt              # Screen rendering (buffered, single-flush)
│   ├── tui_edit.mbt              # Edit mode, undo/redo
│   └── tui_stub.c                # C terminal stubs (raw mode, alt screen, adaptive size)
```

## Dependencies

- [moonbitlang/x](https://mooncakes.io/packages/moonbitlang/x) — File I/O & system APIs
- MoonBit 0.1.20260529+

## License

Apache-2.0
