// Hex Editor — Core Library
// Provides the HexBuffer data structure for viewing and editing binary data.

///|
/// A mutable buffer for hex editing operations.
///
/// HexBuffer holds the binary data being edited and tracks whether
/// modifications have been made. It supports reading, writing, inserting,
/// and deleting bytes at arbitrary offsets.
struct HexBuffer {
  mut data : FixedArray[Byte] // mutable byte buffer
  mut len : Int               // current data length
  mut modified : Bool         // dirty flag
  mut file_path : String?       // associated file path
}

///|
/// Creates a new empty HexBuffer.
pub fn HexBuffer::new() -> HexBuffer {
  {
    data: FixedArray::make(0, Byte::default()),
    len: 0,
    modified: false,
    file_path: None,
  }
}

///|
/// Creates a HexBuffer from a Bytes sequence.
pub fn HexBuffer::from_bytes(bytes : Bytes) -> HexBuffer {
  let len = bytes.length()
  let data = FixedArray::make(len, Byte::default())
  data.blit_from_bytes(0, bytes, 0, len)
  {
    data,
    len,
    modified: false,
    file_path: None,
  }
}

///|
/// Sets the file path associated with this buffer.
pub fn HexBuffer::set_file_path(self : HexBuffer, path : String) -> Unit {
  self.file_path = Some(path)
}

///|
/// Loads a HexBuffer from a file.
///
/// Raises `@fs.IOError` if the file cannot be read.
pub fn HexBuffer::from_file(path : String) -> HexBuffer raise {
  let bytes = @fs.read_file_to_bytes(path)
  let len = bytes.length()
  let data = FixedArray::make(len, Byte::default())
  data.blit_from_bytes(0, bytes, 0, len)
  {
    data,
    len,
    modified: false,
    file_path: Some(path),
  }
}

///|
/// Returns the current length of the buffer in bytes.
pub fn HexBuffer::length(self : HexBuffer) -> Int {
  self.len
}

///|
/// Returns whether the buffer is empty.
pub fn HexBuffer::is_empty(self : HexBuffer) -> Bool {
  self.len == 0
}

///|
/// Returns whether the buffer has been modified since creation or last save.
pub fn HexBuffer::is_modified(self : HexBuffer) -> Bool {
  self.modified
}

///|
/// Gets the file path associated with this buffer, if any.
pub fn HexBuffer::get_file_path(self : HexBuffer) -> String? {
  self.file_path
}

///|
/// Gets the byte at the specified offset.
pub fn HexBuffer::get_byte(self : HexBuffer, offset : Int) -> Byte? {
  guard offset >= 0 && offset < self.len else { None }
  Some(self.data[offset])
}

///|
/// Sets the byte at the specified offset. Marks the buffer as modified.
pub fn HexBuffer::set_byte(
  self : HexBuffer,
  offset : Int,
  value : Byte,
) -> Bool {
  guard offset >= 0 && offset < self.len else { false }
  self.data[offset] = value
  self.modified = true
  true
}

///|
/// Converts the buffer contents to a Bytes sequence.
pub fn HexBuffer::to_bytes(self : HexBuffer) -> Bytes {
  if self.len == 0 {
    return b""
  }
  Bytes::makei(self.len, i => self.data[i])
}

///|
/// Returns internal data without copying — zero-copy for rendering.
pub fn HexBuffer::data_ref(self : HexBuffer) -> FixedArray[Byte] {
  self.data
}

///|
/// Converts the buffer contents to a FixedArray of bytes (copy).
pub fn HexBuffer::to_fixedarray(self : HexBuffer) -> FixedArray[Byte] {
  if self.len == 0 {
    return []
  }
  let arr = FixedArray::make(self.len, Byte::default())
  arr.unsafe_blit(0, self.data, 0, self.len)
  arr
}

///|
/// Saves the buffer contents to a file. Raises IOError on failure.
pub fn HexBuffer::save(self : HexBuffer, path? : String) -> Unit raise {
  let save_path = match path {
    Some(p) => p
    None => match self.file_path {
      Some(p) => p
      None => raise @fs.IOError::IOError("No file path specified for save")
    }
  }
  if self.len == 0 {
    @fs.write_bytes_to_file(save_path, [])
  } else {
    let bytes = Bytes::makei(self.len, i => self.data[i])
    @fs.write_bytes_to_file(save_path, bytes)
  }
  self.modified = false
  self.file_path = Some(save_path)
}

///|
/// Inserts a byte at the specified offset, shifting subsequent bytes.
pub fn HexBuffer::insert_byte(
  self : HexBuffer,
  offset : Int,
  value : Byte,
) -> Bool {
  guard offset >= 0 && offset <= self.len else { false }
  self.ensure_capacity(self.len + 1)
  for i = self.len; i > offset; i = i - 1 {
    self.data[i] = self.data[i - 1]
  }
  self.data[offset] = value
  self.len = self.len + 1
  self.modified = true
  true
}

///|
/// Deletes a byte at the specified offset, shifting subsequent bytes left.
pub fn HexBuffer::delete_byte(self : HexBuffer, offset : Int) -> Bool {
  guard offset >= 0 && offset < self.len else { false }
  for i = offset; i < self.len - 1; i = i + 1 {
    self.data[i] = self.data[i + 1]
  }
  self.len = self.len - 1
  self.modified = true
  true
}

///|
/// Ensures the internal buffer has at least the specified capacity.
fn HexBuffer::ensure_capacity(self : HexBuffer, required : Int) -> Unit {
  let current_cap = self.data.length()
  if current_cap >= required {
    return
  }
  let start_cap = if current_cap <= 0 { 1 } else { current_cap }
  let mut new_cap = start_cap
  for _i = 0; new_cap < required; _i = _i + 1 {
    new_cap = new_cap * 2
  }
  let new_data = FixedArray::make(new_cap, Byte::default())
  new_data.unsafe_blit(0, self.data, 0, self.len)
  self.data = new_data
}

