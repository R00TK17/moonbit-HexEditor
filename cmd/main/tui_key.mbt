// TUI key handlers — bookmark, struct, edit, and normal mode key dispatch

///|
/// Per-file state slot for multi-file support.
pub struct FileSlot {
  mut buffer : @lib.HexBuffer
  path : String
  mut offset : Int
}

///|
/// Mutable TUI state passed to key handlers.
struct TuiState {
  mut offset : Int
  mut msg : String
  mut results : Array[Int]
  mut result_idx : Int
  mut match_len : Int
  mut match_lens : Array[Int]
  mut running : Bool
  mut edit_mode : Bool
  mut edit_off : Int
  mut edit_nibble : Int?
  mut edit_ascii : Bool
  mut edit_modified : Bool
  mut esc_pending : Bool
  mut struct_view : Bool
  mut struct_offset : Int
  mut bookmark_view : Bool
  mut bookmark_sel : Int
  mut bookmark_scroll : Int
  bookmarks : FixedArray[Int?]
  mut scan_view : Bool
  mut scan_sel : Int
  mut scan_scroll : Int
  mut scan_offsets : Array[Int]
  mut scan_names : Array[String]
  mut scan_sizes : Array[Int]
  mut scan_done : Bool
  mut entropy_view : Bool
  mut entropy_sel : Int
  mut entropy_blocks : Array[@lib.EntropyBlock]
  mut entropy_done : Bool
  mut strings_view : Bool
  mut strings_sel : Int
  mut strings_scroll : Int
  mut strings_matches : Array[@lib.StringMatch]
  mut strings_done : Bool
  mut undo_stack : Array[UndoOp]
  mut redo_stack : Array[UndoOp]
  mut codec_view : Bool
  mut codec_type : Int
  mut codec_encode : Bool
  mut codec_input : String
  mut codec_result : String
  file_slots : Array[FileSlot]
  mut active_file : Int
  mut file_list_view : Bool
  mut file_list_sel : Int
  mut pending_switch : Int
  mut browser_view : Bool
  mut browser_path : String
  mut browser_names : Array[String]
  mut browser_is_dir : Array[Bool]
  mut browser_sel : Int
  mut browser_scroll : Int
}

///|
/// Initialize TuiState with defaults.
pub fn TuiState::new(file_path : String?, buffer : @lib.HexBuffer) -> TuiState {
  {
    offset: 0,
    msg: match file_path {
      Some(p) => if buffer.length() > 0 { "\{p} | \{@lib.format_size(buffer.length())}" } else { "" }
      None => ""
    },
    results: [],
    result_idx: 0,
    match_len: 0,
    match_lens: [],
    running: true,
    edit_mode: false,
    edit_off: 0,
    edit_nibble: None,
    edit_ascii: false,
    edit_modified: false,
    esc_pending: false,
    struct_view: false,
    struct_offset: 0,
    bookmark_view: false,
    bookmark_sel: 0,
    bookmark_scroll: 0,
    bookmarks: FixedArray::make(21, None),
    scan_view: false, scan_sel: 0, scan_scroll: 0,
    scan_offsets: [], scan_names: [], scan_sizes: [], scan_done: false,
    entropy_view: false, entropy_sel: 0, entropy_blocks: [], entropy_done: false,
    strings_view: false, strings_sel: 0, strings_scroll: 0, strings_matches: [], strings_done: false,
    undo_stack: [],
    redo_stack: [],
    codec_view: false, codec_type: 0, codec_encode: true,
    codec_input: "", codec_result: "",
    file_slots: [{ buffer, path: match file_path { Some(p) => p; None => "(new)" }, offset: 0 }],
    active_file: 0, file_list_view: false, file_list_sel: 0, pending_switch: -1,
    browser_view: false, browser_path: "", browser_names: [], browser_is_dir: [],
    browser_sel: 0, browser_scroll: 0,
  }
}

