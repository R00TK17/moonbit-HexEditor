// TUI file list popup + file browser — multi-file switching and directory navigation

///|
/// Handle keys in the file list popup. Returns true to swallow all keys.
pub fn handle_file_list_key(
  state : TuiState,
  key : Int,
  screen_rows : Int,
) -> Bool {
  let total = state.file_slots.length()
  if key == -1 { // up
    if state.file_list_sel > 0 { state.file_list_sel = state.file_list_sel - 1 }
  } else if key == -2 { // down
    if state.file_list_sel + 1 < total { state.file_list_sel = state.file_list_sel + 1 }
  } else if key == 13 { // enter: switch to selected file
    if state.file_list_sel < total && state.file_list_sel != state.active_file {
      state.pending_switch = state.file_list_sel
    }
    state.file_list_view = false
    state.msg = "Hex view"
  } else if key == 'd'.to_int() || key == 'D'.to_int() { // close selected file
    if total > 1 && state.file_list_sel < total {
      let removing = state.file_list_sel
      let _ = state.file_slots.remove(removing)
      if state.active_file == removing {
        let new_active = if removing >= state.file_slots.length() { state.file_slots.length() - 1 } else { removing }
        state.pending_switch = new_active
      } else if state.active_file > removing {
        state.active_file = state.active_file - 1
      }
      if state.file_list_sel >= state.file_slots.length() {
        state.file_list_sel = state.file_slots.length() - 1
      }
      state.msg = "File closed"
    } else if total <= 1 {
      state.msg = "Cannot close last file"
    }
  } else if key == 'q'.to_int() || key == 'Q'.to_int() {
    state.running = false
  } else if key == 9 || key == 27 { // Tab or Esc: close popup
    state.file_list_view = false
    state.msg = "Hex view"
  }
  ignore(screen_rows)
  true
}

///|
/// Handle Tab key in normal mode to open file list.
pub fn handle_file_list_normal_key(
  state : TuiState,
  key : Int,
) -> Bool {
  if key == 9 { // Tab
    if state.file_slots.length() > 1 {
      state.file_list_view = true
      state.file_list_sel = state.active_file
      state.msg = "File list (\{state.file_slots.length()} files)"
    } else {
      state.msg = "Only 1 file open (o:open more)"
    }
    return true
  }
  false
}

// ========== File Browser ==========

///|
/// Convert a path to absolute. Falls back to original if resolution fails.
pub fn to_absolute_path(path : String) -> String {
  let buf = Bytes::make(4096, b'\x00')
  let path_bytes = str_to_bytes(path)
  let n = tui_realpath(path_bytes, buf, 4096)
  if n > 0 { utf8_to_string(buf, 0, n) } else { path }
}

///|
/// Get filename from a full path (last component after / or \).
pub fn basename(path : String) -> String {
  let len = path.length()
  let mut last_sep = -1
  for i = 0; i < len; i = i + 1 {
    let ch = path.get_char(i).unwrap()
    if ch == '/' || ch == '\\' { last_sep = i }
  }
  if last_sep >= 0 && last_sep + 1 < len { path[last_sep + 1:].to_owned() } else { path }
}

///|
/// Join directory path with a file/dir name. Uses \ on Windows, / on Linux.
fn join_path(dir : String, name : String) -> String {
  if dir.length() == 0 { return name }
  let last = dir.get_char(dir.length() - 1).unwrap()
  // Detect separator from existing path
  let sep = if dir.contains("\\") { "\\" } else { "/" }
  if last == '/' || last == '\\' { dir + name } else { dir + sep + name }
}

///|
/// Get parent directory path.
fn parent_path(path : String) -> String {
  let len = path.length()
  if len <= 1 { return path }
  // Skip trailing separator
  let mut end = len - 1
  let ch = path.get_char(end).unwrap()
  if ch == '/' || ch == '\\' { end = end - 1 }
  // Find last separator
  let mut i = end
  while i >= 0 {
    let c = path.get_char(i).unwrap()
    if c == '/' || c == '\\' { return path[:i].to_owned() }
    i = i - 1
  }
  path
}

