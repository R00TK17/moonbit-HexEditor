// Encoding and decoding codecs: Base64, URL, Unicode, Hex

const HEX_UPPER = "0123456789ABCDEF"
const B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

///|
fn b64_index(c : Char) -> Int {
  let i = c.to_int()
  if i >= 'A'.to_int() && i <= 'Z'.to_int() { i - 'A'.to_int() }
  else if i >= 'a'.to_int() && i <= 'z'.to_int() { i - 'a'.to_int() + 26 }
  else if i >= '0'.to_int() && i <= '9'.to_int() { i - '0'.to_int() + 52 }
  else if c == '+' { 62 }
  else if c == '/' { 63 }
  else { -1 }
}

///|
/// Check if byte value is URL-unreserved (RFC 3986).
fn is_url_unreserved(b : Int) -> Bool {
  (b >= 0x41 && b <= 0x5A) || // A-Z
  (b >= 0x61 && b <= 0x7A) || // a-z
  (b >= 0x30 && b <= 0x39) || // 0-9
  b == 0x2D || b == 0x5F || b == 0x2E || b == 0x7E // - _ . ~
}

// ========== Base64 Encoding ==========

///|
/// Encode bytes to Base64 string.
pub fn base64_encode(data : Bytes) -> String {
  let len = data.length()
  let sb = StringBuilder()
  let mut i = 0
  while i < len {
    let b0 = data[i].to_int()
    let b1 = if i + 1 < len { data[i + 1].to_int() } else { 0 }
    let b2 = if i + 2 < len { data[i + 2].to_int() } else { 0 }
    let n = (b0 << 16) | (b1 << 8) | b2
    sb.write_char(B64_CHARS.get_char((n >> 18) & 63).unwrap())
    sb.write_char(B64_CHARS.get_char((n >> 12) & 63).unwrap())
    sb.write_char(if i + 1 < len { B64_CHARS.get_char((n >> 6) & 63).unwrap() } else { '=' })
    sb.write_char(if i + 2 < len { B64_CHARS.get_char(n & 63).unwrap() } else { '=' })
    i = i + 3
  }
  sb.to_string()
}

///|
/// Decode Base64 string to bytes.
pub fn base64_decode(text : String) -> Bytes? {
  let len = text.length()
  if len % 4 != 0 { return None }
  let bytes : Array[Byte] = []
  let mut i = 0
  while i < len {
    let v0 = b64_index(text.get_char(i).unwrap())
    let v1 = b64_index(text.get_char(i + 1).unwrap())
    let v2 = if text.get_char(i + 2).unwrap() == '=' { 0 } else { b64_index(text.get_char(i + 2).unwrap()) }
    let v3 = if text.get_char(i + 3).unwrap() == '=' { 0 } else { b64_index(text.get_char(i + 3).unwrap()) }
    if v0 < 0 || v1 < 0 || v2 < 0 || v3 < 0 { return None }
    let n = (v0 << 18) | (v1 << 12) | (v2 << 6) | v3
    bytes.push(((n >> 16) & 0xFF).to_byte())
    if text.get_char(i + 2).unwrap() != '=' { bytes.push(((n >> 8) & 0xFF).to_byte()) }
    if text.get_char(i + 3).unwrap() != '=' { bytes.push((n & 0xFF).to_byte()) }
    i = i + 4
  }
  Some(Bytes::makei(bytes.length(), k => bytes[k]))
}

// ========== URL Encoding ==========

///|
/// URL percent-encode bytes.
/// Unreserved characters (A-Z, a-z, 0-9, -, _, ., ~) pass through,
/// all others become %XX.
pub fn url_encode(data : Bytes) -> String {
  let sb = StringBuilder()
  for i = 0; i < data.length(); i = i + 1 {
    let b = data[i].to_int()
    if is_url_unreserved(b) {
      sb.write_char(b.to_char().unwrap())
    } else {
      sb.write_char('%')
      sb.write_char(HEX_UPPER.get_char((b >> 4) & 0xF).unwrap())
      sb.write_char(HEX_UPPER.get_char(b & 0xF).unwrap())
    }
  }
  sb.to_string()
}

