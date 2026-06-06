// TUI Module — Terminal UI for interactive hex viewing (native only)

///|
/// FFI declarations
extern "C" fn tui_get_key() -> Int = "tui_get_key"
extern "C" fn tui_clear_screen() -> Unit = "tui_clear_screen"
extern "C" fn tui_goto(row : Int, col : Int) -> Unit = "tui_goto"
extern "C" fn tui_hide_cursor() -> Unit = "tui_hide_cursor"
extern "C" fn tui_show_cursor() -> Unit = "tui_show_cursor"
#borrow(_s)
extern "C" fn raw_print(_s : Bytes) -> Unit = "raw_print"

///|
/// Main TUI entry point. Called from main.mbt.
pub fn run_tui(file_path : String?) -> Unit {
  // Load initial file
  let buffer = match file_path {
    Some(p) => match load_file(p) { Ok(b) => b; Err(_) => @lib.HexBuffer::new() }
    None => @lib.HexBuffer::new()
  }

  let mut offset = 0
  let mut msg = ""
  let mut results : Array[Int] = []
  let mut result_idx = 0
  let mut match_len = 0
  let mut running = true

  tui_clear_screen()
  tui_hide_cursor()

  for _i = 0; running; _i = _i + 1 {
    // Draw (pass results for highlighting)
    draw_screen(buffer, offset, msg, results, result_idx, match_len)
    msg = ""

    let key = tui_get_key()

    if key == 'q'.to_int() || key == 'Q'.to_int() {
      running = false

    } else if key == -1 {
      // Up - scroll one line
      if offset >= 16 { offset = offset - 16 }

    } else if key == -2 {
      // Down - scroll one line
      let rows = buffer.length() / 16
      if offset + 16 < rows * 16 { offset = offset + 16 }

    } else if key == -3 {
      // Left = Page Up
      let page = 256
      if offset >= page { offset = offset - page } else { offset = 0 }

    } else if key == -4 {
      // Right = Page Down
      let page = 256
      if offset + page < buffer.length() { offset = offset + page }

    } else if key == -7 {
      // Home
      offset = 0

    } else if key == -8 {
      // End
      let rows = buffer.length() / 16
      offset = rows * 16

    } else if key == '/'.to_int() {
      // Hex search
      let pattern = tui_read_line("Hex search: ")
      if pattern != "" {
        match @lib.parse_hex_string(pattern) {
          Some(bytes) => {
            let data = buffer.to_bytes()
            results = @lib.find_all_bytes(data, bytes)
            if results.length() > 0 {
              result_idx = 0
              match_len = bytes.length()
              msg = "Hex: \{results.length()} matches (n:next)"
            } else {
              msg = "Not found"
              results = []
              match_len = 0
            }
          }
          None => msg = "Invalid hex (FF D8 or FF00)"
        }
      }

    } else if key == 'f'.to_int() {
      // Text search
      let pattern = tui_read_line("Text search: ")
      if pattern != "" {
        let bytes = ascii_to_bytes(pattern)
        match_len = bytes.length()
        let data = buffer.to_bytes()
        results = @lib.find_all_bytes(data, bytes)
        if results.length() > 0 {
          result_idx = 0
          msg = "Text: \{results.length()} matches (n:next)"
        } else {
          msg = "Not found"
          results = []
          match_len = 0
        }
      }

    } else if key == 'n'.to_int() {
      // Next match
      let total = results.length()
      if total > 0 {
        result_idx = result_idx + 1
        if result_idx >= total { result_idx = 0 }
        // Scroll just enough to show match near middle of screen
        offset = scroll_to_show(results[result_idx], offset, buffer.length())
        msg = "Match \{result_idx + 1}/\{total}"
      }

    } else if key == 'N'.to_int() {
      // Previous match
      let total = results.length()
      if total > 0 {
        result_idx = result_idx - 1
        if result_idx < 0 { result_idx = total - 1 }
        offset = scroll_to_show(results[result_idx], offset, buffer.length())
        msg = "Match \{result_idx + 1}/\{total}"
      }

    } else if key == 'g'.to_int() {
      // Goto
      let input = tui_read_line("Goto offset: ")
      if input != "" {
        match parse_int(input) {
          Some(off) if off >= 0 && off < buffer.length() =>
            offset = (off / 16) * 16
          Some(_) => msg = "Offset out of range"
          None => msg = "Invalid offset"
        }
      }

    } else if key == '?'.to_int() || key == 'h'.to_int() {
      msg = "q:quit UD:line LR:page g:goto /:hex f:text n/N:match Home/End"
    }
  }

  tui_show_cursor()
  tui_clear_screen()
}

