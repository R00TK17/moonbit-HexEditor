// Hex Editor — Search Functionality
// Uses Boyer-Moore-Horspool for O(n/m) average case search.

///|
/// Build BMH bad-character skip table. pattern.length() bytes.
fn bmh_skip(pattern : Bytes) -> FixedArray[Int] {
  let m = pattern.length()
  let skip = FixedArray::make(256, m)
  for j = 0; j < m - 1; j = j + 1 {
    skip[pattern[j].to_int()] = m - 1 - j
  }
  skip
}

///|
/// Boyer-Moore-Horspool search — first occurrence.
pub fn find_bytes(
  data : Bytes,
  pattern : Bytes,
  start_offset? : Int = 0,
) -> Int? {
  let n = data.length()
  let m = pattern.length()
  let start = start_offset
  guard m > 0 else { None }
  guard start >= 0 && start <= n else { None }
  guard m <= n else { None }
  let skip = bmh_skip(pattern)
  let mut i = start
  while i <= n - m {
    let mut j = m - 1
    while j >= 0 && data[i + j] == pattern[j] { j = j - 1 }
    if j < 0 { return Some(i) }
    i = i + skip[data[i + m - 1].to_int()]
  }
  None
}

///|
/// Boyer-Moore-Horspool search — all occurrences.
pub fn find_all_bytes(data : Bytes, pattern : Bytes) -> Array[Int] {
  let n = data.length()
  let m = pattern.length()
  let results = []
  guard m > 0 else { return results }
  guard m <= n else { return results }
  let skip = bmh_skip(pattern)
  let mut i = 0
  while i <= n - m {
    let mut j = m - 1
    while j >= 0 && data[i + j] == pattern[j] { j = j - 1 }
    if j < 0 { results.push(i) }
    i = i + skip[data[i + m - 1].to_int()]
  }
  results
}

///|
/// Finds a byte pattern in a HexBuffer.
pub fn find_bytes_in_buffer(
  buffer : HexBuffer,
  pattern : Bytes,
  start_offset? : Int = 0,
) -> Int? {
  let data = buffer.to_bytes()
  find_bytes(data, pattern, start_offset=start_offset)
}

///|
/// Finds all occurrences of a byte pattern in a HexBuffer.
pub fn find_all_bytes_in_buffer(
  buffer : HexBuffer,
  pattern : Bytes,
) -> Array[Int] {
  let data = buffer.to_bytes()
  find_all_bytes(data, pattern)
}

///|
/// Converts an ASCII string to a Bytes sequence.
/// Non-ASCII characters are replaced with '?'.
fn string_to_ascii_bytes(text : String) -> Bytes {
  let len = text.length()
  Bytes::makei(len, i => {
    let ch = text.get_char(i).unwrap()
    let code = ch.to_int()
    if code >= 0 && code <= 127 {
      code.to_byte()
    } else {
      b'?'
    }
  })
}

///|
/// Searches for an ASCII string in the data.
pub fn find_ascii_string(
  data : Bytes,
  text : String,
  start_offset? : Int = 0,
) -> Int? {
  let pattern = string_to_ascii_bytes(text)
  find_bytes(data, pattern, start_offset=start_offset)
}

///|
/// Parses a hex string like "FF 00 AB" into a Bytes sequence.
pub fn parse_hex_string(hex_str : String) -> Bytes? {
  // Extract only hex digits
  let digits : Array[Char] = []
  for i = 0; i < hex_str.length(); i = i + 1 {
    let ch = hex_str.get_char(i).unwrap()
    if is_hex_digit(ch) {
      digits.push(ch)
    }
  }

  let digit_count = digits.length()
  guard digit_count > 0 && digit_count % 2 == 0 else { None }

  let byte_count = digit_count / 2
  let result = Bytes::makei(byte_count, i => {
    let hi = hex_char_to_int(digits[i * 2])
    let lo = hex_char_to_int(digits[i * 2 + 1])
    ((hi << 4) | lo).to_byte()
  })
  Some(result)
}

///|
/// Checks if a character is a valid hex digit (0-9, a-f, A-F).
fn is_hex_digit(ch : Char) -> Bool {
  let c = ch.to_int()
  (c >= '0'.to_int() && c <= '9'.to_int()) ||
  (c >= 'A'.to_int() && c <= 'F'.to_int()) ||
  (c >= 'a'.to_int() && c <= 'f'.to_int())
}

///|
/// Converts a hex character to its integer value.
fn hex_char_to_int(ch : Char) -> Int {
  let c = ch.to_int()
  if c >= '0'.to_int() && c <= '9'.to_int() {
    c - '0'.to_int()
  } else if c >= 'A'.to_int() && c <= 'F'.to_int() {
    c - 'A'.to_int() + 10
  } else {
    c - 'a'.to_int() + 10
  }
}

///|
/// Searches for a hex pattern (specified as string) in the data.
pub fn find_hex_pattern(
  data : Bytes,
  hex_str : String,
  start_offset? : Int = 0,
) -> Int? {
  match parse_hex_string(hex_str) {
    None => None
    Some(pattern) => find_bytes(data, pattern, start_offset=start_offset)
  }
}

///|
/// Counts the number of occurrences of a byte pattern.
pub fn count_bytes(data : Bytes, pattern : Bytes) -> Int {
  let occurrences = find_all_bytes(data, pattern)
  occurrences.length()
}

///|
/// Searches backwards from a given offset for a byte pattern.
pub fn rfind_bytes(
  data : Bytes,
  pattern : Bytes,
  start_offset? : Int,
) -> Int? {
  let data_len = data.length()
  let pat_len = pattern.length()

  let start = match start_offset {
    None => data_len - pat_len
    Some(s) => if s > data_len - pat_len { data_len - pat_len } else { s }
  }

  guard pat_len > 0 else { None }
  guard start >= 0 else { None }
  guard pat_len <= data_len else { None }

  // Search backwards
  for i = start; i >= 0; i = i - 1 {
    for j = 0; j < pat_len; j = j + 1 {
      if data[i + j] != pattern[j] {
        break
      }
    } nobreak {
      return Some(i)
    }
  }
  None
}
