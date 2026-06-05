// Hex Editor — Editing Operations
// Higher-level editing operations built on HexBuffer primitives.

///|
/// Represents a single edit operation for patch-based editing.
struct EditOp {
  kind : EditKind
  offset : Int
  data : Bytes?     // for Set and Insert
  length : Int?     // for Delete and Fill
  fill_byte : Byte? // for Fill
} derive(Debug)

///|
/// The kind of edit operation.
enum EditKind {
  Set
  Insert
  Delete
  Fill
} derive(Debug, Eq)

///|
/// Creates a Set edit operation (overwrite bytes at offset).
pub fn edit_set(offset : Int, bytes : Bytes) -> EditOp {
  { kind: Set, offset, data: Some(bytes), length: None, fill_byte: None }
}

///|
/// Creates an Insert edit operation (insert bytes at offset).
pub fn edit_insert(offset : Int, bytes : Bytes) -> EditOp {
  { kind: Insert, offset, data: Some(bytes), length: None, fill_byte: None }
}

///|
/// Creates a Delete edit operation (delete bytes at offset).
pub fn edit_delete(offset : Int, count : Int) -> EditOp {
  { kind: Delete, offset, data: None, length: Some(count), fill_byte: None }
}

///|
/// Creates a Fill edit operation (fill range with byte value).
pub fn edit_fill(start : Int, end : Int, value : Byte) -> EditOp {
  {
    kind: Fill,
    offset: start,
    data: None,
    length: Some(end - start),
    fill_byte: Some(value),
  }
}

///|
/// Applies a single edit operation to a HexBuffer.
pub fn apply_edit(buffer : HexBuffer, op : EditOp) -> Bool {
  match op.kind {
    Set => match op.data {
      None => false
      Some(bytes) => {
        let count = bytes.length()
        buffer.replace_range(op.offset, count, bytes)
      }
    }
    Insert => match op.data {
      None => false
      Some(bytes) => buffer.insert_bytes(op.offset, bytes)
    }
    Delete => match op.length {
      None => false
      Some(count) => buffer.delete_bytes(op.offset, count)
    }
    Fill => match (op.length, op.fill_byte) {
      (Some(len), Some(b)) => buffer.fill_range(op.offset, op.offset + len, b)
      _ => false
    }
  }
}

///|
/// Applies a list of edit operations in order.
pub fn apply_edits(buffer : HexBuffer, ops : Array[EditOp]) -> Int {
  let mut count = 0
  for i = 0; i < ops.length(); i = i + 1 {
    if apply_edit(buffer, ops[i]) {
      count = count + 1
    }
  }
  count
}

///|
/// Represents a patch — a collection of edits with offset tracking.
struct Patch {
  ops : Array[EditOp]
}

///|
/// Creates a new empty patch.
pub fn Patch::new() -> Patch {
  { ops: [] }
}

///|
/// Adds a Set operation to the patch.
pub fn Patch::set(self : Patch, offset : Int, bytes : Bytes) -> Unit {
  self.ops.push(edit_set(offset, bytes))
}

///|
/// Adds an Insert operation to the patch.
pub fn Patch::insert(self : Patch, offset : Int, bytes : Bytes) -> Unit {
  self.ops.push(edit_insert(offset, bytes))
}

///|
/// Adds a Delete operation to the patch.
pub fn Patch::delete(self : Patch, offset : Int, count : Int) -> Unit {
  self.ops.push(edit_delete(offset, count))
}

///|
/// Adds a Fill operation to the patch.
pub fn Patch::fill(
  self : Patch,
  start : Int,
  end : Int,
  value : Byte,
) -> Unit {
  self.ops.push(edit_fill(start, end, value))
}

///|
/// Returns the number of operations in the patch.
pub fn Patch::length(self : Patch) -> Int {
  self.ops.length()
}

///|
/// Applies all operations in the patch to a HexBuffer.
pub fn Patch::apply(self : Patch, buffer : HexBuffer) -> Int {
  apply_edits(buffer, self.ops)
}

///|
/// Applies patch operations sorted by offset (descending).
/// This is useful when edits at different offsets should not affect each other.
pub fn Patch::apply_sorted(self : Patch, buffer : HexBuffer) -> Int {
  let sorted = sort_ops_by_offset_desc(self.ops)
  apply_edits(buffer, sorted)
}

