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
/// Content area spans rows 1..screen_rows. Status bar is at screen_rows+1, help bar at screen_rows+2.
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
  bookmark_view : Bool,
  bookmark_sel : Int,
  bookmark_scroll : Int,
  bookmarks : FixedArray[Int?],
  scan_view : Bool,
  scan_sel : Int,
  scan_scroll : Int,
  scan_offsets : Array[Int],
  scan_names : Array[String],
  scan_sizes : Array[Int],
  entropy_view : Bool,
  entropy_sel : Int,
  entropy_blocks : Array[@lib.EntropyBlock],
  screen_rows : Int,
) -> Unit {
  let sb = StringBuilder()

  sb.write_string("[H")

  if scan_view {
    draw_scan_popup(sb, scan_sel, scan_scroll, scan_offsets, scan_names, scan_sizes, screen_rows)
  } else if entropy_view {
    draw_entropy_popup(sb, entropy_sel, entropy_blocks, screen_rows)
  } else if bookmark_view {
    draw_bookmark_popup(sb, bookmark_sel, bookmark_scroll, bookmarks, screen_rows)
  } else if struct_view && !buffer.is_empty() {
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
        sb.write_string("  \{lines[i]}[K\r\n")
      }
      for i = end; i < off + screen_rows; i = i + 1 {
        sb.write_string("  [K\r\n")
      }
    } else {
      sb.write_string("  No structure detected.[K\r\n")
      for i = 0; i < screen_rows - 1; i = i + 1 { sb.write_string("  [K\r\n") }
    }
  } else if buffer.is_empty() {
    sb.write_string("\r\n  [Empty]  o:open  q:quit[K\r\n")
  } else {
    let len = buffer.length()
    let rows_from_offset = if offset < len { (len - offset + 15) / 16 } else { 0 }
    let display_rows = if screen_rows < rows_from_offset { screen_rows } else { rows_from_offset }

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
      if row == 0 {
        sb.write_string("[44;37m0x\{off_str}[0m  ")
      } else {
        sb.write_string("[34m0x\{off_str}[0m  ")
      }

      for col = 0; col < 16; col = col + 1 {
        if col > 0 && col == 8 { sb.write_string(" ") }
        if col < row_len {
          let byte_off = row_off + col
          let byte = data[byte_off]
          let is_edit = edit_mode && byte_off == edit_off
          let is_cur = !is_edit && highlight_cur.contains(byte_off)
          let is_hl = !is_edit && !is_cur && highlight_all.contains(byte_off)
          if is_edit { sb.write_string("[7m") }
          else if is_cur { sb.write_string("[42;30m") }
          else if is_hl { sb.write_string("[43;30m") }
          let hex = @lib.format_byte_hex(byte, uppercase=true)
          sb.write_string(hex)
          if is_edit || is_cur || is_hl { sb.write_string("[0m") }
          sb.write_string(" ")
        } else {
          sb.write_string("   ")
        }
      }

      sb.write_string(" |")
      for col = 0; col < 16; col = col + 1 {
        if col < row_len {
          let byte_off = row_off + col
          let byte = data[byte_off]
          let is_edit = edit_mode && byte_off == edit_off
          let is_cur = !is_edit && highlight_cur.contains(byte_off)
          let is_hl = !is_edit && !is_cur && highlight_all.contains(byte_off)
          if is_edit { sb.write_string("[7m") }
          else if is_cur { sb.write_string("[42;30m") }
          else if is_hl { sb.write_string("[43;30m") }
          let a = @lib.format_ascii(byte)
          let s = StringBuilder()
          s.write_char(a)
          sb.write_string(s.to_string())
          if is_edit || is_cur || is_hl { sb.write_string("[0m") }
        } else {
          sb.write_string(" ")
        }
      }
      sb.write_string("[K|\r\n")
    }

    // Fill remaining rows if hex data is shorter than screen
    let remaining = screen_rows - display_rows
    for i = 0; i < remaining; i = i + 1 {
      sb.write_string("[K\r\n")
    }
  }

  // Status bar — fixed at second-to-last line (absolute positioning)
  let status_row = screen_rows + 1
  sb.write_string("[" + status_row.to_string() + ";1H")
  let cur_row = if buffer.length() > 0 { offset / 16 + 1 } else { 0 }
  let max_row = if buffer.length() > 0 { (buffer.length() + 15) / 16 } else { 0 }
  sb.write_string("[44;37m 0x\{@lib.to_hex_string(offset, width=8)} | row \{cur_row}/\{max_row} [0m")

  if status_msg != "" {
    sb.write_string(" [41;37m \{status_msg} [0m")
  }
  sb.write_string("[K")

  // Help bar — fixed at last line (absolute positioning)
  let help_row = screen_rows + 2
  sb.write_string("[" + help_row.to_string() + ";1H")
  if edit_mode {
    let mode = if edit_ascii { "ASCII" } else { "Hex" }
    sb.write_string("[47;30m Esc:exit Tab:\{mode} i:insert Del:delete Ctrl+Z:undo Ctrl+Y:redo Ctrl+S:save [0m[K")
  } else if scan_view {
    sb.write_string("[47;30m q:quit  Enter:jump  x:extract  w:close [0m[K")
  } else if entropy_view {
    sb.write_string("[47;30m q:quit  Enter:jump  LR:page h:close [0m[K")
  } else if bookmark_view {
    sb.write_string("[47;30m q:quit  Enter:jump  d:delete  b:close  Ctrl+B:set [0m[K")
  } else if struct_view {
    sb.write_string("[47;30m q:quit UD:scroll LR:page t:hex [0m[K")
  } else {
    sb.write_string("[47;30m q:quit o:open g:goto /:hex f:text w:scan h:entropy n/p:match e:edit t:struct b:bookmark [0m[K")
  }

  // Erase below: clear anything after the help bar
  sb.write_string("[J")
  let output = sb.to_string()
  raw_print(str_to_bytes(output))
}

