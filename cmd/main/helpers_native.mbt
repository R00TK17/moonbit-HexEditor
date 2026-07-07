// Native-only helper functions used by TUI and native CLI

///|
/// Parse pure hex string to int (e.g., "100" -> 256).
fn parse_hex_int(s : String) -> Int? {
  let len = s.length()
  guard len > 0 else { None }
  let mut result = 0
  for i = 0; i < len; i = i + 1 {
    let c = s.get_char(i).unwrap().to_int()
    let d = if c >= '0'.to_int() && c <= '9'.to_int() {
      c - '0'.to_int()
    } else if c >= 'A'.to_int() && c <= 'F'.to_int() {
      c - 'A'.to_int() + 10
    } else if c >= 'a'.to_int() && c <= 'f'.to_int() {
      c - 'a'.to_int() + 10
    } else {
      return None
    }
    result = result * 16 + d
  }
  Some(result)
}

///|
/// Convert string to ASCII bytes for text search.
fn ascii_to_bytes(s : String) -> Bytes {
  Bytes::makei(s.length(), i => {
    let ch = s.get_char(i).unwrap()
    let code = ch.to_int()
    if code >= 0 && code <= 127 {
      code.to_byte()
    } else {
      b'?'
    }
  })
}