///|
/// Sorts edit operations by offset in descending order.
fn sort_ops_by_offset_desc(ops : Array[EditOp]) -> Array[EditOp] {
  let n = ops.length()
  // Create a copy
  let sorted : Array[EditOp] = []
  for i = 0; i < n; i = i + 1 {
    sorted.push(ops[i])
  }
  // Bubble sort by offset descending
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n - i - 1; j = j + 1 {
      if sorted[j].offset < sorted[j + 1].offset {
        let temp = sorted[j]
        sorted[j] = sorted[j + 1]
        sorted[j + 1] = temp
      }
    }
  }
  sorted
}

///|
/// Modifies a single byte in the buffer at the specified offset.
pub fn modify_byte(
  buffer : HexBuffer,
  offset : Int,
  value : Byte,
) -> Bool {
  buffer.set_byte(offset, value)
}

///|
/// Modifies multiple consecutive bytes starting at an offset.
pub fn modify_bytes(
  buffer : HexBuffer,
  offset : Int,
  values : Bytes,
) -> Int {
  let len = values.length()
  let mut count = 0
  for i = 0; i < len; i = i + 1 {
    if buffer.set_byte(offset + i, values[i]) {
      count = count + 1
    }
  }
  count
}

///|
/// Inserts bytes at an offset. Convenience wrapper.
pub fn insert_bytes(
  buffer : HexBuffer,
  offset : Int,
  bytes : Bytes,
) -> Bool {
  buffer.insert_bytes(offset, bytes)
}

///|
/// Deletes bytes at an offset. Convenience wrapper.
pub fn delete_bytes(
  buffer : HexBuffer,
  offset : Int,
  count : Int,
) -> Bool {
  buffer.delete_bytes(offset, count)
}

///|
/// Fills a range with a byte value. Convenience wrapper.
pub fn fill_range(
  buffer : HexBuffer,
  start : Int,
  end : Int,
  value : Byte,
) -> Bool {
  buffer.fill_range(start, end, value)
}

///|
/// Fills a range with zeros (nop out bytes).
pub fn nop_range(buffer : HexBuffer, start : Int, end : Int) -> Bool {
  buffer.fill_range(start, end, b'\x00')
}

///|
/// Replaces a range with new data. Convenience wrapper.
pub fn replace_range(
  buffer : HexBuffer,
  offset : Int,
  count : Int,
  new_data : Bytes,
) -> Bool {
  buffer.replace_range(offset, count, new_data)
}

///|
/// Swaps two byte ranges of equal length.
pub fn swap_ranges(
  buffer : HexBuffer,
  offset_a : Int,
  offset_b : Int,
  length : Int,
) -> Bool {
  guard offset_a >= 0 && offset_b >= 0 && length > 0 else { false }
  guard offset_a + length <= buffer.length() else { false }
  guard offset_b + length <= buffer.length() else { false }
  guard offset_a + length <= offset_b || offset_b + length <= offset_a else {
    false // Ranges overlap
  }

  let temp = FixedArray::make(length, Byte::default())
  let data = buffer.to_fixedarray()
  // Copy A to temp
  for i = 0; i < length; i = i + 1 {
    temp[i] = data[offset_a + i]
  }
  // Copy B to A
  for i = 0; i < length; i = i + 1 {
    buffer.set_byte(offset_a + i, data[offset_b + i]) |> ignore
  }
  // Copy temp to B
  for i = 0; i < length; i = i + 1 {
    buffer.set_byte(offset_b + i, temp[i]) |> ignore
  }
  true
}

///|
/// Copies a range of bytes from one offset to another.
pub fn copy_range(
  buffer : HexBuffer,
  src_offset : Int,
  dst_offset : Int,
  length : Int,
) -> Bool {
  guard src_offset >= 0 && dst_offset >= 0 && length > 0 else { false }
  guard src_offset + length <= buffer.length() else { false }
  guard dst_offset + length <= buffer.length() else { false }

  let data = buffer.to_fixedarray()
  if dst_offset <= src_offset {
    // Copy forward
    for i = 0; i < length; i = i + 1 {
      buffer.set_byte(dst_offset + i, data[src_offset + i]) |> ignore
    }
  } else {
    // Copy backward to handle overlapping regions
    for i = length - 1; i >= 0; i = i - 1 {
      buffer.set_byte(dst_offset + i, data[src_offset + i]) |> ignore
    }
  }
  true
}
