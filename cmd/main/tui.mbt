// TUI Module — Terminal UI for interactive hex viewing (native only)
// Main loop, FFI, and input helpers.
// Rendering: tui_draw.mbt  |  Edit logic: tui_edit.mbt  |  Key handling: tui_key.mbt

///|
/// FFI declarations
extern "C" fn tui_get_key() -> Int = "tui_get_key"
extern "C" fn tui_clear_screen() -> Unit = "tui_clear_screen"
extern "C" fn tui_hide_cursor() -> Unit = "tui_hide_cursor"
extern "C" fn tui_show_cursor() -> Unit = "tui_show_cursor"
extern "C" fn tui_enter_raw() -> Unit = "tui_enter_raw"
extern "C" fn tui_exit_raw() -> Unit = "tui_exit_raw"
extern "C" fn tui_enter_alt_screen() -> Unit = "tui_enter_alt_screen"
extern "C" fn tui_exit_alt_screen() -> Unit = "tui_exit_alt_screen"
extern "C" fn tui_get_terminal_rows() -> Int = "tui_get_terminal_rows"
extern "C" fn tui_get_terminal_cols() -> Int = "tui_get_terminal_cols"
#borrow(_path)
extern "C" fn mmap_file_size(_path : Bytes) -> Int = "mmap_file_size"
#borrow(_path, _buf)
extern "C" fn mmap_load(_path : Bytes, _buf : Bytes) -> Int = "mmap_load"
#borrow(_s)
extern "C" fn raw_print(_s : Bytes) -> Unit = "raw_print"

///|
/// Convert string to UTF-8 bytes for FFI printing.
fn str_to_bytes(s : String) -> Bytes {
  let buf = Buffer(size_hint=s.length() * 4)
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s.get_char(i).unwrap()
    buf.write_char_utf8(ch)
  }
  buf.write_byte(b'\x00')
  buf.to_bytes()
}

///|
/// Read a line of input from the user with a prompt.
fn tui_read_line(prompt : String) -> String {
  tui_show_cursor()
  // Move cursor up from help bar to status bar line, position at ASCII column
  raw_print(str_to_bytes("[2A[63G[K"))
  raw_print(str_to_bytes(prompt))

  let mut sb = StringBuilder()
  let mut done = false
  for _i = 0; !done; _i = _i + 1 {
    let key = tui_get_key()
    if key == 13 || key == 10 {
      done = true
    } else if key == 27 {
      tui_hide_cursor()
      return ""
    } else if key == 8 || key == 127 {
      let s = sb.to_string()
      if s.length() > 0 {
        let new_s = s[:s.length() - 1].to_owned()
        sb = StringBuilder()
        sb.write_string(new_s)
        raw_print(b"\b \b")
      }
    } else if key >= 32 && key < 127 {
      let ch = key.to_char()
      match ch {
        Some(c) => {
          sb.write_char(c)
          let cs = StringBuilder()
          cs.write_char(c)
          raw_print(str_to_bytes(cs.to_string()))
        }
        None => ()
      }
    }
  }
  tui_hide_cursor()
  sb.to_string()
}

///|
/// Load file via mmap (fast path). Falls back to regular load on failure.
fn load_file_best(path : String) -> Result[@lib.HexBuffer, String] {
  if !@fs.path_exists(path) { return Err("Not found: \{path}") }
  let c_path = str_to_bytes(path)
  let size = mmap_file_size(c_path)
  if size > 0 {
    let buf = Bytes::make(size, b'\x00')
    let loaded = mmap_load(c_path, buf)
    if loaded > 0 {
      let hb = @lib.HexBuffer::from_bytes(buf)
      hb.set_file_path(path)
      return Ok(hb)
    }
  }
  load_file(path)
}

///|
/// Main TUI entry point. Called from main.mbt.
pub fn run_tui(file_path : String?) -> Unit {
  let mut buffer = match file_path {
    Some(p) => match load_file_best(p) { Ok(b) => b; Err(_) => @lib.HexBuffer::new() }
    None => @lib.HexBuffer::new()
  }

  let state = TuiState::new(file_path, buffer)

  tui_enter_raw()
  tui_enter_alt_screen()
  tui_clear_screen()
  tui_hide_cursor()

  for _i = 0; state.running; _i = _i + 1 {
    let term_rows = tui_get_terminal_rows()
    let term_cols = tui_get_terminal_cols()
    let screen_rows = if term_rows > 6 { term_rows - 3 } else { 32 }
    draw_screen(buffer, state.offset, state.msg, state.results, state.result_idx, state.match_len, state.edit_mode, state.edit_off, state.edit_ascii, state.struct_view, state.struct_offset, state.bookmark_view, state.bookmark_sel, state.bookmark_scroll, state.bookmarks, state.scan_view, state.scan_sel, state.scan_scroll, state.scan_offsets, state.scan_names, state.scan_sizes, state.entropy_view, state.entropy_sel, state.entropy_blocks, state.strings_view, state.strings_sel, state.strings_scroll, state.strings_matches, screen_rows, term_cols)

    let key = tui_get_key()

    // o/O: open file — handled here to reload buffer
    if !state.edit_mode && !state.struct_view && !state.bookmark_view && !state.strings_view && (key == 'o'.to_int() || key == 'O'.to_int()) {
      let path = tui_read_line("Open file: ")
      if path != "" {
        match load_file_best(path) {
          Ok(b) => {
            buffer = b
            state.offset = 0
            state.msg = "\{path} | \{@lib.format_size(buffer.length())}"
            state.edit_mode = false
            state.struct_view = false
            state.bookmark_view = false
            state.scan_done = false
            state.strings_done = false
            state.entropy_done = false
            state.undo_stack = []
            state.redo_stack = []
          }
          Err(m) => state.msg = "Error: \{m}"
        }
      }
    } else {
      handle_key(state, buffer, key, screen_rows)
    }
  }

  tui_show_cursor()
  tui_exit_alt_screen()
  tui_exit_raw()
}

///|
/// Calculate offset to show target. Only scrolls if target is off-screen.
fn scroll_to_show(target : Int, current_offset : Int, total_len : Int, screen_rows : Int) -> Int {
  let visible_bytes = screen_rows * 16
  let view_end = current_offset + visible_bytes
  if target >= current_offset && target < view_end { return current_offset }
  let middle = screen_rows / 2
  let ideal = target - middle * 16
  if ideal < 0 { 0 }
  else if ideal + visible_bytes > total_len {
    let max = total_len - visible_bytes
    if max < 0 { 0 } else { max }
  }
  else { (ideal / 16) * 16 }
}

///|
/// Get total lines and max scroll offset for struct view.
fn get_struct_info(buffer : @lib.HexBuffer) -> (Int, Int) {
  let bytes = buffer.to_bytes()
  let fields = @lib.parse_structure(bytes)
  guard fields.length() > 0 else { (0, 0) }
  let text = @lib.format_structure(fields)
  let lines = split_text_lines(text)
  let total = lines.length()
  (total, if total > 0 { total - 1 } else { 0 })
}
