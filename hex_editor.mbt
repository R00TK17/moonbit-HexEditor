// Hex Editor — Core Library
// HexBuffer with Gap Buffer for O(1) insert/delete at cursor.
//
// Gap Buffer Layout:
//   [data_before_gap | ___gap___ | data_after_gap]
//    0..gap_start     gap_start..gap_end   gap_end..data.length()
//
// Logical view (what the user sees):
//   [data_before_gap | data_after_gap]  (gap is invisible)
//   len = data.length() - (gap_end - gap_start)
//
// Gap size = file disk allocation (rounded to 4KB cluster) / 16.
// Insert/delete at gap: O(1). Moving gap: O(distance). Read: O(1).

///|
/// A mutable buffer for hex editing with Gap Buffer optimization.
///
/// Physical layout: `[bytes | gap | bytes]`
/// - `gap_start`: first index of the gap
/// - `gap_end`: first index after the gap
/// - `len`: logical byte count (excluding gap)
///
/// The gap moves to the edit cursor on insert/delete.
/// Consecutive edits at the same position are O(1).
struct HexBuffer {
  mut data : FixedArray[Byte]
  mut gap_start : Int // first gap index (inclusive)
  mut gap_end : Int // first post-gap index (exclusive)
  mut len : Int // logical length = data.length() - gap_size
  mut modified : Bool
  mut file_path : String?
}

///|
/// Gap size = disk allocation / 16, minimum 256 bytes.
/// Disk allocation = file_size rounded up to 4KB cluster boundary.
fn calc_gap_size(file_size : Int) -> Int {
  let alloc = (file_size + 4095) / 4096 * 4096
  let g = alloc / 16
  if g < 256 {
    256
  } else {
    g
  }
}

///|
/// Creates a new empty HexBuffer with 256-byte initial gap.
pub fn HexBuffer::new() -> HexBuffer {
  {
    data: FixedArray::make(256, Byte::default()),
    gap_start: 0,
    gap_end: 256,
    len: 0,
    modified: false,
    file_path: None,
  }
}

///|
/// Creates a HexBuffer from bytes. Gap is placed at the end.
/// Layout: [file_bytes | gap]
pub fn HexBuffer::from_bytes(bytes : Bytes) -> HexBuffer {
  let file_size = bytes.length()
  let gap = calc_gap_size(file_size)
  let total = file_size + gap
  let data = FixedArray::make(total, Byte::default())
  data.blit_from_bytes(0, bytes, 0, file_size)
  {
    data,
    gap_start: file_size,
    gap_end: total,
    len: file_size,
    modified: false,
    file_path: None,
  }
}

///|
pub fn HexBuffer::set_file_path(self : HexBuffer, path : String) -> Unit {
  self.file_path = Some(path)
}

///|
pub fn HexBuffer::from_file(path : String) -> HexBuffer raise {
  let bytes = @fs.read_file_to_bytes(path)
  let buf = HexBuffer::from_bytes(bytes)
  buf.file_path = Some(path)
  buf
}

///|
pub fn HexBuffer::length(self : HexBuffer) -> Int {
  self.len
}

///|
pub fn HexBuffer::is_empty(self : HexBuffer) -> Bool {
  self.len == 0
}

///|
pub fn HexBuffer::is_modified(self : HexBuffer) -> Bool {
  self.modified
}

///|
pub fn HexBuffer::get_file_path(self : HexBuffer) -> String? {
  self.file_path
}

///|
/// Convert logical index to physical index, skipping over the gap.
///   logical 0..gap_start  → physical same
///   logical gap_start..   → physical + gap_size
fn HexBuffer::to_physical(self : HexBuffer, idx : Int) -> Int {
  if idx < self.gap_start {
    idx
  } else {
    idx + self.gap_end - self.gap_start
  }
}

///|
/// Safe byte read with bounds check.
pub fn HexBuffer::get_byte(self : HexBuffer, offset : Int) -> Byte? {
  guard offset >= 0 && offset < self.len else { None }
  Some(self.data[self.to_physical(offset)])
}

///|
/// Fast byte read for rendering (no bounds check, no Option).
/// Caller must ensure idx < self.len.
pub fn HexBuffer::byte_at(self : HexBuffer, idx : Int) -> Byte {
  self.data[self.to_physical(idx)]
}

///|
/// Set byte at logical offset. Returns false if out of bounds.
pub fn HexBuffer::set_byte(
  self : HexBuffer,
  offset : Int,
  value : Byte,
) -> Bool {
  guard offset >= 0 && offset < self.len else { false }
  self.data[self.to_physical(offset)] = value
  self.modified = true
  true
}