///|
/// Refresh browser entries from the current browser_path via FFI.
pub fn refresh_browser(state : TuiState) -> Unit {
  let buf = Bytes::make(65536, b'\x00')
  let path_bytes = str_to_bytes(state.browser_path)
  let n = tui_list_dir(path_bytes, buf, 65536)
  state.browser_names = []
  state.browser_is_dir = []
  // Parse "D:name\nF:name\n..." with UTF-8 names
  let dirs : Array[String] = []
  let files : Array[String] = []
  let mut pos = 0
  while pos < n {
    let t = buf[pos].to_int()
    if pos + 2 > n { break }
    pos = pos + 2 // skip "X:"
    // Find end of name (next \n)
    let name_start = pos
    while pos < n && buf[pos].to_int() != 0x0A { pos = pos + 1 }
    let name = utf8_to_string(buf, name_start, pos)
    pos = pos + 1 // skip \n
    if name == ".." || t == 'D'.to_int() { dirs.push(name) }
    else { files.push(name) }
  }
  // Build sorted list: .. first, then dirs (excluding ..), then files
  state.browser_names.push("..")
  state.browser_is_dir.push(true)
  for i = 0; i < dirs.length(); i = i + 1 {
    if dirs[i] != ".." {  // skip .. from C output, already prepended
      state.browser_names.push(dirs[i])
      state.browser_is_dir.push(true)
    }
  }
  for i = 0; i < files.length(); i = i + 1 {
    if files[i] != ".." {  // skip .. if misclassified as file on Linux
      state.browser_names.push(files[i])
      state.browser_is_dir.push(false)
    }
  }
  state.browser_sel = 0
  state.browser_scroll = 0
  if state.browser_names.length() <= 1 && n == 0 {
    state.msg = "Cannot read directory: \{state.browser_path}"
  }
}

///|
/// Decode UTF-8 bytes to String.
fn utf8_to_string(buf : Bytes, start : Int, end : Int) -> String {
  let sb = StringBuilder()
  let mut i = start
  while i < end {
    let b = buf[i].to_int()
    if b < 0x80 {
      match b.to_char() { Some(c) => sb.write_char(c); None => () }
      i = i + 1
    } else if b < 0xE0 && i + 1 < end {
      let cp = ((b & 0x1F) << 6) | (buf[i + 1].to_int() & 0x3F)
      match cp.to_char() { Some(c) => sb.write_char(c); None => () }
      i = i + 2
    } else if b < 0xF0 && i + 2 < end {
      let cp = ((b & 0x0F) << 12) | ((buf[i + 1].to_int() & 0x3F) << 6) | (buf[i + 2].to_int() & 0x3F)
      match cp.to_char() { Some(c) => sb.write_char(c); None => () }
      i = i + 3
    } else if i + 3 < end {
      let cp = ((b & 0x07) << 18) | ((buf[i + 1].to_int() & 0x3F) << 12) | ((buf[i + 2].to_int() & 0x3F) << 6) | (buf[i + 3].to_int() & 0x3F)
      match cp.to_char() { Some(c) => sb.write_char(c); None => () }
      i = i + 4
    } else {
      i = i + 1 // skip invalid byte
    }
  }
  sb.to_string()
}

///|
/// Get current working directory as String.
fn get_cwd_string() -> String {
  let buf = Bytes::make(1024, b'\x00')
  let n = tui_get_cwd(buf, 1024)
  if n <= 0 { return "." }
  utf8_to_string(buf, 0, n)
}

///|
/// Handle keys in the file browser popup. Returns true to swallow all keys.
pub fn handle_browser_key(
  state : TuiState,
  key : Int,
  screen_rows : Int,
) -> Bool {
  let total = state.browser_names.length()
  if key == -1 { // up
    if state.browser_sel > 0 { state.browser_sel = state.browser_sel - 1 }
    if state.browser_sel < state.browser_scroll { state.browser_scroll = state.browser_sel }
  } else if key == -2 { // down
    if state.browser_sel + 1 < total { state.browser_sel = state.browser_sel + 1 }
    let max_visible = if screen_rows > 1 { screen_rows - 1 } else { 1 }
    if state.browser_sel >= state.browser_scroll + max_visible {
      state.browser_scroll = state.browser_sel - max_visible + 1
    }
  } else if key == 13 && state.browser_sel < total { // enter
    let name = state.browser_names[state.browser_sel]
    let is_dir = state.browser_is_dir[state.browser_sel]
    if is_dir {
      // Enter directory
      if name == ".." {
        state.browser_path = parent_path(state.browser_path)
      } else {
        state.browser_path = join_path(state.browser_path, name)
      }
      refresh_browser(state)
      state.msg = state.browser_path
    } else {
      // Open file
      let full_path = to_absolute_path(join_path(state.browser_path, name))
      match load_file_best(full_path) {
        Ok(b) => {
          let new_slot : FileSlot = { buffer: b, path: full_path, offset: 0 }
          state.file_slots.push(new_slot)
          state.pending_switch = state.file_slots.length() - 1
          state.browser_view = false
          state.msg = "Opened: \{basename(full_path)}"
        }
        Err(m) => state.msg = "Error: \{m}"
      }
    }
  } else if key == 27 { // Esc: close browser
    state.browser_view = false
    state.msg = "Hex view"
  } else if key == 'o'.to_int() || key == 'O'.to_int() { // type path directly
    tui_show_cursor()
    let path = tui_read_line("Open file: ")
    tui_hide_cursor()
    if path != "" {
      let abs = to_absolute_path(path)
      match load_file_best(abs) {
        Ok(b) => {
          let new_slot : FileSlot = { buffer: b, path: abs, offset: 0 }
          state.file_slots.push(new_slot)
          state.pending_switch = state.file_slots.length() - 1
          state.browser_view = false
          state.msg = "Opened: \{basename(abs)}"
        }
        Err(m) => state.msg = "Error: \{m}"
      }
    }
  } else if key == 'q'.to_int() || key == 'Q'.to_int() {
    state.running = false
  }
  true
}

