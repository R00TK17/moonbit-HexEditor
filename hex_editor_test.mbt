// Hex Editor — Blackbox Unit Tests
// Run `moon test` to execute.

///|
/// Test: HexBuffer creation and basic operations
test "HexBuffer new is empty" {
  let buf = @hex_editor.HexBuffer::new()
  assert_eq!(buf.length(), 0)
  assert_true!(buf.is_empty())
}

test "HexBuffer from bytes" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x00\x01\x02\xFF")
  assert_eq!(buf.length(), 4)
  assert_false!(buf.is_empty())
}

test "HexBuffer get_byte valid" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x00\xAB\xFF")
  assert_eq!(buf.get_byte(0), Some(b'\x00'))
  assert_eq!(buf.get_byte(1), Some(b'\xAB'))
  assert_eq!(buf.get_byte(2), Some(b'\xFF'))
}

test "HexBuffer get_byte invalid" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x00\x01")
  assert_eq!(buf.get_byte(-1), None)
  assert_eq!(buf.get_byte(2), None)
}

test "HexBuffer set_byte" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x00\x01\x02")
  let ok = buf.set_byte(0, b'\xFF')
  assert_true!(ok)
  assert_eq!(buf.get_byte(0), Some(b'\xFF'))
}

test "HexBuffer set_byte invalid" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x00\x01")
  let ok = buf.set_byte(5, b'\xFF')
  assert_false!(ok)
}

test "HexBuffer insert_byte" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x01\x02\x03")
  buf.insert_byte(0, b'\xFF') |> ignore
  assert_eq!(buf.length(), 4)
  assert_eq!(buf.get_byte(0), Some(b'\xFF'))
  assert_eq!(buf.get_byte(1), Some(b'\x01'))
}

test "HexBuffer insert_byte at end" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x01\x02")
  buf.insert_byte(2, b'\xFF') |> ignore
  assert_eq!(buf.length(), 3)
  assert_eq!(buf.get_byte(2), Some(b'\xFF'))
}

test "HexBuffer delete_byte" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x01\x02\x03")
  buf.delete_byte(1) |> ignore
  assert_eq!(buf.length(), 2)
  assert_eq!(buf.get_byte(0), Some(b'\x01'))
  assert_eq!(buf.get_byte(1), Some(b'\x03'))
}

test "HexBuffer to_bytes roundtrip" {
  let original = b"\x00\x01\x02\xFF\xFE\xFD"
  let buf = @hex_editor.HexBuffer::from_bytes(original)
  let restored = buf.to_bytes()
  assert_eq!(restored, original)
}

test "HexBuffer capacity growth" {
  let buf = @hex_editor.HexBuffer::new()
  for i = 0; i < 500; i = i + 1 {
    buf.insert_byte(buf.length(), i.to_byte()) |> ignore
  }
  assert_eq!(buf.length(), 500)
  assert_eq!(buf.get_byte(0), Some(b'\x00'))
  assert_eq!(buf.get_byte(255), Some(b'\xFF'))
}

///|
/// Test: Display formatting
test "format_byte_hex" {
  assert_eq!(@hex_editor.format_byte_hex(b'\xFF'), "FF")
  assert_eq!(@hex_editor.format_byte_hex(b'\x0A'), "0A")
  assert_eq!(@hex_editor.format_byte_hex(b'\x00'), "00")
}

test "format_byte_hex lowercase" {
  assert_eq!(@hex_editor.format_byte_hex(b'\xFF', uppercase=false), "ff")
}

test "format_ascii" {
  assert_eq!(@hex_editor.format_ascii(b'A'), 'A')
  assert_eq!(@hex_editor.format_ascii(b'\x00'), '.')
  assert_eq!(@hex_editor.format_ascii(b'\xFF'), '.')
}

test "format_offset" {
  assert_eq!(@hex_editor.format_offset(0), "00000000")
  assert_eq!(@hex_editor.format_offset(255), "000000FF")
}

test "to_hex_string" {
  assert_eq!(@hex_editor.to_hex_string(0), "00")
  assert_eq!(@hex_editor.to_hex_string(255), "FF")
}

test "format_size" {
  let s = @hex_editor.format_size(0)
  assert_true!(s.contains("B"))
  let s512 = @hex_editor.format_size(512)
  assert_true!(s512.contains("B"))
}

///|
/// Test: Search functionality
test "find_all_bytes" {
  let data = b"\x00\x01\x02\x00\x01\x03"
  let results = @hex_editor.find_all_bytes(data, b"\x00\x01")
  assert_eq!(results.length(), 2)
}