///|
/// URL percent-decode a string to bytes.
/// %XX is decoded, + is decoded as space.
/// Returns None on invalid input.
pub fn url_decode(text : String) -> Bytes? {
  let out : Array[Byte] = []
  let len = text.length()
  let mut i = 0
  while i < len {
    let ch = text.get_char(i).unwrap()
    if ch == '%' {
      if i + 2 >= len { return None }
      let h = text.get_char(i + 1).unwrap()
      let l = text.get_char(i + 2).unwrap()
      if !is_hex_digit(h) || !is_hex_digit(l) { return None }
      let val = (hex_char_to_int(h) << 4) | hex_char_to_int(l)
      out.push(val.to_byte())
      i = i + 3
    } else if ch == '+' {
      out.push(b' ')
      i = i + 1
    } else {
      let code = ch.to_int()
      if code > 127 { return None }
      out.push(code.to_byte())
      i = i + 1
    }
  }
  Some(Bytes::makei(out.length(), fn(k) { out[k] }))
}

// ========== Unicode Encoding ==========

///|
/// Unicode encode: each byte → \u00XX notation.
pub fn unicode_encode(data : Bytes) -> String {
  let sb = StringBuilder()
  for i = 0; i < data.length(); i = i + 1 {
    let b = data[i].to_int()
    sb.write_string("\\u00")
    sb.write_char(HEX_UPPER.get_char((b >> 4) & 0xF).unwrap())
    sb.write_char(HEX_UPPER.get_char(b & 0xF).unwrap())
  }
  sb.to_string()
}

///|
/// Unicode decode: parse \uXXXX sequences to bytes.
/// Plain ASCII characters are kept as-is.
/// Codepoints <= 0x7F → 1 byte, <= 0x7FF → 2 bytes, else → 3 bytes (UTF-8).
/// Returns None on invalid input.
pub fn unicode_decode(text : String) -> Bytes? {
  let out : Array[Byte] = []
  let len = text.length()
  let mut i = 0
  while i < len {
    let ch = text.get_char(i).unwrap()
    if ch == '\\' && i + 1 < len {
      let next = text.get_char(i + 1).unwrap()
      if next == 'u' && i + 5 < len {
        let h3 = text.get_char(i + 2).unwrap()
        let h2 = text.get_char(i + 3).unwrap()
        let h1 = text.get_char(i + 4).unwrap()
        let h0 = text.get_char(i + 5).unwrap()
        if !is_hex_digit(h3) || !is_hex_digit(h2) || !is_hex_digit(h1) || !is_hex_digit(h0) {
          return None
        }
        let val = (hex_char_to_int(h3) << 12) |
          (hex_char_to_int(h2) << 8) |
          (hex_char_to_int(h1) << 4) |
          hex_char_to_int(h0)
        if val <= 0x7F {
          out.push(val.to_byte())
        } else if val <= 0x7FF {
          out.push((0xC0 | (val >> 6)).to_byte())
          out.push((0x80 | (val & 0x3F)).to_byte())
        } else {
          out.push((0xE0 | (val >> 12)).to_byte())
          out.push((0x80 | ((val >> 6) & 0x3F)).to_byte())
          out.push((0x80 | (val & 0x3F)).to_byte())
        }
        i = i + 6
      } else {
        return None
      }
    } else {
      let code = ch.to_int()
      if code > 127 { return None }
      out.push(code.to_byte())
      i = i + 1
    }
  }
  Some(Bytes::makei(out.length(), fn(k) { out[k] }))
}

// ========== Hex Encoding ==========

///|
/// Hex encode: bytes → space-separated hex values.
/// Example: b"\x48\x65" → "48 65"
pub fn hex_encode(data : Bytes) -> String {
  let sb = StringBuilder()
  for i = 0; i < data.length(); i = i + 1 {
    if i > 0 { sb.write_char(' ') }
    sb.write_char(HEX_UPPER.get_char((data[i].to_int() >> 4) & 0xF).unwrap())
    sb.write_char(HEX_UPPER.get_char(data[i].to_int() & 0xF).unwrap())
  }
  sb.to_string()
}

///|
/// Hex decode: space-separated hex values → bytes.
/// Example: "48 65 6C" → b"\x48\x65\x6C"
pub fn hex_decode(text : String) -> Bytes? {
  parse_hex_string(text)
}
