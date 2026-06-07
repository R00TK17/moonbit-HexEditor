// TUI screen rendering — draw_screen and highlight helpers

///|
/// Split text into lines by newline.
fn split_text_lines(text : String) -> Array[String] {
  let lines = []
  let mut sb = StringBuilder()
  for i = 0; i < text.length(); i = i + 1 {
    let ch = text.get_char(i).unwrap()
    if ch == '\n' {
      lines.push(sb.to_string())
      sb = StringBuilder()
    } else {
      sb.write_char(ch)
    }
  }
  let remaining = sb.to_string()
  if remaining.length() > 0 { lines.push(remaining) }
  lines
}

///|
/// Build a set of offsets to highlight from all search results.
fn build_highlight_set(
  results : Array[Int],
  match_len : Int,
  buffer : @lib.HexBuffer,
) -> Array[Int] {
  if results.length() == 0 || match_len <= 0 { return [] }
  let set = []
  for i = 0; i < results.length(); i = i + 1 {
    let off = results[i]
    for j = 0; j < match_len; j = j + 1 {
      if off + j < buffer.length() { set.push(off + j) }
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
  if match_len <= 0 || match_offset < 0 || match_offset >= buffer.length() { return [] }
  let set = []
  for j = 0; j < match_len; j = j + 1 {
    if match_offset + j < buffer.length() { set.push(match_offset + j) }
  }
  set
}

///|
/// Draw the full TUI screen.
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
  struct_view : Bool,
  struct_offset : Int,
  screen_rows : Int,
) -> Unit {
  raw_print(str_to_bytes("[H"))

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

  if struct_view && !buffer.is_empty() {
    let bytes = buffer.to_bytes()
    let fields = @lib.parse_structure(bytes)
    if fields.length() > 0 {
      let text = @lib.format_structure(fields)
      let lines = split_text_lines(text)
      let total = lines.length()
      let off = if struct_offset < 0 { 0 } else { struct_offset }
      let off = if off >= total { total - 1 } else { off }
      let off = if off < 0 { 0 } else { off }
      let end = if off + screen_rows < total { off + screen_rows } else { total }
      for i = off; i < end; i = i + 1 {
        raw_print(str_to_bytes("  \{lines[i]}[K\r\n"))
      }
      for i = end; i < off + screen_rows; i = i + 1 {
        raw_print(str_to_bytes("  [K\r\n"))
      }
    } else {
      raw_print(str_to_bytes("  No structure detected.[K\r\n"))
      for i = 0; i < screen_rows - 1; i = i + 1 { raw_print(str_to_bytes("  [K\r\n")) }
    }
  } else if buffer.is_empty() {
    raw_print(str_to_bytes("\r\n  [Empty]  o:open  q:quit[K\r\n"))
  } else {
    let len = buffer.length()
    let max_row = (len + 15) / 16
    let display_rows = if screen_rows < max_row { screen_rows } else { max_row }

    let data = buffer.to_fixedarray()
    let highlight_all = build_highlight_set(search_results, match_len, buffer)
    let highlight_cur : Array[Int] = if search_results.length() > 0 && search_idx >= 0 && search_idx < search_results.length() {
      build_match_range(search_results[search_idx], match_len, buffer)
    } else { [] }

    for row = 0; row < display_rows; row = row + 1 {
      let row_off = offset + row * 16
      if row_off >= len { break }
      let row_len = if row_off + 16 <= len { 16 } else { len - row_off }

      let off_str = @lib.format_offset(row_off)
      raw_print(str_to_bytes("[34m\{off_str}[0m  "))

      for col = 0; col < 16; col = col + 1 {
        if col > 0 && col == 8 { raw_print(str_to_bytes(" ")) }
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
      raw_print(str_to_bytes("[K|\r\n"))
    }

    // Fill remaining rows if hex data is shorter than screen
    let remaining = screen_rows - display_rows
    for i = 0; i < remaining; i = i + 1 {
      raw_print(str_to_bytes("[K\r\n"))
    }
  }

  raw_print(str_to_bytes("[J"))

  let cur_row = if buffer.length() > 0 { offset / 16 + 1 } else { 0 }
  let max_row = if buffer.length() > 0 { (buffer.length() + 15) / 16 } else { 0 }
  raw_print(str_to_bytes("[44;37m 0x\{@lib.to_hex_string(offset, width=8)} | row \{cur_row}/\{max_row} [0m"))

  if status_msg != "" {
    raw_print(str_to_bytes(" [41;37m \{status_msg} [0m"))
  }
  raw_print(str_to_bytes("[K\r\n"))

  if edit_mode {
    let mode = if edit_ascii { "ASCII" } else { "Hex" }
    raw_print(str_to_bytes("[47;30m Esc:exit Tab:\{mode} i:insert Del:delete Ctrl+Z:undo Ctrl+S:save [0m\r\n"))
  } else if struct_view {
    raw_print(str_to_bytes("[47;30m q:quit UD:scroll LR:page t:hex [0m\r\n"))
  } else {
    raw_print(str_to_bytes("[47;30m q:quit UD:line LR:page g:goto /:hex f:text n/N:match e:edit t:struct [0m\r\n"))
  }
}