///|
/// Recompute codec result from current input, type, and mode.
fn codec_recompute(state : TuiState) -> Unit {
  let input = state.codec_input
  if input == "" { state.codec_result = ""; return }
  if state.codec_encode {
    let data = ascii_to_bytes(input)
    state.codec_result = match state.codec_type {
      0 => @lib.base64_encode(data)
      1 => @lib.url_encode(data)
      2 => @lib.unicode_encode(data)
      _ => {
        // Hex: bytes → "48 65 6C"
        let sb = StringBuilder()
        for i = 0; i < data.length(); i = i + 1 {
          if i > 0 { sb.write_char(' ') }
          sb.write_string(@lib.format_byte_hex(data[i], uppercase=true))
        }
        sb.to_string()
      }
    }
  } else {
    if state.codec_type == 3 {
      // Hex → Text
      match @lib.parse_hex_string(input) {
        Some(bytes) => {
          let sb = StringBuilder()
          for i = 0; i < bytes.length(); i = i + 1 {
            let b = bytes[i].to_int()
            if b >= 0x20 && b <= 0x7E { sb.write_char(b.to_char().unwrap()) }
            else { sb.write_char('.') }
          }
          state.codec_result = sb.to_string()
        }
        None => state.codec_result = "(invalid hex)"
      }
    } else {
      let decoded : Bytes? = match state.codec_type {
        0 => @lib.base64_decode(input)
        1 => @lib.url_decode(input)
        _ => @lib.unicode_decode(input)
      }
      match decoded {
        Some(bytes) => {
          let sb = StringBuilder()
          for i = 0; i < bytes.length(); i = i + 1 {
            let b = bytes[i].to_int()
            if b >= 0x20 && b <= 0x7E { sb.write_char(b.to_char().unwrap()) }
            else { sb.write_char('.') }
          }
          state.codec_result = sb.to_string()
        }
        None => state.codec_result = "(invalid)"
      }
    }
  }
}

///|
/// Handle keys in codec popup. All printable chars are input.
fn handle_codec_key(state : TuiState, key : Int) -> Unit {
  if key == -3 { // left: prev type
    state.codec_type = (state.codec_type + 3) % 4
    codec_recompute(state)
  } else if key == -4 { // right: next type
    state.codec_type = (state.codec_type + 1) % 4
    codec_recompute(state)
  } else if key == 9 { // tab: toggle encode/decode
    state.codec_encode = !state.codec_encode
    codec_recompute(state)
  } else if key == 8 || key == 127 { // backspace
    let len = state.codec_input.length()
    if len > 0 {
      state.codec_input = state.codec_input[:len - 1].to_owned()
      codec_recompute(state)
    }
  } else if key == 27 { // esc: close
    state.codec_view = false
    state.msg = "Hex view"
  } else if key >= 32 && key <= 126 { // printable: append to input
    let sb = StringBuilder()
    sb.write_string(state.codec_input)
    sb.write_char(key.to_char().unwrap())
    state.codec_input = sb.to_string()
    codec_recompute(state)
  }
  // else: swallow other keys
}

