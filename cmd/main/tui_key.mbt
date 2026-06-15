// TUI key handlers — bookmark, struct, edit, and normal mode key dispatch

///|
/// Mutable TUI state passed to key handlers.
struct TuiState {
  mut offset : Int
  mut msg : String
  mut results : Array[Int]
  mut result_idx : Int
  mut match_len : Int
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
  mut undo_stack : Array[UndoOp]
  mut redo_stack : Array[UndoOp]
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
    entropy_view: false, entropy_sel: 0, entropy_blocks: [],
    undo_stack: [],
    redo_stack: [],
  }
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
  // ====== Bookmark popup (in tui_bookmark.mbt) ======
  } else if state.bookmark_view && handle_bookmark_popup_key(state, key, screen_rows) {
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
  } else if (state.scan_view || state.entropy_view) && key != 'w'.to_int() && key != 'W'.to_int() {
    ()

  // ====== Edit mode keys ======
  } else if state.edit_mode && key == 27 {
    if state.edit_modified && !state.esc_pending {
      state.esc_pending = true
      state.msg = "Unsaved edits! Press Esc again to discard, Ctrl+S to save"
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
    state.redo_stack = []; state.scan_done = false
    buffer.delete_byte(state.edit_off) |> ignore
    if state.edit_off >= buffer.length() && state.edit_off > 0 { state.edit_off = state.edit_off - 1 }
    state.results = []
    state.match_len = 0
    state.msg = "Deleted 1 byte\{depth_suffix(state.undo_stack.length(), state.redo_stack.length())}"

  } else if state.edit_mode && (key == 'i'.to_int() || key == 'I'.to_int()) {
    state.edit_modified = true
    state.esc_pending = false
    state.undo_stack.push({ kind: 1, offset: state.edit_off, old_byte: b'\x00' })
    state.redo_stack = []; state.scan_done = false
    buffer.insert_byte(state.edit_off, b'\x00') |> ignore
    state.msg = "Inserted 00\{depth_suffix(state.undo_stack.length(), state.redo_stack.length())}"

  } else if state.edit_mode && !state.edit_ascii && key >= '0'.to_int() && key <= '9'.to_int() {
    state.edit_modified = true; state.esc_pending = false; state.redo_stack = []; state.scan_done = false
    let (new_off, new_nib, new_msg, undo) = handle_hex_input(buffer, state.edit_off, state.edit_nibble, key)
    state.edit_off = new_off; state.edit_nibble = new_nib
    match undo { Some(op) => state.undo_stack.push(op); None => () }
    state.msg = "\{new_msg}\{depth_suffix(state.undo_stack.length(), state.redo_stack.length())}"

  } else if state.edit_mode && !state.edit_ascii && key >= 'a'.to_int() && key <= 'f'.to_int() {
    state.edit_modified = true; state.esc_pending = false; state.redo_stack = []; state.scan_done = false
    let (new_off, new_nib, new_msg, undo) = handle_hex_input(buffer, state.edit_off, state.edit_nibble, key)
    state.edit_off = new_off; state.edit_nibble = new_nib
    match undo { Some(op) => state.undo_stack.push(op); None => () }
    state.msg = "\{new_msg}\{depth_suffix(state.undo_stack.length(), state.redo_stack.length())}"

  } else if state.edit_mode && !state.edit_ascii && key >= 'A'.to_int() && key <= 'F'.to_int() {
    state.edit_modified = true; state.esc_pending = false; state.redo_stack = []; state.scan_done = false
    let lower = key + ('a'.to_int() - 'A'.to_int())
    let (new_off, new_nib, new_msg, undo) = handle_hex_input(buffer, state.edit_off, state.edit_nibble, lower)
    state.edit_off = new_off; state.edit_nibble = new_nib
    match undo { Some(op) => state.undo_stack.push(op); None => () }
    state.msg = "\{new_msg}\{depth_suffix(state.undo_stack.length(), state.redo_stack.length())}"

  } else if state.edit_mode && state.edit_ascii && key >= 32 && key <= 126 {
    state.edit_modified = true; state.esc_pending = false; state.edit_nibble = None; state.redo_stack = []; state.scan_done = false
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

  } else if state.edit_mode && key == 19 {
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
    if state.results.length() > 0 { state.results = []; state.match_len = 0; state.msg = "Search cleared" }
  } else if key == 'q'.to_int() || key == 'Q'.to_int() {
    state.running = false

  } else if !state.bookmark_view && !state.scan_view && key == -1 {
    if state.offset >= 16 { state.offset = state.offset - 16 }

  } else if !state.bookmark_view && !state.scan_view && key == -2 {
    if state.offset + 16 < buffer.length() { state.offset = state.offset + 16 }

  } else if !state.bookmark_view && !state.scan_view && key == -3 {
    let page = screen_rows * 16
    if state.offset >= page { state.offset = state.offset - page } else { state.offset = 0 }

  } else if !state.bookmark_view && !state.scan_view && key == -4 {
    let page = screen_rows * 16
    if state.offset + page < buffer.length() { state.offset = state.offset + page }
    else { let last_off = if buffer.length() > 0 { ((buffer.length() - 1) / 16) * 16 } else { 0 }; if state.offset < last_off { state.offset = last_off } }

  } else if !state.bookmark_view && !state.scan_view && key == -7 {
    state.offset = 0

  } else if !state.bookmark_view && !state.scan_view && key == -8 {
    let len = buffer.length()
    let rows = if len > 0 { (len - 1) / 16 } else { 0 }
    state.offset = rows * 16

  } else if key == '/'.to_int() {
    let pattern = tui_read_line("Hex search: ")
    if pattern != "" {
      match @lib.parse_hex_string(pattern) {
        Some(bytes) => {
          let data = buffer.to_bytes()
          state.results = @lib.find_all_bytes(data, bytes)
          if state.results.length() > 0 {
            state.result_idx = 0; state.match_len = bytes.length()
            state.offset = scroll_to_show(state.results[0], state.offset, buffer.length(), screen_rows)
            state.msg = "Hex: \{state.results.length()} matches (n:next)"
          } else { state.msg = "Not found"; state.results = []; state.match_len = 0 }
        }
        None => state.msg = "Invalid hex (FF D8 or FF00)"
      }
    }

  } else if key == 'f'.to_int() || key == 'F'.to_int() {
    let pattern = tui_read_line("Text search: ")
    if pattern != "" {
      let bytes = ascii_to_bytes(pattern)
      state.match_len = bytes.length()
      let data = buffer.to_bytes()
      state.results = @lib.find_all_bytes(data, bytes)
      if state.results.length() > 0 {
        state.result_idx = 0
        state.offset = scroll_to_show(state.results[0], state.offset, buffer.length(), screen_rows)
        state.msg = "Text: \{state.results.length()} matches (n:next)"
      } else { state.msg = "Not found"; state.results = []; state.match_len = 0 }
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
      state.edit_mode = true; state.edit_off = state.offset; state.edit_nibble = None; state.edit_ascii = false
      state.msg = "Entered edit mode"
    } else { state.msg = "Nothing to edit" }

  } else if key == 't'.to_int() || key == 'T'.to_int() {
    state.struct_view = !state.struct_view
    state.msg = if state.struct_view { "Structure view" } else { "Hex view" }

  // Bookmark keys (in tui_bookmark.mbt)
  } else if handle_bookmark_normal_key(state, key) {
    ()

  } else if key == 'w'.to_int() || key == 'W'.to_int() {
    if state.scan_view {
      state.scan_view = false; state.msg = "Hex view"
    } else if state.scan_done {
      state.scan_view = true; state.scan_sel = 0; state.scan_scroll = 0
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
    state.entropy_blocks = @lib.entropy_scan(buffer.to_bytes())
    state.entropy_sel = 0
    state.entropy_view = true
    state.msg = "Entropy analysis"
  } else if key == '?'.to_int() {
    state.msg = "q:quit g:goto /:hex f:text n/p:match e:edit t:struct b:bookmark h:entropy"
  }
}