///|
/// Read a line of input from the user with a prompt.
fn tui_read_line(prompt : String) -> String {
  tui_show_cursor()
  let msg_bytes = str_to_bytes(prompt)
  raw_print(msg_bytes)

  let mut sb = StringBuilder()
  let mut done = false
  for _i = 0; !done; _i = _i + 1 {
    let key = tui_get_key()
    if key == 13 || key == 10 {
      done = true
    } else if key == 27 {
      // ESC cancels
      tui_hide_cursor()
      return ""
    } else if key == 8 || key == 127 {
      // Backspace
      let s = sb.to_string()
      if s.length() > 0 {
        let new_s = s[:s.length() - 1].to_string()
        sb = StringBuilder()
        sb.write_string(new_s)
        raw_print(b"\b \b")
      }
    } else if key >= 32 && key < 127 {
      let ch = key.to_char()
      match ch {
        Some(c) => {
          sb.write_char(c)
          // Echo the character
          let cs = StringBuilder()
          cs.write_char(c)
          let bs = str_to_bytes(cs.to_string())
          raw_print(bs)
        }
        None => ()
      }
    }
  }

  tui_hide_cursor()
  sb.to_string()
}

///|
/// Convert string to UTF-8 bytes for FFI printing.
fn str_to_bytes(s : String) -> Bytes {
  let buf = Buffer(size_hint=s.length() * 4)
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s.get_char(i).unwrap()
    buf.write_char_utf8(ch)
  }
  buf.write_byte(b'\x00') // null terminator for C
  buf.to_bytes()
}

///|
/// Perform a search.
///|
/// Build a set of offsets to highlight from all search results.
fn build_highlight_set(
  results : Array[Int],
  match_len : Int,
  buffer : @lib.HexBuffer,
) -> Array[Int] {
  if results.length() == 0 || match_len <= 0 {
    return []
  }
  let set = []
  for i = 0; i < results.length(); i = i + 1 {
    let off = results[i]
    for j = 0; j < match_len; j = j + 1 {
      if off + j < buffer.length() {
        set.push(off + j)
      }
    }
  }
  set
}

///|
/// Build highlight offsets for a single match (current selection).
fn build_match_range(
  match_offset : Int,
  match_len : Int,
  buffer : @lib.HexBuffer,
) -> Array[Int] {
  if match_len <= 0 || match_offset < 0 || match_offset >= buffer.length() {
    return []
  }
  let set = []
  for j = 0; j < match_len; j = j + 1 {
    if match_offset + j < buffer.length() {
      set.push(match_offset + j)
    }
  }
  set
}

///|
/// Draw the TUI screen.
///|
/// Calculate offset to show target. Only scrolls if target is off-screen.
fn scroll_to_show(target : Int, current_offset : Int, total_len : Int) -> Int {
  let visible_rows = 18
  let visible_bytes = visible_rows * 16
  let view_end = current_offset + visible_bytes

  // Already visible? Don't scroll
  if target >= current_offset && target < view_end {
    return current_offset
  }

  // Scroll to put target at middle of screen
  let middle = visible_rows / 2
  let ideal = target - middle * 16
  if ideal < 0 { 0 }
  else if ideal + visible_bytes > total_len {
    let max = total_len - visible_bytes
    if max < 0 { 0 } else { max }
  }
  else { (ideal / 16) * 16 }
}

///|
/// Convert ASCII string to bytes for text search.
fn ascii_to_bytes(s : String) -> Bytes {
  Bytes::makei(s.length(), i => {
    let ch = s.get_char(i).unwrap()
    let code = ch.to_int()
    if code >= 0 && code <= 127 { code.to_byte() } else { b'?' }
  })
}

