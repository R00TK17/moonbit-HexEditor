// Hex Editor — Blackbox Unit Tests
// Run `moon test` to execute.

///|
/// Test: HexBuffer creation and basic operations
test "HexBuffer new is empty" {
  let buf = @hex_editor.HexBuffer::new()
  assert_eq!(buf.length(), 0)
  assert_true!(buf.is_empty())
  assert_false!(buf.is_modified())
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
  assert_true!(buf.is_modified())
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

test "HexBuffer insert_bytes" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x01\x05")
  buf.insert_bytes(1, b"\x02\x03\x04") |> ignore
  assert_eq!(buf.length(), 5)
  assert_eq!(buf.get_byte(1), Some(b'\x02'))
  assert_eq!(buf.get_byte(3), Some(b'\x04'))
}

test "HexBuffer delete_byte" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x01\x02\x03")
  buf.delete_byte(1) |> ignore
  assert_eq!(buf.length(), 2)
  assert_eq!(buf.get_byte(0), Some(b'\x01'))
  assert_eq!(buf.get_byte(1), Some(b'\x03'))
}

test "HexBuffer delete_bytes range" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x01\x02\x03\x04\x05")
  buf.delete_bytes(1, 3) |> ignore
  assert_eq!(buf.length(), 2)
  assert_eq!(buf.get_byte(0), Some(b'\x01'))
  assert_eq!(buf.get_byte(1), Some(b'\x05'))
}

test "HexBuffer replace_range same size" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x01\x02\x03")
  buf.replace_range(0, 2, b"\xAA\xBB") |> ignore
  assert_eq!(buf.length(), 3)
  assert_eq!(buf.get_byte(0), Some(b'\xAA'))
  assert_eq!(buf.get_byte(1), Some(b'\xBB'))
}

test "HexBuffer replace_range larger" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x01\x02\x03")
  buf.replace_range(1, 1, b"\xAA\xBB\xCC") |> ignore
  assert_eq!(buf.length(), 5)
  assert_eq!(buf.get_byte(1), Some(b'\xAA'))
}

test "HexBuffer fill_range" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x01\x02\x03\x04\x05")
  buf.fill_range(1, 4, b'\x00') |> ignore
  assert_eq!(buf.get_byte(0), Some(b'\x01'))
  assert_eq!(buf.get_byte(1), Some(b'\x00'))
  assert_eq!(buf.get_byte(3), Some(b'\x00'))
  assert_eq!(buf.get_byte(4), Some(b'\x05'))
}

test "HexBuffer clear" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x01\x02\x03")
  buf.clear()
  assert_eq!(buf.length(), 0)
  assert_true!(buf.is_empty())
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
test "find_bytes found" {
  let data = b"\x00\x01\x02\xFF\xFE\xFD"
  let result = @hex_editor.find_bytes(data, b"\xFF\xFE")
  assert_eq!(result, Some(3))
}

test "find_bytes not found" {
  let data = b"\x00\x01\x02\x03"
  let result = @hex_editor.find_bytes(data, b"\xFF")
  assert_eq!(result, None)
}

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

test "find_ascii_string" {
  let data = b"Hello World!"
  let result = @hex_editor.find_ascii_string(data, "World")
  assert_eq!(result, Some(6))
}

test "rfind_bytes" {
  let data = b"\x00\x01\x02\x00\x01\x03"
  let result = @hex_editor.rfind_bytes(data, b"\x00\x01")
  assert_eq!(result, Some(3))
}

///|
/// Test: Editing operations
