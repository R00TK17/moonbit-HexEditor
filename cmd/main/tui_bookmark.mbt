// Bookmark module — popup rendering, key handling, and bookmark state

///|
/// Handle a keypress when the bookmark popup is open.
/// Returns true if the key was handled and the dispatch chain should stop.
pub fn handle_bookmark_popup_key(
  state : TuiState,
  key : Int,
  screen_rows : Int,
) -> Bool {
  if key == -1 {
    if state.bookmark_sel > 0 { state.bookmark_sel = state.bookmark_sel - 1 }
    // Auto-scroll: keep selected slot visible
    if state.bookmark_sel < state.bookmark_scroll {
      state.bookmark_scroll = state.bookmark_sel
    }
    true
  } else if key == -2 {
    if state.bookmark_sel < 20 { state.bookmark_sel = state.bookmark_sel + 1 }
    let max_visible = if screen_rows > 1 { screen_rows - 1 } else { 1 }
    if state.bookmark_sel >= state.bookmark_scroll + max_visible {
      state.bookmark_scroll = state.bookmark_sel - max_visible + 1
    }
    true
  } else if key == 13 {
    match state.bookmarks[state.bookmark_sel] {
      None => state.msg = "Bookmark " + state.bookmark_sel.to_string() + " is empty"
      Some(off) => {
        state.offset = (off / 16) * 16
        state.bookmark_view = false
        state.msg = "Jumped to bookmark " + state.bookmark_sel.to_string() + ": 0x" + @lib.to_hex_string(off, width=8)
      }
    }
    true
  } else if key == 'd'.to_int() || key == 'D'.to_int() {
    state.bookmarks[state.bookmark_sel] = None
    state.msg = "Bookmark " + state.bookmark_sel.to_string() + " deleted"
    true
  } else if key == 'q'.to_int() || key == 'Q'.to_int() {
    state.running = false
    true
  } else if key == 'b'.to_int() || key == 'B'.to_int() {
    state.bookmark_view = false
    state.msg = "Hex view"
    true
  } else if key == 27 {
    state.bookmark_view = false
    state.msg = "Hex view"
    true
  } else {
    true  // Swallow all other keys when popup is open
  }
}

///|
/// Handle bookmark-related keys in normal mode (b toggle, Ctrl+B set).
/// Returns true if the key was handled.
pub fn handle_bookmark_normal_key(
  state : TuiState,
  key : Int,
) -> Bool {
  if key == 'b'.to_int() || key == 'B'.to_int() {
    state.bookmark_view = !state.bookmark_view
    state.msg = if state.bookmark_view { "Bookmark view" } else { "Hex view" }
    true
  } else if key == 2 {
    // Ctrl+B: set bookmark at current offset
    let mut slot = -1
    for i = 0; i < 21; i = i + 1 {
      match state.bookmarks[i] { None => { slot = i; break }; _ => () }
    }
    if slot < 0 { slot = 0 }
    state.bookmarks[slot] = Some(state.offset)
    state.msg = "Bookmark " + slot.to_string() + " set at 0x" + @lib.to_hex_string(state.offset, width=8)
    true
  } else {
    false
  }
}