fn draw_screen(
  buffer : @lib.HexBuffer,
  offset : Int,
  status_msg : String,
  search_results : Array[Int],
  search_idx : Int,
  match_len : Int,
) -> Unit {
  // Move cursor to home without clearing (avoids flicker)
  // \033[H = cursor home
  raw_print(str_to_bytes("[H"))

  // Top bar
  let info = if buffer.is_empty() {
    "<empty>"
  } else {
    let path = match buffer.get_file_path() {
      Some(p) => p
      None => "<no file>"
    }
    "\{path} | \{@lib.format_size(buffer.length())}"
  }
  raw_print(str_to_bytes("[44;37m \{info} [0m[K\r\n"))

  if buffer.is_empty() {
    raw_print(str_to_bytes("\r\n  [Empty]  o:open  q:quit[K\r\n"))
  } else {
    let len = buffer.length()
    let screen_rows = 18
    let max_row = (len + 15) / 16
    let display_rows = if screen_rows < max_row { screen_rows } else { max_row }

    let data = buffer.to_fixedarray()

    // Build highlight sets
    let highlight_all = build_highlight_set(search_results, match_len, buffer)
    let highlight_cur : Array[Int] = if search_results.length() > 0 && search_idx >= 0 && search_idx < search_results.length() {
      build_match_range(search_results[search_idx], match_len, buffer)
    } else { [] }

    for row = 0; row < display_rows; row = row + 1 {
      let row_off = offset + row * 16
      if row_off >= len {
        break
      }
      let row_len = if row_off + 16 <= len { 16 } else { len - row_off }

      // Offset
      let off_str = @lib.format_offset(row_off)
      raw_print(str_to_bytes("[34m\{off_str}[0m  "))

      // Hex bytes - with color: current=green, other=yellow
      for col = 0; col < 16; col = col + 1 {
        if col > 0 && col == 8 {
          raw_print(str_to_bytes(" "))
        }
        if col < row_len {
          let byte_off = row_off + col
          let byte = data[byte_off]
          let is_cur = highlight_cur.contains(byte_off)
          let is_hl = highlight_all.contains(byte_off) && !is_cur
          if is_cur { raw_print(str_to_bytes("[42;30m")) }
          else if is_hl { raw_print(str_to_bytes("[43;30m")) }
          let hex = @lib.format_byte_hex(byte, uppercase=true)
          raw_print(str_to_bytes(hex))
          if is_cur || is_hl { raw_print(str_to_bytes("[0m")) }
          raw_print(str_to_bytes(" "))
        } else {
          raw_print(str_to_bytes("   "))
        }
      }

      // ASCII column - with same color logic
      raw_print(str_to_bytes(" |"))
      for col = 0; col < 16; col = col + 1 {
        if col < row_len {
          let byte_off = row_off + col
          let byte = data[byte_off]
          let is_cur = highlight_cur.contains(byte_off)
          let is_hl = highlight_all.contains(byte_off) && !is_cur
          if is_cur { raw_print(str_to_bytes("[42;30m")) }
          else if is_hl { raw_print(str_to_bytes("[43;30m")) }
          let a = @lib.format_ascii(byte)
          let s = StringBuilder()
          s.write_char(a)
          raw_print(str_to_bytes(s.to_string()))
          if is_cur || is_hl { raw_print(str_to_bytes("[0m")) }
        } else {
          raw_print(str_to_bytes(" "))
        }
      }
      raw_print(str_to_bytes("|\r\n"))
    }
  }

  // Bottom bar
  let cur_row = if buffer.length() > 0 { offset / 16 + 1 } else { 0 }
  let max_row = if buffer.length() > 0 { (buffer.length() + 15) / 16 } else { 0 }
  let bot = "[44;37m 0x\{@lib.to_hex_string(offset, width=8)} | row \{cur_row}/\{max_row} [0m"
  raw_print(str_to_bytes(bot))

  if status_msg != "" {
    let m = " [41;37m \{status_msg} [0m"
    raw_print(str_to_bytes(m))
  }
  // Erase residual chars when message gets shorter
  raw_print(str_to_bytes("[K\r\n"))

  // Help line
  raw_print(str_to_bytes("[47;30m q:quit UD:line LR:page g:goto /:hex f:text n/N:match Home/End [0m\r\n"))

  // Clear any leftover content below (prevents ghosting when display shrinks)
  raw_print(str_to_bytes("[J"))
}

// Helper functions load_file, parse_int, parse_hex are defined in main.mbt
