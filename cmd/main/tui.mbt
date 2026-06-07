// TUI Module — Terminal UI for interactive hex viewing (native only)
// Main loop, FFI, and input helpers. Rendering in tui_draw.mbt, edit logic in tui_edit.mbt.

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
/// Main TUI entry point. Called from main.mbt.
pub fn run_tui(file_path : String?) -> Unit {
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
    draw_screen(buffer, offset, msg, results, result_idx, match_len, edit_mode, edit_off, edit_ascii)
    msg = ""

    let key = tui_get_key()

    // ====== Edit mode keys ======
    if edit_mode && key == 27 {
      if edit_modified && !esc_pending {
        esc_pending = true
        msg = "Unsaved edits! Press Esc again to discard, Ctrl+S to save"
      } else {
        let was_modified = edit_modified
        if was_modified { revert_all_edits(buffer, undo_stack) }
        edit_mode = false
        edit_modified = false
        esc_pending = false
        undo_stack = []
        msg = if was_modified { "Edit mode off (changes discarded)" } else { "Edit mode off" }
      }

    } else if edit_mode && key == -1 {
      if edit_off >= 16 { edit_off = edit_off - 16 }
      if edit_off < offset { offset = (edit_off / 16) * 16 }
      if offset < 0 { offset = 0 }

    } else if edit_mode && key == -2 {
      if edit_off + 16 < buffer.length() { edit_off = edit_off + 16 }
      let visible_end = offset + 18 * 16
      if edit_off >= visible_end { offset = ((edit_off - 17 * 16) / 16) * 16 }
      if offset < 0 { offset = 0 }

    } else if edit_mode && key == -3 {
      if edit_off > 0 { edit_off = edit_off - 1 }
      if edit_off < offset { offset = (edit_off / 16) * 16 }
      if offset < 0 { offset = 0 }

    } else if edit_mode && key == -4 {
      if edit_off + 1 < buffer.length() { edit_off = edit_off + 1 }
      let visible_end = offset + 18 * 16
      if edit_off >= visible_end { offset = ((edit_off - 17 * 16) / 16) * 16 }
      if offset < 0 { offset = 0 }

    } else if edit_mode && key == 9 {
      edit_ascii = !edit_ascii
      edit_nibble = None
      msg = if edit_ascii { "ASCII input mode" } else { "Hex input mode" }

    } else if edit_mode && key == -9 {
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
      edit_modified = true
      esc_pending = false
      undo_stack.push({ kind: 1, offset: edit_off, old_byte: b'\x00' })
      buffer.insert_byte(edit_off, b'\x00') |> ignore
      msg = "Inserted 00"

    } else if edit_mode && !edit_ascii && key >= '0'.to_int() && key <= '9'.to_int() {
      edit_modified = true; esc_pending = false
      let (new_off, new_nib, new_msg, undo) = handle_hex_input(buffer, edit_off, edit_nibble, key)
      edit_off = new_off; edit_nibble = new_nib; msg = new_msg
      match undo { Some(op) => undo_stack.push(op); None => () }

    } else if edit_mode && !edit_ascii && key >= 'a'.to_int() && key <= 'f'.to_int() {
      edit_modified = true; esc_pending = false
      let (new_off, new_nib, new_msg, undo) = handle_hex_input(buffer, edit_off, edit_nibble, key)
      edit_off = new_off; edit_nibble = new_nib; msg = new_msg
      match undo { Some(op) => undo_stack.push(op); None => () }

    } else if edit_mode && !edit_ascii && key >= 'A'.to_int() && key <= 'F'.to_int() {
      edit_modified = true; esc_pending = false
      let lower = key + ('a'.to_int() - 'A'.to_int())
      let (new_off, new_nib, new_msg, undo) = handle_hex_input(buffer, edit_off, edit_nibble, lower)
      edit_off = new_off; edit_nibble = new_nib; msg = new_msg
      match undo { Some(op) => undo_stack.push(op); None => () }

    } else if edit_mode && edit_ascii && key >= 32 && key <= 126 {
      edit_modified = true; esc_pending = false; edit_nibble = None
      let old = match buffer.get_byte(edit_off) { Some(b) => b; None => b'\x00' }
      undo_stack.push({ kind: 0, offset: edit_off, old_byte: old })
      let ch = key.to_char().unwrap()
      buffer.set_byte(edit_off, ch.to_int().to_byte()) |> ignore
      msg = "Set '\{ch}' (0x\{@lib.format_byte_hex(ch.to_int().to_byte())})"
      if edit_off + 1 < buffer.length() { edit_off = edit_off + 1 }

    } else if edit_mode && key == 26 {
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
      } else { msg = "Nothing to undo" }

    } else if edit_mode && key == 19 {
      match buffer.get_file_path() {
        Some(p) => {
          try {
            buffer.save(path=p)
            edit_modified = false; undo_stack = []; msg = "Saved: \{p}"
          } catch {
            @fs.IOError::IOError(m) => msg = "Save error: \{m}"
            _ => msg = "Unknown save error"
          }
        }
        None => msg = "No file path to save"
      }

    } else if edit_mode {
      ()

    // ====== Normal mode keys ======
    } else if key == 'q'.to_int() || key == 'Q'.to_int() {
      running = false

    } else if key == -1 {
      if offset >= 16 { offset = offset - 16 }

    } else if key == -2 {
      let rows = buffer.length() / 16
      if offset + 16 < rows * 16 { offset = offset + 16 }

    } else if key == -3 {
      let page = 256
      if offset >= page { offset = offset - page } else { offset = 0 }

    } else if key == -4 {
      let page = 256
      if offset + page < buffer.length() { offset = offset + page }

    } else if key == -7 {
      offset = 0

    } else if key == -8 {
      let rows = buffer.length() / 16
      offset = rows * 16

    } else if key == '/'.to_int() {
      let pattern = tui_read_line("Hex search: ")
      if pattern != "" {
        match @lib.parse_hex_string(pattern) {
          Some(bytes) => {
            let data = buffer.to_bytes()
            results = @lib.find_all_bytes(data, bytes)
            if results.length() > 0 {
              result_idx = 0; match_len = bytes.length()
              msg = "Hex: \{results.length()} matches (n:next)"
            } else { msg = "Not found"; results = []; match_len = 0 }
          }
          None => msg = "Invalid hex (FF D8 or FF00)"
        }
      }

    } else if key == 'f'.to_int() {
      let pattern = tui_read_line("Text search: ")
      if pattern != "" {
        let bytes = ascii_to_bytes(pattern)
        match_len = bytes.length()
        let data = buffer.to_bytes()
        results = @lib.find_all_bytes(data, bytes)
        if results.length() > 0 {
          result_idx = 0
          msg = "Text: \{results.length()} matches (n:next)"
        } else { msg = "Not found"; results = []; match_len = 0 }
      }

    } else if key == 'n'.to_int() {
      let total = results.length()
      if total > 0 {
        result_idx = result_idx + 1
        if result_idx >= total { result_idx = 0 }
        offset = scroll_to_show(results[result_idx], offset, buffer.length())
        msg = "Match \{result_idx + 1}/\{total}"
      }

    } else if key == 'N'.to_int() {
      let total = results.length()
      if total > 0 {
        result_idx = result_idx - 1
        if result_idx < 0 { result_idx = total - 1 }
        offset = scroll_to_show(results[result_idx], offset, buffer.length())
        msg = "Match \{result_idx + 1}/\{total}"
      }

    } else if key == 'g'.to_int() {
      let input = tui_read_line("Goto offset (hex): ")
      if input != "" {
        let off = if string_starts_with(input, "0x") || string_starts_with(input, "0X") {
          parse_int(input)
        } else { parse_hex_int(input) }
        match off {
          Some(o) if o >= 0 && o < buffer.length() => offset = (o / 16) * 16
          Some(_) => msg = "Offset out of range"
          None => msg = "Invalid offset"
        }
      }

    } else if key == 'e'.to_int() {
      if buffer.length() > 0 {
        edit_mode = true; edit_off = offset; edit_nibble = None; edit_ascii = false
        msg = "Entered edit mode"
      } else { msg = "Nothing to edit" }

    } else if key == '?'.to_int() || key == 'h'.to_int() {
      msg = "q:quit UD:line LR:page g:goto /:hex f:text n/N:match e:edit Home/End"
    }
  }

  tui_show_cursor()
  tui_clear_screen()
}

///|
/// Calculate offset to show target. Only scrolls if target is off-screen.
fn scroll_to_show(target : Int, current_offset : Int, total_len : Int) -> Int {
  let visible_rows = 18
  let visible_bytes = visible_rows * 16
  let view_end = current_offset + visible_bytes
  if target >= current_offset && target < view_end { return current_offset }
  let middle = visible_rows / 2
  let ideal = target - middle * 16
  if ideal < 0 { 0 }
  else if ideal + visible_bytes > total_len {
    let max = total_len - visible_bytes
    if max < 0 { 0 } else { max }
  }
  else { (ideal / 16) * 16 }
}