///|
/// Dispatch a single key event. Modifies state and buffer in place.
pub fn handle_key(
  state : TuiState,
  buffer : @lib.HexBuffer,
  key : Int,
  screen_rows : Int,
) -> Unit {
  // Only clear status message on real keypress, not on timeout (-10)
  if key != -10 { state.msg = "" }

  // ====== Scan popup ======
  if state.scan_view && key == -1 {
    if state.scan_sel > 0 { state.scan_sel = state.scan_sel - 1 }
    if state.scan_sel < state.scan_scroll { state.scan_scroll = state.scan_sel }
  } else if state.scan_view && key == -2 {
    let total = state.scan_offsets.length()
    if state.scan_sel + 1 < total { state.scan_sel = state.scan_sel + 1 }
    let max_visible = if screen_rows > 1 { screen_rows - 1 } else { 1 }
    if state.scan_sel >= state.scan_scroll + max_visible {
      state.scan_scroll = state.scan_sel - max_visible + 1
    }
  } else if state.scan_view && key == -3 {
    let page = if screen_rows > 2 { screen_rows - 2 } else { 1 }
    if state.scan_sel >= page { state.scan_sel = state.scan_sel - page } else { state.scan_sel = 0 }
    if state.scan_sel < state.scan_scroll { state.scan_scroll = state.scan_sel }
  } else if state.scan_view && key == -4 {
    let total = state.scan_offsets.length()
    let page = if screen_rows > 2 { screen_rows - 2 } else { 1 }
    let new_sel = state.scan_sel + page
    state.scan_sel = if new_sel < total { new_sel } else { total - 1 }
    let max_visible = if screen_rows > 1 { screen_rows - 1 } else { 1 }
    if state.scan_sel >= state.scan_scroll + max_visible {
      state.scan_scroll = state.scan_sel - max_visible + 1
    }
  } else if state.scan_view && key == 13 {
    let total = state.scan_offsets.length()
    if total > 0 && state.scan_sel < total {
      state.offset = (state.scan_offsets[state.scan_sel] / 16) * 16
      state.scan_view = false
      state.msg = "Jumped to " + state.scan_names[state.scan_sel] + " (" + @lib.format_size(state.scan_sizes[state.scan_sel]) + ")"
    }
  } else if state.scan_view && (key == 'x'.to_int() || key == 'X'.to_int()) {
    let total = state.scan_offsets.length()
    if total > 0 && state.scan_sel < total {
      let data = buffer.to_bytes()
      let base = match buffer.get_file_path() { Some(p) => p; None => "output" }
      state.msg = @lib.extract_region(data, state.scan_offsets[state.scan_sel], state.scan_names[state.scan_sel], base)
    }
  } else if state.scan_view && key == 27 {
    state.scan_view = false; state.msg = "Hex view"
  } else if state.scan_view && (key == 'q'.to_int() || key == 'Q'.to_int()) {
    state.running = false
  } else if state.scan_view && key != 'w'.to_int() && key != 'W'.to_int() { () }

  // ====== Entropy popup ======
  if state.entropy_view && key == -1 {
    if state.entropy_sel > 0 { state.entropy_sel = state.entropy_sel - 1 }
  } else if state.entropy_view && key == -2 {
    let total = state.entropy_blocks.length()
    if state.entropy_sel + 1 < total { state.entropy_sel = state.entropy_sel + 1 }
  } else if state.entropy_view && key == -3 {
    let page = if screen_rows > 2 { screen_rows - 2 } else { 1 }
    if state.entropy_sel >= page { state.entropy_sel = state.entropy_sel - page } else { state.entropy_sel = 0 }
  } else if state.entropy_view && key == -4 {
    let total = state.entropy_blocks.length()
    let page = if screen_rows > 2 { screen_rows - 2 } else { 1 }
    let new_sel = state.entropy_sel + page
    state.entropy_sel = if new_sel < total { new_sel } else { total - 1 }
  } else if state.entropy_view && key == 13 {
    let total = state.entropy_blocks.length()
    if total > 0 && state.entropy_sel < total {
      state.offset = (state.entropy_blocks[state.entropy_sel].start / 16) * 16
      state.entropy_view = false
      state.msg = "Jumped to 0x" + @lib.to_hex_string(state.entropy_blocks[state.entropy_sel].start, width=8)
    }
  } else if state.entropy_view && (key == 'h'.to_int() || key == 'H'.to_int() || key == 27) {
    state.entropy_view = false; state.msg = "Hex view"
  } else if state.entropy_view && (key == 'q'.to_int() || key == 'Q'.to_int()) {
    state.running = false
  } else if state.entropy_view { ()
  // ====== Strings popup ======
  } else if state.strings_view && key == -2 {
    let total = state.strings_matches.length()
    if total > 0 && state.strings_sel < total - 1 { state.strings_sel = state.strings_sel + 1 }
    if state.strings_sel >= state.strings_scroll + screen_rows - 1 { state.strings_scroll = state.strings_sel - screen_rows + 2 }
  } else if state.strings_view && key == -1 {
    if state.strings_sel > 0 { state.strings_sel = state.strings_sel - 1 }
    if state.strings_sel < state.strings_scroll { state.strings_scroll = state.strings_sel }
  } else if state.strings_view && key == -3 {
    let page = if screen_rows > 2 { screen_rows - 2 } else { 1 }
    state.strings_sel = if state.strings_sel >= page { state.strings_sel - page } else { 0 }
    if state.strings_sel < state.strings_scroll { state.strings_scroll = state.strings_sel }
  } else if state.strings_view && key == -4 {
    let page = if screen_rows > 2 { screen_rows - 2 } else { 1 }
    let total = state.strings_matches.length()
    if total > 0 && state.strings_sel + page < total - 1 { state.strings_sel = state.strings_sel + page }
    else if total > 0 { state.strings_sel = total - 1 }
    if state.strings_sel >= state.strings_scroll + screen_rows - 1 { state.strings_scroll = state.strings_sel - screen_rows + 2 }
  } else if state.strings_view && key == 13 {
    let total = state.strings_matches.length()
    if total > 0 && state.strings_sel < total {
      let m = state.strings_matches[state.strings_sel]
      state.results = [m.offset]
      state.match_len = m.text.length()
      state.result_idx = 0
      state.offset = scroll_to_show(m.offset, state.offset, buffer.length(), screen_rows)
      state.strings_view = false
      state.msg = "String at 0x" + @lib.to_hex_string(m.offset, width=8)
    }
  } else if state.strings_view && (key == 's'.to_int() || key == 'S'.to_int() || key == 27) {
    state.strings_view = false; state.msg = "Hex view"
  } else if state.strings_view && (key == 'q'.to_int() || key == 'Q'.to_int()) {
    state.running = false
  } else if state.strings_view { ()
  // ====== Codec popup ======
  } else if state.codec_view {
    handle_codec_key(state, key)
  // ====== Bookmark popup (in tui_bookmark.mbt) ======
  } else if state.bookmark_view && handle_bookmark_popup_key(state, key, screen_rows) {
    ()
  } else if state.file_list_view && handle_file_list_key(state, key, screen_rows) {
    ()
  } else if state.browser_view && handle_browser_key(state, key, screen_rows) {
    ()

  // ====== Struct view mode ======
  } else if state.struct_view && key == -1 {
    let (total, _max) = get_struct_info(buffer)
    if total > screen_rows && state.struct_offset > 0 { state.struct_offset = state.struct_offset - 1 }
  } else if state.struct_view && key == -2 {
    let (total, _max) = get_struct_info(buffer)
    let max_off = if total > screen_rows { total - screen_rows } else { 0 }
    if state.struct_offset < max_off { state.struct_offset = state.struct_offset + 1 }
  } else if state.struct_view && key == -3 {
    let (total, _max) = get_struct_info(buffer)
    if total > screen_rows {
      if state.struct_offset >= screen_rows { state.struct_offset = state.struct_offset - screen_rows } else { state.struct_offset = 0 }
    }
  } else if state.struct_view && key == -4 {
    let (total, _max) = get_struct_info(buffer)
    if total > screen_rows {
      let max_off = total - screen_rows
      let new_off = state.struct_offset + screen_rows
      state.struct_offset = if new_off > max_off { max_off } else { new_off }
    }
  } else if state.struct_view && key == -7 {
    state.struct_offset = 0
  } else if state.struct_view && (key == 't'.to_int() || key == 'T'.to_int() || key == 27) {
    state.struct_view = false
    state.msg = "Hex view"
  } else if state.struct_view && (key == 'q'.to_int() || key == 'Q'.to_int()) {
    state.running = false
  } else if state.struct_view {
    ()
  } else if (state.scan_view || state.entropy_view || state.strings_view) && key != 'w'.to_int() && key != 'W'.to_int() && key != 's'.to_int() && key != 'S'.to_int() {
    ()

  // ====== Edit mode keys ======
  } else if state.edit_mode && key == 27 {
    if state.edit_modified && !state.esc_pending {
      state.esc_pending = true
      state.msg = "Unsaved edits! Press Esc again to discard, Ctrl+X to save"
    } else {
      let was_modified = state.edit_modified
      if was_modified { revert_all_edits(buffer, state.undo_stack) }
      state.edit_mode = false
      state.edit_modified = false
      state.esc_pending = false
      state.undo_stack = []
      state.redo_stack = []
      state.msg = if was_modified { "Edit mode off (changes discarded)" } else { "Edit mode off" }
    }

  } else if state.edit_mode && key == -1 {
    if state.edit_off >= 16 { state.edit_off = state.edit_off - 16 }
    if state.edit_off < state.offset { state.offset = (state.edit_off / 16) * 16 }
    if state.offset < 0 { state.offset = 0 }

  } else if state.edit_mode && key == -2 {
    if state.edit_off + 16 < buffer.length() { state.edit_off = state.edit_off + 16 }
    let visible_end = state.offset + screen_rows * 16
    if state.edit_off >= visible_end { state.offset = ((state.edit_off - (screen_rows - 1) * 16) / 16) * 16 }
    if state.offset < 0 { state.offset = 0 }

  } else if state.edit_mode && key == -3 {
    if state.edit_off > 0 { state.edit_off = state.edit_off - 1 }
    if state.edit_off < state.offset { state.offset = (state.edit_off / 16) * 16 }
    if state.offset < 0 { state.offset = 0 }

  } else if state.edit_mode && key == -4 {
    if state.edit_off + 1 < buffer.length() { state.edit_off = state.edit_off + 1 }
    let visible_end = state.offset + screen_rows * 16
    if state.edit_off >= visible_end { state.offset = ((state.edit_off - (screen_rows - 1) * 16) / 16) * 16 }
    if state.offset < 0 { state.offset = 0 }

  } else if state.edit_mode && key == 9 {
    state.edit_ascii = !state.edit_ascii
    state.edit_nibble = None
    state.msg = if state.edit_ascii { "ASCII input mode" } else { "Hex input mode" }

  } else if state.edit_mode && key == -9 {
    state.edit_modified = true
    state.esc_pending = false
    let old = match buffer.get_byte(state.edit_off) { Some(b) => b; None => b'\x00' }
    state.undo_stack.push({ kind: 2, offset: state.edit_off, old_byte: old })
    state.redo_stack = []; state.scan_done = false; state.strings_done = false; state.entropy_done = false
    buffer.delete_byte(state.edit_off) |> ignore
    if state.edit_off >= buffer.length() && state.edit_off > 0 { state.edit_off = state.edit_off - 1 }
    state.results = []
    state.match_len = 0
    state.match_lens = []
    state.msg = "Deleted 1 byte\{depth_suffix(state.undo_stack.length(), state.redo_stack.length())}"

  } else if state.edit_mode && (key == 'i'.to_int() || key == 'I'.to_int()) {
    state.edit_modified = true
    state.esc_pending = false
    state.undo_stack.push({ kind: 1, offset: state.edit_off, old_byte: b'\x00' })
    state.redo_stack = []; state.scan_done = false; state.strings_done = false; state.entropy_done = false
    buffer.insert_byte(state.edit_off, b'\x00') |> ignore
    state.msg = "Inserted 00\{depth_suffix(state.undo_stack.length(), state.redo_stack.length())}"

  } else if state.edit_mode && !state.edit_ascii && key >= '0'.to_int() && key <= '9'.to_int() {
    state.edit_modified = true; state.esc_pending = false; state.redo_stack = []; state.scan_done = false; state.strings_done = false; state.entropy_done = false
    let (new_off, new_nib, new_msg, undo) = handle_hex_input(buffer, state.edit_off, state.edit_nibble, key)
    state.edit_off = new_off; state.edit_nibble = new_nib
    match undo { Some(op) => state.undo_stack.push(op); None => () }
    state.msg = "\{new_msg}\{depth_suffix(state.undo_stack.length(), state.redo_stack.length())}"

  } else if state.edit_mode && !state.edit_ascii && key >= 'a'.to_int() && key <= 'f'.to_int() {
    state.edit_modified = true; state.esc_pending = false; state.redo_stack = []; state.scan_done = false; state.strings_done = false; state.entropy_done = false
    let (new_off, new_nib, new_msg, undo) = handle_hex_input(buffer, state.edit_off, state.edit_nibble, key)
    state.edit_off = new_off; state.edit_nibble = new_nib
    match undo { Some(op) => state.undo_stack.push(op); None => () }
    state.msg = "\{new_msg}\{depth_suffix(state.undo_stack.length(), state.redo_stack.length())}"

  } else if state.edit_mode && !state.edit_ascii && key >= 'A'.to_int() && key <= 'F'.to_int() {
    state.edit_modified = true; state.esc_pending = false; state.redo_stack = []; state.scan_done = false; state.strings_done = false; state.entropy_done = false
    let lower = key + ('a'.to_int() - 'A'.to_int())
    let (new_off, new_nib, new_msg, undo) = handle_hex_input(buffer, state.edit_off, state.edit_nibble, lower)
    state.edit_off = new_off; state.edit_nibble = new_nib
    match undo { Some(op) => state.undo_stack.push(op); None => () }
    state.msg = "\{new_msg}\{depth_suffix(state.undo_stack.length(), state.redo_stack.length())}"

  } else if state.edit_mode && state.edit_ascii && key >= 32 && key <= 126 {
    state.edit_modified = true; state.esc_pending = false; state.edit_nibble = None; state.redo_stack = []; state.scan_done = false; state.strings_done = false; state.entropy_done = false
    let old = match buffer.get_byte(state.edit_off) { Some(b) => b; None => b'\x00' }
    state.undo_stack.push({ kind: 0, offset: state.edit_off, old_byte: old })
    let ch = key.to_char().unwrap()
    buffer.set_byte(state.edit_off, ch.to_int().to_byte()) |> ignore
    state.msg = "Set '\{ch}' (0x\{@lib.format_byte_hex(ch.to_int().to_byte())})\{depth_suffix(state.undo_stack.length(), state.redo_stack.length())}"
    if state.edit_off + 1 < buffer.length() { state.edit_off = state.edit_off + 1 }

  // Ctrl+Z: Undo
  } else if state.edit_mode && key == 26 {
    let (new_undo, popped) = pop_last(state.undo_stack)
    match popped {
      None => state.msg = "Nothing to undo (undo:0 redo:\{state.redo_stack.length()})"
      Some(op) => {
        state.undo_stack = new_undo
        let redo_op = apply_undo(buffer, op)
        state.redo_stack.push(redo_op)
        let depth = depth_suffix(state.undo_stack.length(), state.redo_stack.length())
        if op.kind == 0 {
          state.msg = "Undo: restored 0x\{@lib.format_byte_hex(op.old_byte)}\{depth}"
        } else if op.kind == 1 {
          state.msg = "Undo: removed insertion\{depth}"
        } else {
          state.msg = "Undo: restored deleted byte\{depth}"
        }
        state.edit_off = op.offset
        state.edit_modified = state.undo_stack.length() > 0
      }
    }

  // Ctrl+Y: Redo
  } else if state.edit_mode && key == 25 {
    let (new_redo, popped) = pop_last(state.redo_stack)
    match popped {
      None => state.msg = "Nothing to redo (undo:\{state.undo_stack.length()} redo:0)"
      Some(op) => {
        state.redo_stack = new_redo
        let undo_op = apply_redo(buffer, op)
        state.undo_stack.push(undo_op)
        let depth = depth_suffix(state.undo_stack.length(), state.redo_stack.length())
        if op.kind == 0 {
          state.msg = "Redo: restored 0x\{@lib.format_byte_hex(op.old_byte)}\{depth}"
        } else if op.kind == 1 {
          state.msg = "Redo: re-inserted byte\{depth}"
        } else {
          state.msg = "Redo: removed byte\{depth}"
        }
        state.edit_off = op.offset
        state.edit_modified = true
      }
    }

  } else if state.edit_mode && key == 24 {
    match buffer.get_file_path() {
      Some(p) => {
        try {
          buffer.save(path=p)
          state.edit_modified = false; state.undo_stack = []; state.redo_stack = []; state.msg = "Saved: \{p}"
        } catch {
          @fs.IOError::IOError(m) => state.msg = "Save error: \{m}"
          _ => state.msg = "Unknown save error"
        }
      }
      None => state.msg = "No file path to save"
    }

  } else if state.edit_mode {
    ()

  // ====== Normal mode keys ======
  } else if key == 27 {
    if state.results.length() > 0 { state.results = []; state.match_len = 0; state.match_lens = []; state.msg = "Search cleared" }
  } else if key == 'q'.to_int() || key == 'Q'.to_int() {
    state.running = false

  } else if !state.bookmark_view && !state.scan_view && !state.strings_view && key == -1 {
    if state.offset >= 16 { state.offset = state.offset - 16 }

  } else if !state.bookmark_view && !state.scan_view && !state.strings_view && key == -2 {
    if state.offset + 16 < buffer.length() { state.offset = state.offset + 16 }

  } else if !state.bookmark_view && !state.scan_view && !state.strings_view && key == -3 {
    let page = screen_rows * 16
    if state.offset >= page { state.offset = state.offset - page } else { state.offset = 0 }

  } else if !state.bookmark_view && !state.scan_view && !state.strings_view && key == -4 {
    let page = screen_rows * 16
    if state.offset + page < buffer.length() { state.offset = state.offset + page }
    else { let last_off = if buffer.length() > 0 { ((buffer.length() - 1) / 16) * 16 } else { 0 }; if state.offset < last_off { state.offset = last_off } }

  } else if !state.bookmark_view && !state.scan_view && !state.strings_view && key == -7 {
    state.offset = 0

  } else if !state.bookmark_view && !state.scan_view && !state.strings_view && key == -8 {
    let len = buffer.length()
    let rows = if len > 0 { (len - 1) / 16 } else { 0 }
    state.offset = rows * 16

  } else if key == '/'.to_int() {
    let pattern = tui_read_line("Hex search: ")
    if pattern != "" {
      let data = buffer.to_bytes()
      match @lib.find_hex_pattern(data, pattern) {
        Some((offsets, lens)) => {
          state.results = offsets
          state.match_lens = lens
          if offsets.length() > 0 {
            state.result_idx = 0; state.match_len = lens[0]
            state.offset = scroll_to_show(offsets[0], state.offset, buffer.length(), screen_rows)
            state.msg = "Hex: \{offsets.length()} matches (n:next)"
          } else { state.msg = "Not found"; state.match_len = 0 }
        }
        None => state.msg = "Invalid hex pattern"
      }
    }

  } else if key == 'f'.to_int() || key == 'F'.to_int() {
    let pattern = tui_read_line("Text search: ")
    if pattern != "" {
      let data = buffer.to_bytes()
      match @lib.find_text_pattern(data, pattern) {
        Some((offsets, lens)) => {
          state.results = offsets
          state.match_lens = lens
          if offsets.length() > 0 {
            state.result_idx = 0; state.match_len = lens[0]
            state.offset = scroll_to_show(offsets[0], state.offset, buffer.length(), screen_rows)
            state.msg = "Text: \{offsets.length()} matches (n:next)"
          } else { state.msg = "Not found"; state.match_len = 0 }
        }
        None => state.msg = "Invalid text pattern"
      }
    }

  } else if key == 'n'.to_int() || key == 'N'.to_int() {
    let total = state.results.length()
    if total > 0 {
      state.result_idx = state.result_idx + 1
      if state.result_idx >= total { state.result_idx = 0 }
      state.offset = scroll_to_show(state.results[state.result_idx], state.offset, buffer.length(), screen_rows)
      state.msg = "Match \{state.result_idx + 1}/\{total}"
    }

  } else if key == 'p'.to_int() || key == 'P'.to_int() {
    let total = state.results.length()
    if total > 0 {
      state.result_idx = state.result_idx - 1
      if state.result_idx < 0 { state.result_idx = total - 1 }
      state.offset = scroll_to_show(state.results[state.result_idx], state.offset, buffer.length(), screen_rows)
      state.msg = "Match \{state.result_idx + 1}/\{total}"
    }

  } else if key == 'g'.to_int() || key == 'G'.to_int() {
    let input = tui_read_line("Goto offset (hex, #N bookmark): ")
    if input != "" {
      // Bookmark reference: #N (e.g., #0, #5, #20)
      if string_starts_with(input, "#") {
        let num_str = input[1:].to_owned()
        match parse_int(num_str) {
          Some(n) if n >= 0 && n <= 20 => match state.bookmarks[n] {
            None => state.msg = "Bookmark #" + n.to_string() + " is empty"
            Some(off) => {
              state.offset = (off / 16) * 16
              state.msg = "Jumped to #" + n.to_string() + ": 0x" + @lib.to_hex_string(off, width=8)
            }
          }
          Some(n) => state.msg = "Bookmark #" + n.to_string() + " out of range (0-20)"
          None => state.msg = "Invalid bookmark number"
        }
      } else {
        let off = if string_starts_with(input, "0x") || string_starts_with(input, "0X") {
          parse_int(input)
        } else { parse_hex_int(input) }
        match off {
          Some(o) if o >= 0 && o < buffer.length() => state.offset = (o / 16) * 16
          Some(_) => state.msg = "Offset out of range"
          None => state.msg = "Invalid offset"
        }
      }
    }

  } else if key == 'e'.to_int() || key == 'E'.to_int() {
    if buffer.length() > 0 {
      let target = if state.results.length() > 0 && state.result_idx < state.results.length() { state.results[state.result_idx] } else { state.offset }
      state.edit_mode = true; state.edit_off = target; state.edit_nibble = None; state.edit_ascii = false
      state.offset = scroll_to_show(target, state.offset, buffer.length(), screen_rows)
      state.msg = "Entered edit mode"
    } else { state.msg = "Nothing to edit" }

  } else if key == 't'.to_int() || key == 'T'.to_int() {
    state.struct_view = !state.struct_view
    state.msg = if state.struct_view { "Structure view" } else { "Hex view" }

  // Bookmark keys (in tui_bookmark.mbt)
  } else if handle_bookmark_normal_key(state, key) {
    ()
  } else if handle_file_list_normal_key(state, key) {
    ()

  } else if key == 'w'.to_int() || key == 'W'.to_int() {
    if state.scan_view {
      state.scan_view = false; state.msg = "Hex view"
    } else if state.scan_done {
      state.scan_view = true
      state.msg = "Binary scan view (cached)"
      state.results = state.scan_offsets; state.match_len = 8; state.result_idx = 0
    } else {
      let matches = @lib.scan_signatures(buffer.to_bytes())
      state.scan_offsets = []; state.scan_names = []; state.scan_sizes = []
      for i = 0; i < matches.length(); i = i + 1 {
        state.scan_offsets.push(matches[i].offset)
        state.scan_names.push(matches[i].name)
        state.scan_sizes.push(matches[i].size)
      }
      state.scan_sel = 0; state.scan_scroll = 0; state.scan_done = true
      if matches.length() > 0 { state.scan_view = true; state.msg = "Binary scan view" } else { state.msg = "No signatures found" }
      state.results = state.scan_offsets; state.match_len = 8; state.result_idx = 0
    }
  } else if key == 'h'.to_int() || key == 'H'.to_int() {
    if !state.entropy_done {
      state.entropy_blocks = @lib.entropy_scan(buffer.to_bytes())
      state.entropy_done = true
      state.entropy_sel = 0
    }
    state.entropy_view = true
    state.msg = "Entropy analysis"
  } else if key == 's'.to_int() || key == 'S'.to_int() {
    if !state.strings_done {
      state.strings_matches = @lib.find_strings(buffer.to_bytes())
      state.strings_done = true
      state.strings_sel = 0; state.strings_scroll = 0
    }
    state.strings_view = true
    let n = state.strings_matches.length()
    state.msg = if n > 0 { "\{n} strings (cached)" } else { "No strings found" }
  } else if key == 'c'.to_int() || key == 'C'.to_int() {
    state.codec_view = true
    state.codec_input = ""
    state.codec_result = ""
    state.msg = "Codec"
  } else if key == '?'.to_int() {
    state.msg = "q:quit g:goto /:hex f:text n/p:match e:edit t:struct b:bookmark h:entropy"
  }
}
