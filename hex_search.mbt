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