///|
/// Move the gap so that gap_start == pos.
///
/// Two cases:
///   pos < gap_start: move bytes [pos, gap_start) to end of gap
///     [AAA|_____|BBB]  →  [A|_____|AABBB]
///
///   pos > gap_start: move bytes [gap_end, gap_end+delta) to start of gap
///     [AAA|_____|BBB]  →  [AAAB|_____|BB]
fn HexBuffer::move_gap(self : HexBuffer, pos : Int) -> Unit {
  if pos == self.gap_start {
    return
  }
  let gap_size = self.gap_end - self.gap_start
  if pos < self.gap_start {
    // Shift bytes leftward into the gap's tail
    let n = self.gap_start - pos
    for i = n - 1; i >= 0; i = i - 1 {
      self.data[self.gap_end - n + i] = self.data[pos + i]
    }
    self.gap_start = pos
    self.gap_end = pos + gap_size
  } else {
    // Shift bytes rightward into the gap's head
    let n = pos - self.gap_start
    for i = 0; i < n; i = i + 1 {
      self.data[self.gap_start + i] = self.data[self.gap_end + i]
    }
    self.gap_start = pos
    self.gap_end = pos + gap_size
  }
}

///|
/// Grow the gap when exhausted (gap_start == gap_end).
/// Allocates new array with fresh gap at current gap_start position.
fn HexBuffer::grow_gap(self : HexBuffer) -> Unit {
  let new_gap = calc_gap_size(self.len)
  let new_total = self.len + new_gap
  let new_data = FixedArray::make(new_total, Byte::default())
  // Copy bytes before gap
  new_data.unsafe_blit(0, self.data, 0, self.gap_start)
  // Copy bytes after gap (skip old gap, place after new gap)
  let after_len = self.len - self.gap_start
  let new_gap_end = self.gap_start + new_gap
  if after_len > 0 {
    new_data.unsafe_blit(new_gap_end, self.data, self.gap_end, after_len)
  }
  self.data = new_data
  self.gap_end = new_gap_end
}

///|
/// Insert a byte at logical offset. O(1) if gap is already at offset.
/// 1. Grow gap if exhausted
/// 2. Move gap to offset
/// 3. Write byte into gap_start, advance gap_start
pub fn HexBuffer::insert_byte(
  self : HexBuffer,
  offset : Int,
  value : Byte,
) -> Bool {
  guard offset >= 0 && offset <= self.len else { false }
  if self.gap_start == self.gap_end {
    self.grow_gap()
  }
  self.move_gap(offset)
  self.data[self.gap_start] = value
  self.gap_start = self.gap_start + 1
  self.len = self.len + 1
  self.modified = true
  true
}

///|
/// Delete byte at logical offset. O(1) if gap is already at offset.
/// 1. Move gap to offset
/// 2. Expand gap_end by 1 (the byte at gap_end is "deleted")
pub fn HexBuffer::delete_byte(self : HexBuffer, offset : Int) -> Bool {
  guard offset >= 0 && offset < self.len else { false }
  self.move_gap(offset)
  self.gap_end = self.gap_end + 1
  self.len = self.len - 1
  self.modified = true
  true
}

///|
/// Compact copy of logical bytes (no gap).
pub fn HexBuffer::to_bytes(self : HexBuffer) -> Bytes {
  if self.len == 0 {
    return b""
  }
  Bytes::makei(self.len, fn(i) { self.data[self.to_physical(i)] })
}

///|
pub fn HexBuffer::to_fixedarray(self : HexBuffer) -> FixedArray[Byte] {
  if self.len == 0 {
    return []
  }
  let arr = FixedArray::make(self.len, Byte::default())
  if self.gap_start > 0 {
    arr.unsafe_blit(0, self.data, 0, self.gap_start)
  }
  let after = self.len - self.gap_start
  if after > 0 {
    arr.unsafe_blit(self.gap_start, self.data, self.gap_end, after)
  }
  arr
}

///|
/// Returns internal data array (includes gap). Use byte_at() for correct access.
pub fn HexBuffer::data_ref(self : HexBuffer) -> FixedArray[Byte] {
  self.data
}

///|
pub fn HexBuffer::save(self : HexBuffer, path? : String) -> Unit raise {
  let save_path = match path {
    Some(p) => p
    None =>
      match self.file_path {
        Some(p) => p
        None => raise @fs.IOError::IOError("No file path specified for save")
      }
  }
  let bytes = self.to_bytes()
  @fs.write_bytes_to_file(save_path, bytes)
  self.modified = false
  self.file_path = Some(save_path)
}
