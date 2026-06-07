# MoonBit Hex Editor

A terminal-based hex editor and binary file analyzer written in MoonBit, featuring an interactive TUI, structure parsing for 16+ file formats, search, and editing capabilities.

## Features

### Interactive TUI
- Hex dump with offset, 16 bytes/row, and ASCII sidebar
- Navigation: Arrow keys scroll line/page, Home/End, Goto offset
- Search: `/` hex pattern, `f` ASCII text, `n`/`N` next/prev match
- Highlighting: current match (green), other matches (yellow), edit cursor (inverse)
- Edit mode: hex/ASCII input, insert, delete, undo (Ctrl+Z), save (Ctrl+S)
- Structure view: parsed file structure with scrollable display

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
# Build (native for TUI, wasm for CLI only)
moon build --target native
moon build

# Run tests
moon test

# Start TUI
moon run --target native cmd/main -- file.jpg
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
| `n/N` | Next/prev match | `Ctrl+S` | Save |
| `e` | Edit mode | | |
| `t` | Struct view | | |

Struct view: `↑↓←→` scroll, `t` back to hex, `q` quit.

## Project Structure

```
hex_editor/
├── hex_editor.mbt / hex_view.mbt / hex_search.mbt / hex_edit.mbt / hex_struct.mbt
├── hex_editor_test.mbt           # Tests
├── cmd/main/
│   ├── main.mbt / main_wasm.mbt  # CLI entries
│   ├── helpers.mbt               # Shared utilities
│   ├── tui.mbt / tui_draw.mbt / tui_edit.mbt  # TUI
│   └── tui_stub.c                # C terminal stubs
```

## Dependencies

- [moonbitlang/x](https://mooncakes.io/packages/moonbitlang/x) — File I/O & system APIs
- MoonBit 0.1.20260529+

## License

Apache-2.0