///|
/// Draw the bookmark list popup over the hex content area.
fn draw_bookmark_popup(
  sb : StringBuilder,
  sel : Int,
  scroll : Int,
  bookmarks : FixedArray[Int?],
  screen_rows : Int,
) -> Unit {
  sb.write_string("  -- Bookmarks --[K\r\n")
  let max_visible = if screen_rows > 1 { screen_rows - 1 } else { 0 }
  let end = if scroll + max_visible < 21 { scroll + max_visible } else { 21 }
  for i = scroll; i < end; i = i + 1 {
    let marker = if i == sel { "> " } else { "  " }
    let content = match bookmarks[i] {
      None => "(empty)"
      Some(off) => "0x" + @lib.to_hex_string(off, width=8)
    }
    if i == sel {
      sb.write_string("  [44;37m" + marker + i.to_string() + ": " + content + "[0m[K\r\n")
    } else {
      sb.write_string("  " + marker + i.to_string() + ": " + content + "[K\r\n")
    }
  }
  let displayed = end - scroll
  let remaining = if screen_rows > displayed + 1 { screen_rows - displayed - 1 } else { 0 }
  for _i = 0; _i < remaining; _i = _i + 1 {
    sb.write_string("  [K\r\n")
  }
}

///|
/// Draw the entropy analysis popup.
fn draw_entropy_popup(
  sb : StringBuilder,
  sel : Int,
  blocks : Array[@lib.EntropyBlock],
  screen_rows : Int,
) -> Unit {
  sb.write_string("  -- Entropy Scan --[K\r\n")
  let total = blocks.length()
  let max_visible = if screen_rows > 1 { screen_rows - 1 } else { 0 }
  let end = if sel + max_visible < total { sel + max_visible } else { total }
  for i = sel; i < end; i = i + 1 {
    let b = blocks[i]
    let off_str = "0x" + @lib.to_hex_string(b.start, width=8)
    let e_str = format_e(b.entropy)
    let bar = make_bar((b.entropy / 8.0 * 40.0).to_int())
    if i == sel {
      sb.write_string("  [44;37m" + off_str + "  " + bar + "  " + e_str + "[0m[K\r\n")
    } else {
      sb.write_string("  " + off_str + "  " + bar + "  " + e_str + "[K\r\n")
    }
  }
  let displayed = end - sel
  let remaining = if screen_rows > displayed + 1 { screen_rows - displayed - 1 } else { 0 }
  for _i = 0; _i < remaining; _i = _i + 1 {
    sb.write_string("  [K\r\n")
  }
}

fn make_bar(len : Int) -> String {
  let s = StringBuilder()
  let clamped = if len > 40 { 40 } else { len }
  let color = if clamped > 30 { "[41m" } else if clamped > 15 { "[43m" } else { "[42m" }
  s.write_string(color)
  for _i = 0; _i < clamped; _i = _i + 1 { s.write_char('|') }
  s.write_string("[0m")
  for _i = clamped; _i < 40; _i = _i + 1 { s.write_char(' ') }
  s.to_string()
}

fn format_e(e : Double) -> String {
  let n = (e * 10.0).to_int()
  (n / 10).to_string() + "." + (n % 10).to_string()
}

///|
/// Draw the signature scan popup.
fn draw_scan_popup(
  sb : StringBuilder,
  sel : Int,
  scroll : Int,
  offsets : Array[Int],
  names : Array[String],
  sizes : Array[Int],
  screen_rows : Int,
) -> Unit {
  sb.write_string("  -- Binary Scan --[K\r\n")
  let total = offsets.length()
  let max_visible = if screen_rows > 1 { screen_rows - 1 } else { 0 }
  let end = if scroll + max_visible < total { scroll + max_visible } else { total }
  for i = scroll; i < end; i = i + 1 {
    let off_str = "0x" + @lib.to_hex_string(offsets[i], width=8)
    let size_str = " (" + @lib.format_size(sizes[i]) + ")"
    if i == sel {
      sb.write_string("  [44;37m" + off_str + "  " + names[i] + size_str + "[0m[K\r\n")
    } else {
      sb.write_string("  " + off_str + "  " + names[i] + size_str + "[K\r\n")
    }
  }
  let displayed = end - scroll
  let remaining = if screen_rows > displayed + 1 { screen_rows - displayed - 1 } else { 0 }
  for _i = 0; _i < remaining; _i = _i + 1 {
    sb.write_string("  [K\r\n")
  }
}
