// Hex Editor — Strings Extraction
// Find printable ASCII strings (>= 4 chars) in binary data.

///|
pub struct StringMatch {
  offset : Int
  text : String
} derive(Debug)

///|
/// Scan bytes for printable ASCII strings of length >= 4.
pub fn find_strings(bytes : Bytes) -> Array[StringMatch] {
  let len = bytes.length()
  let results : Array[StringMatch] = []
  let mut i = 0
  while i < len {
    while i < len {
      let b = bytes[i].to_int()
      if b >= 0x20 && b <= 0x7E {
        break
      }
      i = i + 1
    }
    if i >= len {
      break
    }
    let start = i
    let sb = StringBuilder()
    while i < len {
      let b = bytes[i].to_int()
      if b < 0x20 || b > 0x7E {
        break
      }
      match b.to_char() {
        Some(c) => sb.write_char(c)
        None => ()
      }
      i = i + 1
    }
    let text = sb.to_string()
    if text.length() >= 4 {
      results.push({ offset: start, text })
    }
  }
  results
}

///|
/// Format strings matches as plain text for export.
pub fn format_strings_export(matches : Array[StringMatch]) -> String {
  let sb = StringBuilder()
  for i = 0; i < matches.length(); i = i + 1 {
    sb.write_string(
      "0x\{to_hex_string(matches[i].offset, width=8)}  \{matches[i].text}\n",
    )
  }
  sb.write_string("\{matches.length()} strings found\n")
  sb.to_string()
}