// ========== Bookmark Persistence ==========

///|
/// Get home directory as String.
fn get_home_string() -> String {
  let buf = Bytes::make(1024, b'\x00')
  let n = tui_get_home(buf, 1024)
  if n <= 0 { return "." }
  utf8_to_string(buf, 0, n)
}

///|
/// Sanitize path for use as filename (replace unsafe chars with _).
fn sanitize_name(path : String) -> String {
  let sb = StringBuilder()
  for i = 0; i < path.length(); i = i + 1 {
    let ch = path.get_char(i).unwrap()
    if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '.' || ch == '-' || ch == '_' {
      sb.write_char(ch)
    } else {
      sb.write_char('_')
    }
  }
  sb.to_string()
}

///|
/// Get marks file path for a given file.
fn get_marks_path(file_path : String) -> String {
  let home = get_home_string()
  let dir = join_path(home, ".hexedit")
  join_path(dir, sanitize_name(file_path) + ".marks")
}

///|
/// Parse an integer from ASCII bytes. Returns 0 on failure.
fn parse_int_from_bytes(data : Bytes, start : Int, end : Int) -> Int {
  let mut val = 0
  let mut neg = false
  let mut i = start
  if i < end && data[i].to_int() == 0x2D { neg = true; i = i + 1 } // '-'
  while i < end {
    let d = data[i].to_int() - 0x30
    if d < 0 || d > 9 { break }
    val = val * 10 + d
    i = i + 1
  }
  if neg { -val } else { val }
}

///|
/// Save bookmarks and scroll offset to marks file.
pub fn save_file_state(file_path : String, offset : Int, bookmarks : FixedArray[Int?]) -> Unit {
  if file_path == "(new)" || file_path == "" { return }
  let marks_dir = join_path(get_home_string(), ".hexedit")
  tui_mkdir_p(str_to_bytes(marks_dir))
  let marks_path = get_marks_path(file_path)
  let sb = StringBuilder()
  sb.write_string("offset=\{offset}\n")
  for i = 0; i < 21; i = i + 1 {
    match bookmarks[i] {
      Some(off) => sb.write_string("b\{i}=\{off}\n")
      None => ()
    }
  }
  let content = sb.to_string()
  let bytes = ascii_to_bytes(content)
  try { @fs.write_bytes_to_file(marks_path, bytes) }
  catch { @fs.IOError::IOError(_) => () }
}

///|
/// Load bookmarks and scroll offset from marks file. Returns saved offset (0 if none).
pub fn load_file_state(file_path : String, bookmarks : FixedArray[Int?]) -> Int {
  if file_path == "(new)" || file_path == "" { return 0 }
  let marks_path = get_marks_path(file_path)
  if !@fs.path_exists(marks_path) { return 0 }
  let mut data : Bytes = Bytes::new(0)
  try { data = @fs.read_file_to_bytes(marks_path) } catch { _ => return 0 }
  let mut offset = 0
  let len = data.length()
  let mut pos = 0
  while pos < len {
    // Find line start and end
    let line_start = pos
    while pos < len && data[pos].to_int() != 0x0A { pos = pos + 1 }
    let line_end = pos
    pos = pos + 1 // skip \n
    // Find '=' in line
    let mut eq = line_start
    while eq < line_end && data[eq].to_int() != 0x3D { eq = eq + 1 }
    if eq >= line_end { continue }
    // Parse key
    let key_len = eq - line_start
    let val_start = eq + 1
    if key_len == 6 && data[line_start].to_int() == 0x6F { // "offset"
      offset = parse_int_from_bytes(data, val_start, line_end)
    } else if key_len >= 2 && data[line_start].to_int() == 0x62 { // "bN"
      let slot = parse_int_from_bytes(data, line_start + 1, eq)
      if slot >= 0 && slot < 21 {
        let val = parse_int_from_bytes(data, val_start, line_end)
        bookmarks[slot] = Some(val)
      }
    }
  }
  offset
}