test "parse_hex_string" {
  let result = @hex_editor.parse_hex_string("FF00AB")
  assert_true!(result is Some)
  let bytes = result.unwrap()
  assert_eq!(bytes.length(), 3)
  assert_eq!(bytes[0], b'\xFF')
}

test "parse_hex_string with spaces" {
  let result = @hex_editor.parse_hex_string("FF 00 AB")
  assert_true!(result is Some)
}

test "parse_hex_string invalid" {
  assert_eq!(@hex_editor.parse_hex_string("ZZ"), None)
  assert_eq!(@hex_editor.parse_hex_string("FFF"), None)
}

///|
/// Test: data_ref zero-copy access
test "data_ref" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x01\x02\x03")
  let data = buf.data_ref()
  assert_eq!(data.length(), 3)
  assert_eq!(data[0], b'\x01')
  assert_eq!(data[2], b'\x03')
}

///|
/// Test: Scan module
test "scan_signatures on PNG" {
  let png = b"\x89PNG\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90\x77\x53\xDE\x00\x00\x00\x0A\x49\x44\x41\x54\x08\xD7\x63\xF8\xCF\xC0\x00\x00\x00\x00\x49\x45\x4E\x44\xAE\x42\x60\x82"
  let matches = @hex_editor.scan_signatures(png)
  assert_true!(matches.length() >= 1)
}

test "scan_signatures on ZIP" {
  let zip = b"\x50\x4B\x03\x04\x0A\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x07\x00\x00\x00readme\x50\x4B\x01\x02\x00\x00\x0A\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x07\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00readme\x50\x4B\x05\x06\x00\x00\x00\x00\x01\x00\x01\x00\x35\x00\x00\x00\x29\x00\x00\x00\x00\x00"
  let matches = @hex_editor.scan_signatures(zip)
  assert_true!(matches.length() >= 1)
}

///|
/// Test: Strings extraction
test "find_strings" {
  let data = b"\x00Hello World\x00\x00Test\x00"
  let matches = @hex_editor.find_strings(data)
  assert_true!(matches.length() >= 1)
}

///|
/// Test: Entropy analysis
test "entropy_scan" {
  let buf = @hex_editor.HexBuffer::new()
  for i = 0; i < 256; i = i + 1 { buf.insert_byte(buf.length(), (i % 16).to_byte()) |> ignore }
  let blocks = @hex_editor.entropy_scan(buf.to_bytes())
  assert_true!(blocks.length() >= 1)
}

///|
/// Test: is_modified flag
test "is_modified" {
  let buf = @hex_editor.HexBuffer::new()
  assert_false!(buf.is_modified())
  buf.insert_byte(0, b'\x00') |> ignore
  assert_true!(buf.is_modified())
}

///|
/// Test: format_hex_dump output
test "format_hex_dump" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F")
  let dump = @hex_editor.format_hex_dump(buf, length=16)
  assert_true!(dump.length() > 0)
  assert_true!(dump.contains("00000000"))
}

///|
/// Test: parse_structure on PNG data
test "parse_structure PNG" {
  let png = b"\x89PNG\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90\x77\x53\xDE\x00\x00\x00\x0A\x49\x44\x41\x54\x08\xD7\x63\xF8\xCF\xC0\x00\x00\x00\x00\x49\x45\x4E\x44\xAE\x42\x60\x82"
  let fields = @hex_editor.parse_structure(png)
  assert_true!(fields.length() >= 2)
}

// ========== Codec Tests ==========

test "base64 roundtrip" {
  let data = b"\x00\x01\x02\x48\x65\x6C\x6C\x6F"
  let encoded = @hex_editor.base64_encode(data)
  let decoded = @hex_editor.base64_decode(encoded)
  assert_true!(decoded is Some(_))
  assert_eq!(decoded.unwrap().length(), data.length())
}

test "base64 encode known" {
  assert_eq!(@hex_editor.base64_encode(b"\x48\x65\x6C\x6C\x6F"), "SGVsbG8=")
  assert_eq!(@hex_editor.base64_encode(b""), "")
}

test "url_encode" {
  // Unreserved chars pass through
  assert_eq!(@hex_editor.url_encode(b"\x41\x42\x43"), "ABC")
  assert_eq!(@hex_editor.url_encode(b"\x7E"), "~")
  // Space and special chars get percent-encoded
  assert_eq!(@hex_editor.url_encode(b"\x20"), "%20")
  assert_eq!(@hex_editor.url_encode(b"\x00"), "%00")
  assert_eq!(@hex_editor.url_encode(b"\xFF"), "%FF")
}

