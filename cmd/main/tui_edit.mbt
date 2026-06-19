// TUI edit mode — hex/ASCII input, undo, redo
// Supports compound undo for paste operations (kind 3/4).

///|
/// Undo operation record.
struct UndoOp {
  kind : Int           // 0=modify, 1=insert, 2=delete, 3=paste_overwrite, 4=paste_insert
  offset : Int
  old_byte : Byte      // for kind 0/1/2
  old_bytes : Array[Byte]  // for kind 3 (original bytes before paste)
  count : Int          // for kind 3/4 (number of bytes pasted)
} derive(Debug)

///|
/// Create a single-byte undo op.
pub fn undo_op(kind : Int, offset : Int, old_byte : Byte) -> UndoOp {
  { kind, offset, old_byte, old_bytes: [], count: 1 }
}

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
      let new_off = if edit_off + 1 < buffer.length() { edit_off + 1 } else { edit_off }
      (new_off, None, "Set 0x\{@lib.format_byte_hex(byte_val)}", Some(undo_op(0, edit_off, old)))
    }
  }
}

///|
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
    } else if op.kind == 2 {
      buffer.insert_byte(op.offset, op.old_byte) |> ignore
    } else if op.kind == 3 {
      // Paste overwrite: restore original bytes
      for j = 0; j < op.old_bytes.length(); j = j + 1 {
        buffer.set_byte(op.offset + j, op.old_bytes[j]) |> ignore
      }
    } else if op.kind == 4 {
      // Paste insert: delete inserted bytes
      for j = 0; j < op.count; j = j + 1 {
        buffer.delete_byte(op.offset) |> ignore
      }
    }
  }
}

///|
/// Apply a single undo operation. Returns the redo op.
pub fn apply_undo(buffer : @lib.HexBuffer, op : UndoOp) -> UndoOp {
  if op.kind == 0 {
    let current = match buffer.get_byte(op.offset) { Some(b) => b; None => b'\x00' }
    buffer.set_byte(op.offset, op.old_byte) |> ignore
    undo_op(0, op.offset, current)
  } else if op.kind == 1 {
    buffer.delete_byte(op.offset) |> ignore
    undo_op(2, op.offset, b'\x00')
  } else if op.kind == 2 {
    buffer.insert_byte(op.offset, op.old_byte) |> ignore
    undo_op(1, op.offset, op.old_byte)
  } else if op.kind == 3 {
    // Undo paste overwrite: save current (pasted) bytes, restore old
    let pasted : Array[Byte] = []
    for j = 0; j < op.old_bytes.length(); j = j + 1 {
      let cur = match buffer.get_byte(op.offset + j) { Some(b) => b; None => b'\x00' }
      pasted.push(cur)
      buffer.set_byte(op.offset + j, op.old_bytes[j]) |> ignore
    }
    { kind: 3, offset: op.offset, old_byte: b'\x00', old_bytes: pasted, count: op.count }
  } else {
    // kind 4: Undo paste insert: save inserted bytes, delete them
    let saved : Array[Byte] = []
    for j = 0; j < op.count; j = j + 1 {
      let cur = match buffer.get_byte(op.offset) { Some(b) => b; None => b'\x00' }
      saved.push(cur)
      buffer.delete_byte(op.offset) |> ignore
    }
    { kind: 4, offset: op.offset, old_byte: b'\x00', old_bytes: saved, count: op.count }
  }
}

///|
/// Apply a single redo operation. Returns the undo op.
pub fn apply_redo(buffer : @lib.HexBuffer, op : UndoOp) -> UndoOp {
  if op.kind == 0 {
    let current = match buffer.get_byte(op.offset) { Some(b) => b; None => b'\x00' }
    buffer.set_byte(op.offset, op.old_byte) |> ignore
    undo_op(0, op.offset, current)
  } else if op.kind == 1 {
    buffer.insert_byte(op.offset, op.old_byte) |> ignore
    undo_op(2, op.offset, op.old_byte)
  } else if op.kind == 2 {
    let captured = match buffer.get_byte(op.offset) { Some(b) => b; None => b'\x00' }
    buffer.delete_byte(op.offset) |> ignore
    undo_op(2, op.offset, captured)
  } else if op.kind == 3 {
    // Redo paste overwrite: save current, overwrite with old_bytes (pasted bytes)
    let saved : Array[Byte] = []
    for j = 0; j < op.old_bytes.length(); j = j + 1 {
      let cur = match buffer.get_byte(op.offset + j) { Some(b) => b; None => b'\x00' }
      saved.push(cur)
      buffer.set_byte(op.offset + j, op.old_bytes[j]) |> ignore
    }
    { kind: 3, offset: op.offset, old_byte: b'\x00', old_bytes: saved, count: op.count }
  } else {
    // kind 4: Redo paste insert: re-insert old_bytes
    for j = 0; j < op.old_bytes.length(); j = j + 1 {
      buffer.insert_byte(op.offset + j, op.old_bytes[j]) |> ignore
    }
    { kind: 4, offset: op.offset, old_byte: b'\x00', old_bytes: [], count: op.count }
  }
}

///|
pub fn pop_last(stack : Array[UndoOp]) -> (Array[UndoOp], UndoOp?) {
  let len = stack.length()
  guard len > 0 else { ([], None) }
  let last = len - 1
  let new_stack : Array[UndoOp] = []
  for i = 0; i < last; i = i + 1 { new_stack.push(stack[i]) }
  (new_stack, Some(stack[last]))
}

///|
pub fn depth_suffix(undo_len : Int, redo_len : Int) -> String {
  if undo_len == 0 && redo_len == 0 { "" }
  else { " (undo:\{undo_len} redo:\{redo_len})" }
}
