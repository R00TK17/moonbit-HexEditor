// Hex Editor — Core Library
// HexBuffer with Gap Buffer for O(1) insert/delete at cursor.
// Gap size = file allocation size (rounded to 4KB cluster) / 16.

///|
/// A mutable buffer for hex editing with Gap Buffer optimization.
/// The internal array has a "gap" at the edit position.
/// Insert/delete at the gap is O(1); moving the gap is O(distance).
struct HexBuffer {
  mut data : FixedArray[Byte]
  mut gap_start : Int
  mut gap_end : Int
  mut len : Int
  mut modified : Bool
  mut file_path : String?
}

///|
/// Calculate gap size: allocation_size / 16, min 256.
fn calc_gap_size(file_size : Int) -> Int {
  let alloc = ((file_size + 4095) / 4096) * 4096
  let g = alloc / 16
  if g < 256 { 256 } else { g }
}

///|
/// Creates a new empty HexBuffer.
pub fn HexBuffer::new() -> HexBuffer {
  { data: FixedArray::make(256, Byte::default()), gap_start: 0, gap_end: 256, len: 0, modified: false, file_path: None }
}

///|
/// Creates a HexBuffer from a Bytes sequence with gap buffer.
pub fn HexBuffer::from_bytes(bytes : Bytes) -> HexBuffer {
  let file_size = bytes.length()
  let gap = calc_gap_size(file_size)
  let total = file_size + gap
  let data = FixedArray::make(total, Byte::default())
  // Copy all bytes, gap at end
  data.blit_from_bytes(0, bytes, 0, file_size)
  { data, gap_start: file_size, gap_end: total, len: file_size, modified: false, file_path: None }
}

///|
/// Sets the file path associated with this buffer.
pub fn HexBuffer::set_file_path(self : HexBuffer, path : String) -> Unit {
  self.file_path = Some(path)
}

///|
/// Loads a HexBuffer from a file.
pub fn HexBuffer::from_file(path : String) -> HexBuffer raise {
  let bytes = @fs.read_file_to_bytes(path)
  let buf = HexBuffer::from_bytes(bytes)
  buf.file_path = Some(path)
  buf
}

///|
/// Returns the current logical length of the buffer.
pub fn HexBuffer::length(self : HexBuffer) -> Int {
  self.len
}

///|
/// Returns whether the buffer is empty.
pub fn HexBuffer::is_empty(self : HexBuffer) -> Bool {
  self.len == 0
}

///|
/// Returns whether the buffer has been modified.
pub fn HexBuffer::is_modified(self : HexBuffer) -> Bool {
  self.modified
}

///|
/// Gets the file path associated with this buffer.
pub fn HexBuffer::get_file_path(self : HexBuffer) -> String? {
  self.file_path
}

///|
/// Convert logical index to physical index (accounting for gap).
fn HexBuffer::to_physical(self : HexBuffer, idx : Int) -> Int {
  if idx < self.gap_start { idx } else { idx + self.gap_end - self.gap_start }
}

///|
/// Gets the byte at the specified logical offset.
pub fn HexBuffer::get_byte(self : HexBuffer, offset : Int) -> Byte? {
  guard offset >= 0 && offset < self.len else { None }
  Some(self.data[self.to_physical(offset)])
}

///|
/// Fast byte access for rendering — no bounds check, no Option.
pub fn HexBuffer::byte_at(self : HexBuffer, idx : Int) -> Byte {
  self.data[self.to_physical(idx)]
}

///|
/// Sets the byte at the specified logical offset.
pub fn HexBuffer::set_byte(self : HexBuffer, offset : Int, value : Byte) -> Bool {
  guard offset >= 0 && offset < self.len else { false }
  self.data[self.to_physical(offset)] = value
  self.modified = true
  true
}

