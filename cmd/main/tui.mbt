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
/// Undo operation record.
struct UndoOp {
  kind : Int     // 0=modify, 1=insert, 2=delete
  offset : Int
  old_byte : Byte
} derive(Debug)

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
  let mut edit_mode = false
  let mut edit_off = 0
  let mut edit_nibble : Int? = None
  let mut edit_ascii = false
  let mut edit_modified = false
  let mut esc_pending = false
  let mut undo_stack : Array[UndoOp] = []

  tui_clear_screen()
  tui_hide_cursor()

  for _i = 0; running; _i = _i + 1 {
    // Draw
    draw_screen(buffer, offset, msg, results, result_idx, match_len, edit_mode, edit_off, edit_ascii)
    msg = ""

    let key = tui_get_key()

    if edit_mode && key == 27 {
      // Esc - exit edit mode (double-Esc if modified)
      if edit_modified && !esc_pending {
        esc_pending = true
        msg = "Unsaved edits! Press Esc again to discard, Ctrl+S to save"
      } else {
        // Undo all edits if force-exiting
        let was_modified = edit_modified
        if was_modified {
          revert_all_edits(buffer, undo_stack)
        }
        edit_mode = false
        edit_modified = false
        esc_pending = false
        undo_stack = []
        msg = if was_modified { "Edit mode off (changes discarded)" } else { "Edit mode off" }
      }

    } else if edit_mode && key == -1 {
      // Up - move cursor up one row, scroll if needed
      if edit_off >= 16 {
        edit_off = edit_off - 16
        if edit_off < offset { offset = (edit_off / 16) * 16 }
      }
      if offset < 0 { offset = 0 }

    } else if edit_mode && key == -2 {
      // Down - move cursor down, scroll if off-screen
      if edit_off + 16 < buffer.length() {
        edit_off = edit_off + 16
        let visible_end = offset + 18 * 16
        if edit_off >= visible_end { offset = ((edit_off - 17 * 16) / 16) * 16 }
      }
      if offset < 0 { offset = 0 }

    } else if edit_mode && key == -3 {
      // Left
      if edit_off > 0 {
        edit_off = edit_off - 1
        if edit_off < offset { offset = (edit_off / 16) * 16 }
      }
      if offset < 0 { offset = 0 }

    } else if edit_mode && key == -4 {
      // Right
      if edit_off + 1 < buffer.length() {
        edit_off = edit_off + 1
        let visible_end = offset + 18 * 16
        if edit_off >= visible_end { offset = ((edit_off - 17 * 16) / 16) * 16 }
      }
      if offset < 0 { offset = 0 }

    } else if edit_mode && key == 9 {
      // Tab - toggle hex/ASCII input mode
      edit_ascii = !edit_ascii
      edit_nibble = None
      msg = if edit_ascii { "ASCII input mode" } else { "Hex input mode" }

    } else if edit_mode && key == -9 {
      // Delete key
      edit_modified = true
      esc_pending = false
      let old = match buffer.get_byte(edit_off) { Some(b) => b; None => b'\x00' }
      undo_stack.push({ kind: 2, offset: edit_off, old_byte: old })
      buffer.delete_byte(edit_off) |> ignore
      if edit_off >= buffer.length() && edit_off > 0 { edit_off = edit_off - 1 }
      results = []
      match_len = 0
      msg = "Deleted 1 byte"

    } else if edit_mode && key == 'i'.to_int() {
      // Insert zero byte
      edit_modified = true
      esc_pending = false
      undo_stack.push({ kind: 1, offset: edit_off, old_byte: b'\x00' })
      buffer.insert_byte(edit_off, b'\x00') |> ignore
      msg = "Inserted 00"

    } else if edit_mode && !edit_ascii && key >= '0'.to_int() && key <= '9'.to_int() {
      // Hex mode: digit input
      edit_modified = true
      esc_pending = false
      let (new_off, new_nib, new_msg, undo) = handle_hex_input(buffer, edit_off, edit_nibble, key)
      edit_off = new_off
      edit_nibble = new_nib
      msg = new_msg
      match undo { Some(op) => undo_stack.push(op); None => () }

    } else if edit_mode && !edit_ascii && key >= 'a'.to_int() && key <= 'f'.to_int() {
      edit_modified = true
      esc_pending = false
      let (new_off, new_nib, new_msg, undo) = handle_hex_input(buffer, edit_off, edit_nibble, key)
      edit_off = new_off
      edit_nibble = new_nib
      msg = new_msg
      match undo { Some(op) => undo_stack.push(op); None => () }

    } else if edit_mode && !edit_ascii && key >= 'A'.to_int() && key <= 'F'.to_int() {
      edit_modified = true
      esc_pending = false
      let lower = key + ('a'.to_int() - 'A'.to_int())
      let (new_off, new_nib, new_msg, undo) = handle_hex_input(buffer, edit_off, edit_nibble, lower)
      edit_off = new_off
      edit_nibble = new_nib
      msg = new_msg
      match undo { Some(op) => undo_stack.push(op); None => () }

    } else if edit_mode && edit_ascii && key >= 32 && key <= 126 {
      // ASCII mode: any printable char directly sets the byte
      edit_modified = true
      esc_pending = false
      edit_nibble = None
      let old = match buffer.get_byte(edit_off) { Some(b) => b; None => b'\x00' }
      undo_stack.push({ kind: 0, offset: edit_off, old_byte: old })
      let ch = key.to_char().unwrap()
      buffer.set_byte(edit_off, ch.to_int().to_byte()) |> ignore
      msg = "Set '\{ch}' (0x\{@lib.format_byte_hex(ch.to_int().to_byte())})"
      if edit_off + 1 < buffer.length() { edit_off = edit_off + 1 }

    } else if edit_mode && key == 26 {
      // Ctrl+Z in edit mode
      if undo_stack.length() > 0 {
        let last_idx = undo_stack.length() - 1
        let op = undo_stack[last_idx]
        let new_stack = []
        for i = 0; i < last_idx; i = i + 1 { new_stack.push(undo_stack[i]) }
        undo_stack = new_stack
        if op.kind == 0 {
          buffer.set_byte(op.offset, op.old_byte) |> ignore
          msg = "Undo: restored 0x\{@lib.format_byte_hex(op.old_byte)}"
        } else if op.kind == 1 {
          buffer.delete_byte(op.offset) |> ignore
          msg = "Undo: removed insertion"
        } else {
          buffer.insert_byte(op.offset, op.old_byte) |> ignore
          msg = "Undo: restored deleted byte"
        }
        if edit_off >= buffer.length() && edit_off > 0 { edit_off = edit_off - 1 }
      } else {
        msg = "Nothing to undo"
      }

    } else if edit_mode && key == 19 {
      // Ctrl+S in edit mode
      match buffer.get_file_path() {
        Some(p) => {
          try {
            buffer.save(path=p)
            edit_modified = false
            undo_stack = []
            msg = "Saved: \{p}"
          } catch {
            @fs.IOError::IOError(m) => msg = "Save error: \{m}"
            _ => msg = "Unknown save error"
          }
        }
        None => msg = "No file path to save"
      }

    } else if edit_mode {
      // In edit mode, ignore other keys (q, etc.)
      ()

    } else if key == 'q'.to_int() || key == 'Q'.to_int() {
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

    } else if key == 'e'.to_int() {
      // Enter edit mode
      if buffer.length() > 0 {
        edit_mode = true
        edit_off = offset
        edit_nibble = None
        msg = "Entered edit mode"
      } else {
        msg = "Nothing to edit"
      }

    } else if key == 'g'.to_int() {
      // Goto (default hex input, e.g., "100" = 0x100)
      let input = tui_read_line("Goto offset (hex): ")
      if input != "" {
        let off = if string_starts_with(input, "0x") || string_starts_with(input, "0X") {
          parse_int(input)
        } else {
          parse_hex_int(input)
        }
        match off {
          Some(o) if o >= 0 && o < buffer.length() =>
            offset = (o / 16) * 16
          Some(_) => msg = "Offset out of range"
          None => msg = "Invalid offset"
        }
      }

    } else if key == '?'.to_int() || key == 'h'.to_int() {
      msg = "q:quit UD:line LR:page g:goto /:hex f:text n/N:match e:edit Home/End"
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
/// Revert all edits using the undo stack (in reverse order).
fn revert_all_edits(
  buffer : @lib.HexBuffer,
  undo_stack : Array[UndoOp],
) -> Unit {
  for i = undo_stack.length() - 1; i >= 0; i = i - 1 {
    let op = undo_stack[i]
    if op.kind == 0 {
      buffer.set_byte(op.offset, op.old_byte) |> ignore
    } else if op.kind == 1 {
      buffer.delete_byte(op.offset) |> ignore
    } else {
      buffer.insert_byte(op.offset, op.old_byte) |> ignore
    }
  }
}

///|
/// Handle hex digit input in edit mode. Returns (new_edit_off, new_nibble, msg, undo_op).
fn handle_hex_input(
  buffer : @lib.HexBuffer,
  edit_off : Int,
  edit_nibble : Int?,
  key : Int,
) -> (Int, Int?, String, UndoOp?) {
  let digit = if key >= '0'.to_int() && key <= '9'.to_int() {
    key - '0'.to_int()
  } else {
    key - 'a'.to_int() + 10
  }
  match edit_nibble {
    None => (edit_off, Some(digit), "Edit: _\{hex_digit_char(digit)}", None)
    Some(hi) => {
      let old = match buffer.get_byte(edit_off) { Some(b) => b; None => b'\x00' }
      let byte_val = ((hi << 4) | digit).to_byte()
      buffer.set_byte(edit_off, byte_val) |> ignore
      let undo = { kind: 0, offset: edit_off, old_byte: old }
      let new_off = if edit_off + 1 < buffer.length() { edit_off + 1 } else { edit_off }
      (new_off, None, "Set 0x\{@lib.format_byte_hex(byte_val)}", Some(undo))
    }
  }
}

///|
/// Format a single hex digit (0-15) as a char.
fn hex_digit_char(n : Int) -> Char {
  if n < 10 { ('0'.to_int() + n).to_char().unwrap() }
  else { ('a'.to_int() + n - 10).to_char().unwrap() }
}

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
/// Parse a hex string to integer (e.g., "100" -> 256, "FF" -> 255).
fn parse_hex_int(s : String) -> Int? {
  let len = s.length()
  guard len > 0 else { None }
  let mut result = 0
  for i = 0; i < len; i = i + 1 {
    let c = s.get_char(i).unwrap().to_int()
    let d = if c >= '0'.to_int() && c <= '9'.to_int() { c - '0'.to_int() }
    else if c >= 'A'.to_int() && c <= 'F'.to_int() { c - 'A'.to_int() + 10 }
    else if c >= 'a'.to_int() && c <= 'f'.to_int() { c - 'a'.to_int() + 10 }
    else { return None }
    result = result * 16 + d
  }
  Some(result)
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
  edit_mode : Bool,
  edit_off : Int,
  edit_ascii : Bool,
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

      // Hex bytes - edit cursor (reverse), search current (green), search other (yellow)
      for col = 0; col < 16; col = col + 1 {
        if col > 0 && col == 8 {
          raw_print(str_to_bytes(" "))
        }
        if col < row_len {
          let byte_off = row_off + col
          let byte = data[byte_off]
          let is_edit = edit_mode && byte_off == edit_off
          let is_cur = !is_edit && highlight_cur.contains(byte_off)
          let is_hl = !is_edit && !is_cur && highlight_all.contains(byte_off)
          if is_edit { raw_print(str_to_bytes("[7m")) }
          else if is_cur { raw_print(str_to_bytes("[42;30m")) }
          else if is_hl { raw_print(str_to_bytes("[43;30m")) }
          let hex = @lib.format_byte_hex(byte, uppercase=true)
          raw_print(str_to_bytes(hex))
          if is_edit || is_cur || is_hl { raw_print(str_to_bytes("[0m")) }
          raw_print(str_to_bytes(" "))
        } else {
          raw_print(str_to_bytes("   "))
        }
      }

      // ASCII column - same highlight logic
      raw_print(str_to_bytes(" |"))
      for col = 0; col < 16; col = col + 1 {
        if col < row_len {
          let byte_off = row_off + col
          let byte = data[byte_off]
          let is_edit = edit_mode && byte_off == edit_off
          let is_cur = !is_edit && highlight_cur.contains(byte_off)
          let is_hl = !is_edit && !is_cur && highlight_all.contains(byte_off)
          if is_edit { raw_print(str_to_bytes("[7m")) }
          else if is_cur { raw_print(str_to_bytes("[42;30m")) }
          else if is_hl { raw_print(str_to_bytes("[43;30m")) }
          let a = @lib.format_ascii(byte)
          let s = StringBuilder()
          s.write_char(a)
          raw_print(str_to_bytes(s.to_string()))
          if is_edit || is_cur || is_hl { raw_print(str_to_bytes("[0m")) }
        } else {
          raw_print(str_to_bytes(" "))
        }
      }
      raw_print(str_to_bytes("|\r\n"))
    }
  }

  // Clear old rows between hex dump and status bar (when display shrinks)
  raw_print(str_to_bytes("[J"))

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
  if edit_mode {
    let mode = if edit_ascii { "ASCII" } else { "Hex" }
    raw_print(str_to_bytes("[47;30m Esc:exit Tab:\{mode} i:insert Del:delete Ctrl+Z:undo Ctrl+S:save [0m\r\n"))
  } else {
    raw_print(str_to_bytes("[47;30m q:quit UD:line LR:page g:goto /:hex f:text n/N:match e:edit [0m\r\n"))
  }

}

// Helper functions load_file, parse_int, parse_hex are defined in main.mbt