test "url_decode" {
  let d1 = @hex_editor.url_decode("ABC")
  assert_true!(d1 is Some(_))
  assert_eq!(d1.unwrap().length(), 3)
  assert_eq!(d1.unwrap()[0], b'\x41')
  // Percent decode
  let d2 = @hex_editor.url_decode("%20")
  assert_true!(d2 is Some(_))
  assert_eq!(d2.unwrap()[0], b'\x20')
  // Plus → space
  let d3 = @hex_editor.url_decode("+")
  assert_true!(d3 is Some(_))
  assert_eq!(d3.unwrap()[0], b'\x20')
}

test "url roundtrip" {
  let data = b"\x00\x20\x41\xFF\x0A"
  let encoded = @hex_editor.url_encode(data)
  let decoded = @hex_editor.url_decode(encoded)
  assert_true!(decoded is Some(_))
  let dec = decoded.unwrap()
  assert_eq!(dec.length(), data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_eq!(dec[i], data[i])
  }
}

test "url_decode invalid" {
  assert_true!(@hex_editor.url_decode("%") is None)
  assert_true!(@hex_editor.url_decode("%G0") is None)
  assert_true!(@hex_editor.url_decode("%0") is None)
}

test "unicode_encode" {
  assert_eq!(@hex_editor.unicode_encode(b"\x41\x42"), "\\u0041\\u0042")
  assert_eq!(@hex_editor.unicode_encode(b"\x00"), "\\u0000")
  assert_eq!(@hex_editor.unicode_encode(b"\xFF"), "\\u00FF")
  assert_eq!(@hex_editor.unicode_encode(b""), "")
}

test "unicode_decode" {
  let d1 = @hex_editor.unicode_decode("\\u0041\\u0042")
  assert_true!(d1 is Some(_))
  assert_eq!(d1.unwrap().length(), 2)
  assert_eq!(d1.unwrap()[0], b'\x41')
  assert_eq!(d1.unwrap()[1], b'\x42')
  // Plain ASCII mixed in
  let d2 = @hex_editor.unicode_decode("A")
  assert_true!(d2 is Some(_))
  assert_eq!(d2.unwrap()[0], b'\x41')
}

test "unicode roundtrip" {
  let data = b"\x48\x65\x6C\x6C\x6F"
  let encoded = @hex_editor.unicode_encode(data)
  let decoded = @hex_editor.unicode_decode(encoded)
  assert_true!(decoded is Some(_))
  let dec = decoded.unwrap()
  assert_eq!(dec.length(), data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_eq!(dec[i], data[i])
  }
}

test "unicode_decode invalid" {
  assert_true!(@hex_editor.unicode_decode("\\u00G0") is None)
  assert_true!(@hex_editor.unicode_decode("\\u") is None)
}

test "hex_encode" {
  assert_eq!(@hex_editor.hex_encode(b"\x48\x65\x6C"), "48 65 6C")
  assert_eq!(@hex_editor.hex_encode(b"\x00\xFF"), "00 FF")
  assert_eq!(@hex_editor.hex_encode(b""), "")
}

test "hex_decode" {
  let d1 = @hex_editor.hex_decode("48 65 6C")
  assert_true!(d1 is Some(_))
  assert_eq!(d1.unwrap().length(), 3)
  assert_eq!(d1.unwrap()[0], b'\x48')
  assert_eq!(d1.unwrap()[1], b'\x65')
  assert_eq!(d1.unwrap()[2], b'\x6C')
  // No spaces
  let d2 = @hex_editor.hex_decode("00FF")
  assert_true!(d2 is Some(_))
  assert_eq!(d2.unwrap()[0], b'\x00')
  assert_eq!(d2.unwrap()[1], b'\xFF')
}

test "hex roundtrip" {
  let data = b"\x00\x01\x7F\xFF"
  let encoded = @hex_editor.hex_encode(data)
  let decoded = @hex_editor.hex_decode(encoded)
  assert_true!(decoded is Some(_))
  let dec = decoded.unwrap()
  assert_eq!(dec.length(), data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_eq!(dec[i], data[i])
  }
}

test "hex_decode invalid" {
  assert_true!(@hex_editor.hex_decode("GG") is None)
  assert_true!(@hex_editor.hex_decode("0") is None)
}