///|
/// Move the gap to the specified logical position.
fn HexBuffer::move_gap(self : HexBuffer, pos : Int) -> Unit {
  if pos == self.gap_start { return }
  let gap_size = self.gap_end - self.gap_start
  if pos < self.gap_start {
    // Move bytes [pos, gap_start) to end of gap
    let n = self.gap_start - pos
    for i = n - 1; i >= 0; i = i - 1 {
      self.data[self.gap_end - n + i] = self.data[pos + i]
    }
    self.gap_start = pos
    self.gap_end = pos + gap_size
  } else {
    // Move bytes [gap_end, gap_end + (pos - gap_start)) to start of gap
    let n = pos - self.gap_start
    for i = 0; i < n; i = i + 1 {
      self.data[self.gap_start + i] = self.data[self.gap_end + i]
    }
    self.gap_start = pos
    self.gap_end = pos + gap_size
  }
}

///|
/// Grow the gap when exhausted.
fn HexBuffer::grow_gap(self : HexBuffer) -> Unit {
  let new_gap = calc_gap_size(self.len)
  let new_total = self.len + new_gap
  let new_data = FixedArray::make(new_total, Byte::default())
  // Copy before gap
  new_data.unsafe_blit(0, self.data, 0, self.gap_start)
  // Copy after gap
  let after_len = self.len - self.gap_start
  let new_gap_end = self.gap_start + new_gap
  if after_len > 0 {
    new_data.unsafe_blit(new_gap_end, self.data, self.gap_end, after_len)
  }
  self.data = new_data
  self.gap_end = new_gap_end
}

///|
/// Inserts a byte at the specified logical offset. O(1) at gap, O(d) otherwise.
pub fn HexBuffer::insert_byte(self : HexBuffer, offset : Int, value : Byte) -> Bool {
  guard offset >= 0 && offset <= self.len else { false }
  if self.gap_start == self.gap_end { self.grow_gap() }
  self.move_gap(offset)
  self.data[self.gap_start] = value
  self.gap_start = self.gap_start + 1
  self.len = self.len + 1
  self.modified = true
  true
}

///|
/// Deletes a byte at the specified logical offset. O(1) at gap, O(d) otherwise.
pub fn HexBuffer::delete_byte(self : HexBuffer, offset : Int) -> Bool {
  guard offset >= 0 && offset < self.len else { false }
  self.move_gap(offset)
  // Byte to delete is at physical position gap_end
  self.gap_end = self.gap_end + 1
  self.len = self.len - 1
  self.modified = true
  true
}

///|
/// Converts the buffer contents to a Bytes sequence (compact copy).
pub fn HexBuffer::to_bytes(self : HexBuffer) -> Bytes {
  if self.len == 0 { return b"" }
  Bytes::makei(self.len, fn(i) { self.data[self.to_physical(i)] })
}

///|
/// Returns a compact copy as FixedArray (no gap).
pub fn HexBuffer::to_fixedarray(self : HexBuffer) -> FixedArray[Byte] {
  if self.len == 0 { return [] }
  let arr = FixedArray::make(self.len, Byte::default())
  // Before gap
  if self.gap_start > 0 { arr.unsafe_blit(0, self.data, 0, self.gap_start) }
  // After gap
  let after = self.len - self.gap_start
  if after > 0 { arr.unsafe_blit(self.gap_start, self.data, self.gap_end, after) }
  arr
}

///|
/// Returns internal data — NOTE: with gap buffer, use byte_at() for correct access.
pub fn HexBuffer::data_ref(self : HexBuffer) -> FixedArray[Byte] {
  self.data
}

///|
/// Saves the buffer contents to a file.
pub fn HexBuffer::save(self : HexBuffer, path? : String) -> Unit raise {
  let save_path = match path {
    Some(p) => p
    None => match self.file_path {
      Some(p) => p
      None => raise @fs.IOError::IOError("No file path specified for save")
    }
  }
  let bytes = self.to_bytes()
  @fs.write_bytes_to_file(save_path, bytes)
  self.modified = false
  self.file_path = Some(save_path)
}
