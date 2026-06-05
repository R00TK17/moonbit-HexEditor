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
  let mut bpr = 16
  let mut ascii = true
  let mut upper = true
  let mut msg = ""
  let mut results : Array[Int] = []
  let mut result_idx = 0
  let mut running = true

  tui_clear_screen()
  tui_hide_cursor()

  for _i = 0; running; _i = _i + 1 {
    // Draw
    draw_screen(buffer, offset, bpr, ascii, upper, msg, results, result_idx)
    msg = ""

    let key = tui_get_key()

    if key == 'q'.to_int() || key == 'Q'.to_int() {
      running = false

    } else if key == -1 {
      // Up
      if offset >= bpr { offset = offset - bpr }

    } else if key == -2 {
      // Down
      let rows = buffer.length() / bpr
      if offset + bpr < rows * bpr { offset = offset + bpr }

    } else if key == -4 {
      // Right = PgDn
      let page = bpr * 16
      if offset + page < buffer.length() { offset = offset + page }

    } else if key == -3 {
      // Left = PgUp
      let page = bpr * 16
      if offset >= page { offset = offset - page } else { offset = 0 }

    } else if key == -5 {
      // PgUp
      let page = bpr * 16
      if offset >= page { offset = offset - page } else { offset = 0 }

    } else if key == -6 {
      // PgDn
      let page = bpr * 16
      if offset + page < buffer.length() { offset = offset + page }

    } else if key == -7 {
      // Home
      offset = 0

    } else if key == -8 {
      // End
      let rows = buffer.length() / bpr
      offset = rows * bpr

    } else if key == '/'.to_int() {
      // Search
      let pattern = tui_read_line("Search: ")
      if pattern != "" {
        match do_search(buffer, pattern) {
          (found, _idx) => {
            if found.length() > 0 {
              msg = "Found \{found.length()} matches"
              results = found
              result_idx = 0
              offset = found[0]
            } else {
              msg = "Not found"
            }
          }
        }
      }

    } else if key == 'n'.to_int() {
      // Next search result
      if results.length() > 0 {
        result_idx = (result_idx + 1) % results.length()
        offset = results[result_idx]
      }

    } else if key == 'N'.to_int() {
      // Prev search result
      if results.length() > 0 {
        result_idx = if result_idx > 0 { result_idx - 1 } else { results.length() - 1 }
        offset = results[result_idx]
      }

    } else if key == 'g'.to_int() {
      // Goto
      let input = tui_read_line("Goto offset: ")
      if input != "" {
        match parse_int(input) {
          Some(off) if off >= 0 && off < buffer.length() =>
            offset = (off / bpr) * bpr
          Some(_) => msg = "Offset out of range"
          None => msg = "Invalid offset"
        }
      }

    } else if key == 'o'.to_int() {
      // Open
      let _path = tui_read_line("Open file: ")
      msg = "File open not supported in TUI yet, use CLI."

    } else if key == 'b'.to_int() {
      // Toggle bytes per row
      bpr = if bpr == 16 { 8 } else { 16 }
      msg = "Bytes per row: \{bpr}"

    } else if key == 'a'.to_int() {
      // Toggle ASCII column
      ascii = !ascii
      msg = if ascii { "ASCII column on" } else { "ASCII column off" }

    } else if key == 'u'.to_int() {
      // Toggle uppercase
      upper = !upper
      msg = if upper { "Uppercase on" } else { "Uppercase off" }

    } else if key == '?'.to_int() || key == 'h'.to_int() {
      msg = "q:quit arrows/PgUp/Dn:nav g:goto /:search n:next o:open b:8/16 a:ascii u:case"
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
fn do_search(buffer : @lib.HexBuffer, pattern_str : String) -> (Array[Int], Int) {
  let data = buffer.to_bytes()
  let hex_parsed = @lib.parse_hex_string(pattern_str)
  let search_bytes = match hex_parsed {
    Some(bytes) => bytes
    None => {
      Bytes::makei(pattern_str.length(), i => {
        let ch = pattern_str.get_char(i).unwrap()
        let code = ch.to_int()
        if code >= 0 && code <= 127 { code.to_byte() } else { b'?' }
      })
    }
  }
  let found = @lib.find_all_bytes(data, search_bytes)
  (found, 0)
}

///|
/// Draw the TUI screen.
fn draw_screen(
  buffer : @lib.HexBuffer,
  offset : Int,
  bpr : Int,
  show_ascii : Bool,
  uppercase : Bool,
  status_msg : String,
  search_results : Array[Int],
  search_idx : Int,
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
  raw_print(str_to_bytes("[44;37m \{info} [0m\r\n"))

  if buffer.is_empty() {
    raw_print(str_to_bytes("\r\n  [Empty]  o:open  q:quit\r\n"))
  } else {
    let len = buffer.length()
    let screen_rows = 18
    let max_row = (len + bpr - 1) / bpr
    let display_rows = if screen_rows < max_row { screen_rows } else { max_row }

    // Build highlight set from current search result
    let highlight : Array[Int] = if search_results.length() > 0 && search_idx >= 0 && search_idx < search_results.length() {
      [search_results[search_idx]]
    } else { [] }

    let data = buffer.to_fixedarray()

    for row = 0; row < display_rows; row = row + 1 {
      let row_off = offset + row * bpr
      if row_off >= len {
        break
      }
      let row_len = if row_off + bpr <= len { bpr } else { len - row_off }

      // Offset
      let off_str = @lib.format_offset(row_off)
      raw_print(str_to_bytes("[34m\{off_str}[0m  "))

      // Hex bytes
      for col = 0; col < bpr; col = col + 1 {
        if col > 0 && col == bpr / 2 {
          raw_print(str_to_bytes(" "))
        }
        if col < row_len {
          let byte_off = row_off + col
          let byte = data[byte_off]
          let hl = highlight.length() > 0 && highlight[0] == byte_off
          if hl {
            raw_print(str_to_bytes("[43;30m"))
          }
          let hex = @lib.format_byte_hex(byte, uppercase=uppercase)
          raw_print(str_to_bytes(hex))
          if hl {
            raw_print(str_to_bytes("[0m"))
          }
          raw_print(str_to_bytes(" "))
        } else {
          raw_print(str_to_bytes("   "))
        }
      }

      // ASCII
      if show_ascii {
        raw_print(str_to_bytes(" |"))
        for col = 0; col < bpr; col = col + 1 {
          if col < row_len {
            let byte_off = row_off + col
            let byte = data[byte_off]
            let hl = highlight.length() > 0 && highlight[0] == byte_off
            if hl {
              raw_print(str_to_bytes("[43;30m"))
            }
            let a = @lib.format_ascii(byte)
            let s = StringBuilder()
            s.write_char(a)
            raw_print(str_to_bytes(s.to_string()))
            if hl {
              raw_print(str_to_bytes("[0m"))
            }
          } else {
            raw_print(str_to_bytes(" "))
          }
        }
        raw_print(str_to_bytes("|"))
      }
      raw_print(str_to_bytes("\r\n"))
    }
  }

  // Bottom bar
  let cur_row = if buffer.length() > 0 { offset / bpr + 1 } else { 0 }
  let max_row = if buffer.length() > 0 { (buffer.length() + bpr - 1) / bpr } else { 0 }
  let bot = "[44;37m 0x\{@lib.to_hex_string(offset, width=8)} | row \{cur_row}/\{max_row} | \{bpr}b/row [0m"
  raw_print(str_to_bytes(bot))

  if status_msg != "" {
    let m = " [41;37m \{status_msg} [0m"
    raw_print(str_to_bytes(m))
  }
  raw_print(str_to_bytes("\r\n"))

  // Help line
  raw_print(str_to_bytes("[47;30m q:quit UD:scroll PgUp/Dn:page g:goto /:search n/N:match o:open a:ascii b:8/16 [0m\r\n"))
}

// Helper functions load_file, parse_int, parse_hex are defined in main.mbt
