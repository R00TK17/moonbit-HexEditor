// TUI edit mode — hex/ASCII input, undo, redo

///|
/// Undo operation record.
struct UndoOp {
  kind : Int     // 0=modify, 1=insert, 2=delete
  offset : Int
  old_byte : Byte
} derive(Debug)

///|
/// Handle hex digit input in edit mode. Returns (new_off, new_nibble, msg, undo).
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
/// Revert all edits using the undo stack (in reverse order).
fn revert_all_edits(buffer : @lib.HexBuffer, undo_stack : Array[UndoOp]) -> Unit {
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
/// Apply a single undo operation to the buffer.
/// Returns the corresponding redo operation that can re-apply the original edit.
pub fn apply_undo(
  buffer : @lib.HexBuffer,
  op : UndoOp,
) -> UndoOp {
  if op.kind == 0 {
    // Modify: capture current (the "new" value), restore old
    let current = match buffer.get_byte(op.offset) { Some(b) => b; None => b'\x00' }
    buffer.set_byte(op.offset, op.old_byte) |> ignore
    { kind: 0, offset: op.offset, old_byte: current }
  } else if op.kind == 1 {
    // Insert → delete
    buffer.delete_byte(op.offset) |> ignore
    { kind: 2, offset: op.offset, old_byte: b'\x00' }
  } else {
    // Delete → re-insert
    buffer.insert_byte(op.offset, op.old_byte) |> ignore
    { kind: 1, offset: op.offset, old_byte: op.old_byte }
  }
}

///|
/// Apply a single redo operation to the buffer.
/// Returns the corresponding undo operation for future undo.
pub fn apply_redo(
  buffer : @lib.HexBuffer,
  op : UndoOp,
) -> UndoOp {
  if op.kind == 0 {
    // Re-modify: capture current, set to saved value
    let current = match buffer.get_byte(op.offset) { Some(b) => b; None => b'\x00' }
    buffer.set_byte(op.offset, op.old_byte) |> ignore
    { kind: 0, offset: op.offset, old_byte: current }
  } else if op.kind == 1 {
    // Re-insert
    buffer.insert_byte(op.offset, op.old_byte) |> ignore
    { kind: 2, offset: op.offset, old_byte: op.old_byte }
  } else {
    // Re-delete
    let captured = match buffer.get_byte(op.offset) { Some(b) => b; None => b'\x00' }
    buffer.delete_byte(op.offset) |> ignore
    { kind: 2, offset: op.offset, old_byte: captured }
  }
}

///|
/// Pop the last element from an array and return (new_array, popped_element).
pub fn pop_last(stack : Array[UndoOp]) -> (Array[UndoOp], UndoOp?) {
  let len = stack.length()
  guard len > 0 else { ([], None) }
  let last = len - 1
  let new_stack : Array[UndoOp] = []
  for i = 0; i < last; i = i + 1 {
    new_stack.push(stack[i])
  }
  (new_stack, Some(stack[last]))
}

///|
/// Build depth display suffix for status messages.
pub fn depth_suffix(undo_len : Int, redo_len : Int) -> String {
  if undo_len == 0 && redo_len == 0 { "" }
  else { " (undo:\{undo_len} redo:\{redo_len})" }
}
