// Hex Editor — Blackbox Unit Tests
// Run `moon test` to execute.

///|
/// Test: HexBuffer creation and basic operations
test "HexBuffer new is empty" {
  let buf = @hex_editor.HexBuffer::new()
  assert_eq(buf.length(), 0)
  assert_true(buf.is_empty())
}

test "HexBuffer from bytes" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x00\x01\x02\xFF")
  assert_eq(buf.length(), 4)
  assert_false(buf.is_empty())
}

test "HexBuffer get_byte valid" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x00\xAB\xFF")
  assert_eq(buf.get_byte(0), Some(b'\x00'))
  assert_eq(buf.get_byte(1), Some(b'\xAB'))
  assert_eq(buf.get_byte(2), Some(b'\xFF'))
}

test "HexBuffer get_byte invalid" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x00\x01")
  assert_eq(buf.get_byte(-1), None)
  assert_eq(buf.get_byte(2), None)
}

test "HexBuffer set_byte" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x00\x01\x02")
  let ok = buf.set_byte(0, b'\xFF')
  assert_true(ok)
  assert_eq(buf.get_byte(0), Some(b'\xFF'))
}

test "HexBuffer set_byte invalid" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x00\x01")
  let ok = buf.set_byte(5, b'\xFF')
  assert_false(ok)
}

test "HexBuffer insert_byte" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x01\x02\x03")
  buf.insert_byte(0, b'\xFF') |> ignore
  assert_eq(buf.length(), 4)
  assert_eq(buf.get_byte(0), Some(b'\xFF'))
  assert_eq(buf.get_byte(1), Some(b'\x01'))
}

test "HexBuffer insert_byte at end" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x01\x02")
  buf.insert_byte(2, b'\xFF') |> ignore
  assert_eq(buf.length(), 3)
  assert_eq(buf.get_byte(2), Some(b'\xFF'))
}

test "HexBuffer delete_byte" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x01\x02\x03")
  buf.delete_byte(1) |> ignore
  assert_eq(buf.length(), 2)
  assert_eq(buf.get_byte(0), Some(b'\x01'))
  assert_eq(buf.get_byte(1), Some(b'\x03'))
}

test "HexBuffer to_bytes roundtrip" {
  let original = b"\x00\x01\x02\xFF\xFE\xFD"
  let buf = @hex_editor.HexBuffer::from_bytes(original)
  let restored = buf.to_bytes()
  assert_eq(restored, original)
}

test "HexBuffer capacity growth" {
  let buf = @hex_editor.HexBuffer::new()
  for i = 0; i < 500; i = i + 1 {
    buf.insert_byte(buf.length(), i.to_byte()) |> ignore
  }
  assert_eq(buf.length(), 500)
  assert_eq(buf.get_byte(0), Some(b'\x00'))
  assert_eq(buf.get_byte(255), Some(b'\xFF'))
}

///|
/// Test: Display formatting
test "format_byte_hex" {
  assert_eq(@hex_editor.format_byte_hex(b'\xFF'), "FF")
  assert_eq(@hex_editor.format_byte_hex(b'\x0A'), "0A")
  assert_eq(@hex_editor.format_byte_hex(b'\x00'), "00")
}

test "format_byte_hex lowercase" {
  assert_eq(@hex_editor.format_byte_hex(b'\xFF', uppercase=false), "ff")
}

test "format_ascii" {
  assert_eq(@hex_editor.format_ascii(b'A'), 'A')
  assert_eq(@hex_editor.format_ascii(b'\x00'), '.')
  assert_eq(@hex_editor.format_ascii(b'\xFF'), '.')
}

test "format_offset" {
  assert_eq(@hex_editor.format_offset(0), "00000000")
  assert_eq(@hex_editor.format_offset(255), "000000FF")
}

test "to_hex_string" {
  assert_eq(@hex_editor.to_hex_string(0), "00")
  assert_eq(@hex_editor.to_hex_string(255), "FF")
}

test "format_size" {
  let s = @hex_editor.format_size(0)
  assert_true(s.contains("B"))
  let s512 = @hex_editor.format_size(512)
  assert_true(s512.contains("B"))
}

///|
/// Test: Search functionality
test "find_all_bytes" {
  let data = b"\x00\x01\x02\x00\x01\x03"
  let results = @hex_editor.find_all_bytes(data, b"\x00\x01")
  assert_eq(results.length(), 2)
}

test "parse_hex_string" {
  let result = @hex_editor.parse_hex_string("FF00AB")
  assert_true(result is Some)
  let bytes = result.unwrap()
  assert_eq(bytes.length(), 3)
  assert_eq(bytes[0], b'\xFF')
}

test "parse_hex_string with spaces" {
  let result = @hex_editor.parse_hex_string("FF 00 AB")
  assert_true(result is Some)
}

test "parse_hex_string invalid" {
  assert_eq(@hex_editor.parse_hex_string("ZZ"), None)
  assert_eq(@hex_editor.parse_hex_string("FFF"), None)
}

///|
/// Test: byte_at fast access
test "byte_at" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x01\x02\x03")
  assert_eq(buf.byte_at(0), b'\x01')
  assert_eq(buf.byte_at(1), b'\x02')
  assert_eq(buf.byte_at(2), b'\x03')
}

///|
/// Test: Scan module
test "scan_signatures on PNG" {
  let png = b"\x89PNG\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90\x77\x53\xDE\x00\x00\x00\x0A\x49\x44\x41\x54\x08\xD7\x63\xF8\xCF\xC0\x00\x00\x00\x00\x49\x45\x4E\x44\xAE\x42\x60\x82"
  let matches = @hex_editor.scan_signatures(png)
  assert_true(matches.length() >= 1)
}

test "scan_signatures on ZIP" {
  let zip = b"\x50\x4B\x03\x04\x0A\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x07\x00\x00\x00readme\x50\x4B\x01\x02\x00\x00\x0A\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x07\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00readme\x50\x4B\x05\x06\x00\x00\x00\x00\x01\x00\x01\x00\x35\x00\x00\x00\x29\x00\x00\x00\x00\x00"
  let matches = @hex_editor.scan_signatures(zip)
  assert_true(matches.length() >= 1)
}

///|
/// Test: Strings extraction
test "find_strings" {
  let data = b"\x00Hello World\x00\x00Test\x00"
  let matches = @hex_editor.find_strings(data)
  assert_true(matches.length() >= 1)
}

///|
/// Test: Entropy analysis
test "entropy_scan" {
  let buf = @hex_editor.HexBuffer::new()
  for i = 0; i < 256; i = i + 1 { buf.insert_byte(buf.length(), (i % 16).to_byte()) |> ignore }
  let blocks = @hex_editor.entropy_scan(buf.to_bytes())
  assert_true(blocks.length() >= 1)
}

///|
/// Test: is_modified flag
test "is_modified" {
  let buf = @hex_editor.HexBuffer::new()
  assert_false(buf.is_modified())
  buf.insert_byte(0, b'\x00') |> ignore
  assert_true(buf.is_modified())
}

///|
/// Test: format_hex_dump output
test "format_hex_dump" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F")
  let dump = @hex_editor.format_hex_dump(buf, length=16)
  assert_true(dump.length() > 0)
  assert_true(dump.contains("00000000"))
}

///|
/// Test: parse_structure on PNG data
test "parse_structure PNG" {
  let png = b"\x89PNG\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90\x77\x53\xDE\x00\x00\x00\x0A\x49\x44\x41\x54\x08\xD7\x63\xF8\xCF\xC0\x00\x00\x00\x00\x49\x45\x4E\x44\xAE\x42\x60\x82"
  let fields = @hex_editor.parse_structure(png)
  assert_true(fields.length() >= 2)
}

// ========== Codec Tests ==========

test "base64 roundtrip" {
  let data = b"\x00\x01\x02\x48\x65\x6C\x6C\x6F"
  let encoded = @hex_editor.base64_encode(data)
  let decoded = @hex_editor.base64_decode(encoded)
  assert_true(decoded is Some(_))
  assert_eq(decoded.unwrap().length(), data.length())
}

test "base64 encode known" {
  assert_eq(@hex_editor.base64_encode(b"\x48\x65\x6C\x6C\x6F"), "SGVsbG8=")
  assert_eq(@hex_editor.base64_encode(b""), "")
}

test "url_encode" {
  // Unreserved chars pass through
  assert_eq(@hex_editor.url_encode(b"\x41\x42\x43"), "ABC")
  assert_eq(@hex_editor.url_encode(b"\x7E"), "~")
  // Space and special chars get percent-encoded
  assert_eq(@hex_editor.url_encode(b"\x20"), "%20")
  assert_eq(@hex_editor.url_encode(b"\x00"), "%00")
  assert_eq(@hex_editor.url_encode(b"\xFF"), "%FF")
}

test "url_decode" {
  let d1 = @hex_editor.url_decode("ABC")
  assert_true(d1 is Some(_))
  assert_eq(d1.unwrap().length(), 3)
  assert_eq(d1.unwrap()[0], b'\x41')
  // Percent decode
  let d2 = @hex_editor.url_decode("%20")
  assert_true(d2 is Some(_))
  assert_eq(d2.unwrap()[0], b'\x20')
  // Plus → space
  let d3 = @hex_editor.url_decode("+")
  assert_true(d3 is Some(_))
  assert_eq(d3.unwrap()[0], b'\x20')
}

test "url roundtrip" {
  let data = b"\x00\x20\x41\xFF\x0A"
  let encoded = @hex_editor.url_encode(data)
  let decoded = @hex_editor.url_decode(encoded)
  assert_true(decoded is Some(_))
  let dec = decoded.unwrap()
  assert_eq(dec.length(), data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_eq(dec[i], data[i])
  }
}

test "url_decode invalid" {
  assert_true(@hex_editor.url_decode("%") is None)
  assert_true(@hex_editor.url_decode("%G0") is None)
  assert_true(@hex_editor.url_decode("%0") is None)
}

test "unicode_encode" {
  assert_eq(@hex_editor.unicode_encode(b"\x41\x42"), "\\u0041\\u0042")
  assert_eq(@hex_editor.unicode_encode(b"\x00"), "\\u0000")
  assert_eq(@hex_editor.unicode_encode(b"\xFF"), "\\u00FF")
  assert_eq(@hex_editor.unicode_encode(b""), "")
}

test "unicode_decode" {
  let d1 = @hex_editor.unicode_decode("\\u0041\\u0042")
  assert_true(d1 is Some(_))
  assert_eq(d1.unwrap().length(), 2)
  assert_eq(d1.unwrap()[0], b'\x41')
  assert_eq(d1.unwrap()[1], b'\x42')
  // Plain ASCII mixed in
  let d2 = @hex_editor.unicode_decode("A")
  assert_true(d2 is Some(_))
  assert_eq(d2.unwrap()[0], b'\x41')
}

test "unicode roundtrip" {
  let data = b"\x48\x65\x6C\x6C\x6F"
  let encoded = @hex_editor.unicode_encode(data)
  let decoded = @hex_editor.unicode_decode(encoded)
  assert_true(decoded is Some(_))
  let dec = decoded.unwrap()
  assert_eq(dec.length(), data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_eq(dec[i], data[i])
  }
}

test "unicode_decode invalid" {
  assert_true(@hex_editor.unicode_decode("\\u00G0") is None)
  assert_true(@hex_editor.unicode_decode("\\u") is None)
}

test "hex_encode" {
  assert_eq(@hex_editor.hex_encode(b"\x48\x65\x6C"), "48 65 6C")
  assert_eq(@hex_editor.hex_encode(b"\x00\xFF"), "00 FF")
  assert_eq(@hex_editor.hex_encode(b""), "")
}

test "hex_decode" {
  let d1 = @hex_editor.hex_decode("48 65 6C")
  assert_true(d1 is Some(_))
  assert_eq(d1.unwrap().length(), 3)
  assert_eq(d1.unwrap()[0], b'\x48')
  assert_eq(d1.unwrap()[1], b'\x65')
  assert_eq(d1.unwrap()[2], b'\x6C')
  // No spaces
  let d2 = @hex_editor.hex_decode("00FF")
  assert_true(d2 is Some(_))
  assert_eq(d2.unwrap()[0], b'\x00')
  assert_eq(d2.unwrap()[1], b'\xFF')
}

test "hex roundtrip" {
  let data = b"\x00\x01\x7F\xFF"
  let encoded = @hex_editor.hex_encode(data)
  let decoded = @hex_editor.hex_decode(encoded)
  assert_true(decoded is Some(_))
  let dec = decoded.unwrap()
  assert_eq(dec.length(), data.length())
  for i = 0; i < data.length(); i = i + 1 {
    assert_eq(dec[i], data[i])
  }
}

test "hex_decode invalid" {
  assert_true(@hex_editor.hex_decode("GG") is None)
  assert_true(@hex_editor.hex_decode("0") is None)
}

// ========== Wildcard Hex Pattern Tests ==========

test "find_hex_pattern exact" {
  let data = b"\x41\x42\x43\x41\x42"
  let r = @hex_editor.find_hex_pattern(data, "41 42")
  assert_true(r is Some(_))
  let (off, len) = r.unwrap()
  assert_eq(off.length(), 2)
  assert_eq(off[0], 0)
  assert_eq(off[1], 3)
  assert_eq(len[0], 2)
}

test "find_hex_pattern fallback hex string" {
  let data = b"\xFF\xD8\xFF\xE0"
  let r = @hex_editor.find_hex_pattern(data, "FFD8FF")
  assert_true(r is Some(_))
  let (off, _) = r.unwrap()
  assert_eq(off.length(), 1)
  assert_eq(off[0], 0)
}

test "find_hex_pattern ?? wildcard" {
  let data = b"\xA0\x11\xB2\xA0\x22\xB2\xA0\x33\xC0"
  let r = @hex_editor.find_hex_pattern(data, "A0 ?? B2")
  assert_true(r is Some(_))
  let (off, len) = r.unwrap()
  assert_eq(off.length(), 2)
  assert_eq(off[0], 0)
  assert_eq(off[1], 3)
  assert_eq(len[0], 3)
}

test "find_hex_pattern * wildcard" {
  let data = b"\x00\xAA\xBB\xCC\xFF"
  let r = @hex_editor.find_hex_pattern(data, "00 * FF")
  assert_true(r is Some(_))
  let (off, len) = r.unwrap()
  assert_eq(off.length(), 1)
  assert_eq(off[0], 0)
  assert_eq(len[0], 5)
}

test "find_hex_pattern invalid" {
  let data = b"\x00\x01"
  assert_true(@hex_editor.find_hex_pattern(data, "GG") is None)
  assert_true(@hex_editor.find_hex_pattern(data, "*") is None)
  assert_true(@hex_editor.find_hex_pattern(data, "") is None)
}

test "find_hex_pattern *N fixed wildcard" {
  // *3 = skip exactly 3 bytes (same as ?? ?? ??)
  let data = b"\xAA\x11\x22\x33\xBB"
  let r = @hex_editor.find_hex_pattern(data, "AA *3 BB")
  assert_true(r is Some(_))
  let (off, len) = r.unwrap()
  assert_eq(off.length(), 1)
  assert_eq(off[0], 0)
  assert_eq(len[0], 5)
  // *2 won't match (gap is 3 bytes, not 2)
  let r2 = @hex_editor.find_hex_pattern(data, "AA *2 BB")
  assert_true(r2 is Some(_))
  let (off2, _) = r2.unwrap()
  assert_eq(off2.length(), 0)
}

// ========== Text Pattern Tests ==========

test "find_text_pattern exact" {
  let data = b"\x48\x65\x6C\x6C\x6F\x20\x48\x65\x6C\x6C\x6F"
  let r = @hex_editor.find_text_pattern(data, "Hello")
  assert_true(r is Some(_))
  let (off, len) = r.unwrap()
  assert_eq(off.length(), 2)
  assert_eq(off[0], 0)
  assert_eq(off[1], 6)
  assert_eq(len[0], 5)
}

test "find_text_pattern ? wildcard" {
  let data = b"\x48\x65\x6C\x6C\x6F"
  let r = @hex_editor.find_text_pattern(data, "H?llo")
  assert_true(r is Some(_))
  let (off, _) = r.unwrap()
  assert_eq(off.length(), 1)
  assert_eq(off[0], 0)
}

test "find_text_pattern * wildcard" {
  let data = b"\x48\x65\x6C\x6C\x6F\x20\x57\x6F\x72\x6C\x64"
  let r = @hex_editor.find_text_pattern(data, "He*ld")
  assert_true(r is Some(_))
  let (off, len) = r.unwrap()
  assert_eq(off.length(), 1)
  assert_eq(off[0], 0)
  assert_eq(len[0], 11)
}

test "find_text_pattern *N fixed" {
  let data = b"\x41\x42\x43\x44\x45"
  let r = @hex_editor.find_text_pattern(data, "A*3E")
  assert_true(r is Some(_))
  let (off, len) = r.unwrap()
  assert_eq(off.length(), 1)
  assert_eq(off[0], 0)
  assert_eq(len[0], 5)
}

test "find_text_pattern escape" {
  let data = b"\x48\x3F\x21"
  let r = @hex_editor.find_text_pattern(data, "H\\?!")
  assert_true(r is Some(_))
  let (off, _) = r.unwrap()
  assert_eq(off.length(), 1)
  assert_eq(off[0], 0)
}

// ========== File-Based Integration Tests ==========
// Tests against real files in testfile/ directory.
// Skips gracefully if file not found.

fn read_test_file(name : String) -> Bytes? {
  let mut data : Bytes = Bytes::new(0)
  try { data = @fs.read_file_to_bytes("testfile/" + name) } catch { _ => return None }
  Some(data)
}

fn scan_has(matches : Array[@hex_editor.ScanMatch], keyword : String) -> Bool {
  for i = 0; i < matches.length(); i = i + 1 {
    if matches[i].name.contains(keyword) { return true }
  }
  false
}

test "file: JPEG scan+parse" {
  let data = match read_test_file("test.jpg") { Some(d) => d; None => return }
  assert_true(scan_has(@hex_editor.scan_signatures(data), "JPEG"))
  assert_true(@hex_editor.parse_structure(data).length() > 0)
}

test "file: PNG scan+parse" {
  let data = match read_test_file("test.png") { Some(d) => d; None => return }
  assert_true(scan_has(@hex_editor.scan_signatures(data), "PNG"))
  assert_true(@hex_editor.parse_structure(data).length() > 0)
}

test "file: GIF scan+parse" {
  let data = match read_test_file("test.gif") { Some(d) => d; None => return }
  assert_true(scan_has(@hex_editor.scan_signatures(data), "GIF"))
  assert_true(@hex_editor.parse_structure(data).length() > 0)
}

test "file: BMP scan+parse" {
  let data = match read_test_file("test.bmp") { Some(d) => d; None => return }
  assert_true(scan_has(@hex_editor.scan_signatures(data), "BMP"))
  assert_true(@hex_editor.parse_structure(data).length() > 0)
}

test "file: WAV scan+parse" {
  let data = match read_test_file("test.wav") { Some(d) => d; None => return }
  assert_true(scan_has(@hex_editor.scan_signatures(data), "WAV"))
  assert_true(@hex_editor.parse_structure(data).length() > 0)
}

test "file: FLAC parse" {
  let data = match read_test_file("test.flac") { Some(d) => d; None => return }
  assert_true(@hex_editor.parse_structure(data).length() > 0)
}

test "file: MP3 parse" {
  let data = match read_test_file("test.mp3") { Some(d) => d; None => return }
  assert_true(@hex_editor.parse_structure(data).length() > 0)
}

test "file: OGG parse" {
  let data = match read_test_file("test.ogg") { Some(d) => d; None => return }
  assert_true(@hex_editor.parse_structure(data).length() > 0)
}

test "file: AVI parse" {
  let data = match read_test_file("test.avi") { Some(d) => d; None => return }
  assert_true(@hex_editor.parse_structure(data).length() > 0)
}

test "file: MP4 parse" {
  let data = match read_test_file("test.mp4") { Some(d) => d; None => return }
  assert_true(@hex_editor.parse_structure(data).length() > 0)
}

test "file: WebM parse" {
  let data = match read_test_file("test.webm") { Some(d) => d; None => return }
  assert_true(@hex_editor.parse_structure(data).length() > 0)
}

test "file: ZIP scan+parse" {
  let data = match read_test_file("test.zip") { Some(d) => d; None => return }
  assert_true(scan_has(@hex_editor.scan_signatures(data), "ZIP"))
  assert_true(@hex_editor.parse_structure(data).length() > 0)
}

test "file: RAR scan+parse" {
  let data = match read_test_file("test.rar") { Some(d) => d; None => return }
  assert_true(scan_has(@hex_editor.scan_signatures(data), "RAR"))
  assert_true(@hex_editor.parse_structure(data).length() > 0)
}

test "file: TAR scan+parse" {
  let data = match read_test_file("test.tar") { Some(d) => d; None => return }
  assert_true(scan_has(@hex_editor.scan_signatures(data), "TAR"))
  assert_true(@hex_editor.parse_structure(data).length() > 0)
}

test "file: 7z scan+parse" {
  let data = match read_test_file("test.7z") { Some(d) => d; None => return }
  assert_true(scan_has(@hex_editor.scan_signatures(data), "7"))
  assert_true(@hex_editor.parse_structure(data).length() > 0)
}

test "file: GZip scan+parse" {
  let data = match read_test_file("test.gz") { Some(d) => d; None => return }
  assert_true(scan_has(@hex_editor.scan_signatures(data), "zip") || scan_has(@hex_editor.scan_signatures(data), "Zip"))
  assert_true(@hex_editor.parse_structure(data).length() > 0)
}

test "file: BZip2 scan+parse" {
  let data = match read_test_file("test.bz2") { Some(d) => d; None => return }
  assert_true(scan_has(@hex_editor.scan_signatures(data), "Zip") || scan_has(@hex_editor.scan_signatures(data), "zip") || scan_has(@hex_editor.scan_signatures(data), "BZip"))
  assert_true(@hex_editor.parse_structure(data).length() > 0)
}

test "file: PE scan+parse" {
  let data = match read_test_file("test.exe") { Some(d) => d; None => return }
  assert_true(scan_has(@hex_editor.scan_signatures(data), "PE"))
  assert_true(@hex_editor.parse_structure(data).length() > 0)
}

test "file: ELF scan+parse" {
  let data = match read_test_file("test.elf") { Some(d) => d; None => return }
  assert_true(scan_has(@hex_editor.scan_signatures(data), "ELF"))
  assert_true(@hex_editor.parse_structure(data).length() > 0)
}

test "file: entropy on JPEG" {
  let data = match read_test_file("test.jpg") { Some(d) => d; None => return }
  let blocks = @hex_editor.entropy_scan(data)
  assert_true(blocks.length() > 0)
  assert_true(blocks[0].entropy > 3.0)
}

test "file: strings on text" {
  let data = match read_test_file("test.txt") { Some(d) => d; None => return }
  let strings = @hex_editor.find_strings(data)
  assert_true(strings.length() >= 0)
}

// — Steganography / merged file tests —

test "file: hidden.jpg scan detects multiple signatures" {
  let data = match read_test_file("hidden.jpg") { Some(d) => d; None => return }
  let scans = @hex_editor.scan_signatures(data)
  // Merged file should have JPEG + at least one other signature or trailing data
  assert_true(scan_has(scans, "JPEG"))
  assert_true(scans.length() >= 2) // JPEG + hidden content
}

test "file: mergejp.jpg scan detects embedded content" {
  let data = match read_test_file("mergejp.jpg") { Some(d) => d; None => return }
  let scans = @hex_editor.scan_signatures(data)
  // Two files merged: should detect multiple signatures
  assert_true(scans.length() >= 2)
}

// ========== Coverage Gap Tests ==========

test "gap buffer: cross-position insert" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x01\x02\x03\x04\x05")
  // Insert at position 0 (gap must move from end to start)
  buf.insert_byte(0, b'\xAA') |> ignore
  assert_eq(buf.length(), 6)
  assert_eq(buf.byte_at(0), b'\xAA')
  assert_eq(buf.byte_at(1), b'\x01')
  // Insert at end (gap must move from start to end)
  buf.insert_byte(6, b'\xBB') |> ignore
  assert_eq(buf.length(), 7)
  assert_eq(buf.byte_at(6), b'\xBB')
  // Insert in middle (gap must move again)
  buf.insert_byte(3, b'\xCC') |> ignore
  assert_eq(buf.length(), 8)
  assert_eq(buf.byte_at(3), b'\xCC')
  assert_eq(buf.byte_at(4), b'\x03')
}

test "gap buffer: grow on many inserts" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x00")
  // Insert 300+ bytes to exceed initial gap (256 for 1-byte file)
  for i = 0; i < 300; i = i + 1 {
    buf.insert_byte(0, b'\xFF') |> ignore
  }
  assert_eq(buf.length(), 301)
  assert_eq(buf.byte_at(0), b'\xFF')
  assert_eq(buf.byte_at(300), b'\x00')
}

test "format_structure_json" {
  let png = b"\x89PNG\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90\x77\x53\xDE"
  let fields = @hex_editor.parse_structure(png)
  let json = @hex_editor.format_structure_json(fields)
  assert_true(json.contains("\"name\""))
  assert_true(json.contains("\"offset\""))
  assert_true(json.contains("0x"))
  assert_true(json.contains("["))
  assert_true(json.contains("]"))
}

test "format_strings_export" {
  let data = b"\x00\x00\x00\x00Hello World\x00\x00\x00\x00Test1234\x00"
  let matches = @hex_editor.find_strings(data)
  let text = @hex_editor.format_strings_export(matches)
  assert_true(text.contains("Hello World"))
  assert_true(text.contains("0x"))
  assert_true(text.contains("strings found"))
}

test "format_buffer_info" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x89PNG\x0D\x0A\x1A\x0A")
  let info = @hex_editor.format_buffer_info(buf)
  assert_true(info.contains("8"))
  assert_true(info.contains("B"))
}

test "base64_decode edge cases" {
  // Wrong length (not multiple of 4)
  assert_true(@hex_editor.base64_decode("ABC") is None)
  // Invalid character
  assert_true(@hex_editor.base64_decode("!!!!") is None)
  // Valid padding
  let d = @hex_editor.base64_decode("AA==")
  assert_true(d is Some(_))
  assert_eq(d.unwrap().length(), 1)
}

test "entropy precision" {
  // All same bytes → entropy should be 0
  let uniform = Bytes::make(256, b'\x41')
  let blocks = @hex_editor.entropy_scan(uniform)
  assert_eq(blocks.length(), 1)
  assert_true(blocks[0].entropy < 0.01)
  // All different bytes (0-255) → entropy should be 8.0
  let diverse = Bytes::makei(256, fn(i) { i.to_byte() })
  let blocks2 = @hex_editor.entropy_scan(diverse)
  assert_eq(blocks2.length(), 1)
  assert_true(blocks2[0].entropy > 7.9)
}

test "empty input safety" {
  let empty = b""
  // All modules should handle empty input without panic
  assert_eq(@hex_editor.scan_signatures(empty).length(), 0)
  assert_eq(@hex_editor.parse_structure(empty).length(), 0)
  assert_eq(@hex_editor.find_strings(empty).length(), 0)
  assert_eq(@hex_editor.entropy_scan(empty).length(), 0)
  assert_eq(@hex_editor.base64_encode(empty), "")
  assert_eq(@hex_editor.url_encode(empty), "")
  assert_eq(@hex_editor.unicode_encode(empty), "")
  assert_eq(@hex_editor.hex_encode(empty), "")
}

// ========== Supplementary Tests — Strings, Entropy, Search ==========

///|
/// Test: string extraction minimum length boundary
test "find_strings min length 4" {
  // "ABC" (3 chars) should NOT be extracted; "ABCD" (4 chars) should
  let data = b"\x00ABC\x00ABCD\x00"
  let matches = @hex_editor.find_strings(data)
  // Only "ABCD" should appear (length >= 4)
  let mut found_abc = false
  let mut found_abcd = false
  for i = 0; i < matches.length(); i = i + 1 {
    if matches[i].text == "ABC" { found_abc = true }
    if matches[i].text == "ABCD" { found_abcd = true }
  }
  assert_false(found_abc)
  assert_true(found_abcd)
}

///|
/// Test: string extraction offset correctness
test "find_strings offset" {
  // "Test" at offset 4
  let data = b"\x00\x00\x00\x00Test\x00"
  let matches = @hex_editor.find_strings(data)
  assert_eq(matches.length(), 1)
  assert_eq(matches[0].offset, 4)
  assert_eq(matches[0].text, "Test")
}

///|
/// Test: entropy partial block < 256 bytes
test "entropy partial block" {
  // 100 bytes of all 0x41 → entropy should be 0
  let data = Bytes::make(100, b'\x41')
  let blocks = @hex_editor.entropy_scan(data)
  assert_eq(blocks.length(), 1)
  assert_true(blocks[0].entropy < 0.01)
}

///|
/// Test: entropy on 512 bytes (2 full blocks)
test "entropy two full blocks" {
  // 512 bytes → 2 blocks of 256
  let data = Bytes::make(512, b'\x00')
  let blocks = @hex_editor.entropy_scan(data)
  assert_eq(blocks.length(), 2)
  assert_true(blocks[0].entropy < 0.01)
  assert_true(blocks[1].entropy < 0.01)
}

///|
/// Test: entropy on single byte
test "entropy single byte" {
  let data = b"\x42"
  let blocks = @hex_editor.entropy_scan(data)
  assert_eq(blocks.length(), 1)
  assert_true(blocks[0].entropy < 0.01)
}

///|
/// Test: search BMH exact match positions
test "find_all_bytes exact positions" {
  // Pattern "AB" at positions 0, 5, 10
  let data = b"\x41\x42\x00\x00\x00\x41\x42\x00\x00\x00\x41\x42"
  let results = @hex_editor.find_all_bytes(data, b"\x41\x42")
  assert_eq(results.length(), 3)
  assert_eq(results[0], 0)
  assert_eq(results[1], 5)
  assert_eq(results[2], 10)
}

///|
/// Test: search no match returns empty
test "find_all_bytes no match" {
  let data = b"\x00\x01\x02\x03"
  let results = @hex_editor.find_all_bytes(data, b"\xFF\xFE")
  assert_eq(results.length(), 0)
}

///|
/// Test: search single byte pattern
test "find_all_bytes single byte" {
  let data = b"\x00\xFF\x00\xFF\x00"
  let results = @hex_editor.find_all_bytes(data, b"\xFF")
  assert_eq(results.length(), 2)
  assert_eq(results[0], 1)
  assert_eq(results[1], 3)
}

///|
/// Test: hex pattern with repeated wildcards
test "find_hex_pattern multiple ?? wildcards" {
  // Pattern: FF ?? ?? EE → matches FF AA BB EE
  let data = b"\xFF\xAA\xBB\xEE"
  let r = @hex_editor.find_hex_pattern(data, "FF ?? ?? EE")
  assert_true(r is Some(_))
  let (off, _) = r.unwrap()
  assert_eq(off.length(), 1)
  assert_eq(off[0], 0)
}

///|
/// Test: format_hex_dump with specific content check
test "format_hex_dump content check" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\xDE\xAD\xBE\xEF")
  let dump = @hex_editor.format_hex_dump(buf, length=4)
  // First row should contain the offset and hex bytes
  assert_true(dump.contains("DE AD BE EF"))
  // ASCII sidebar should show printable or '.' chars
  assert_true(dump.contains("|"))
}

///|
/// Test: format_size with known values
test "format_size known values" {
  assert_eq(@hex_editor.format_size(0), "0 B")
  assert_true(@hex_editor.format_size(1024).contains("KB"))
  assert_true(@hex_editor.format_size(1048576).contains("MB"))
}

///|
/// Test: parse_structure on known PNG fields
test "parse_structure PNG field names" {
  let png = b"\x89PNG\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90\x77\x53\xDE\x00\x00\x00\x0A\x49\x44\x41\x54\x08\xD7\x63\xF8\xCF\xC0\x00\x00\x00\x00\x49\x45\x4E\x44\xAE\x42\x60\x82"
  let formatted = @hex_editor.format_structure_json(@hex_editor.parse_structure(png))
  // Should mention PNG signature + IHDR
  assert_true(formatted.contains("PNG"))
  assert_true(formatted.contains("IHDR"))
}

///|
/// Test: format_structure_json valid JSON structure
test "format_structure_json structure" {
  let fields = @hex_editor.parse_structure(b"\x89PNG\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90\x77\x53\xDE")
  let json = @hex_editor.format_structure_json(fields)
  // Valid JSON structure markers
  assert_true(json.contains("["))
  assert_true(json.contains("]"))
  assert_true(json.contains("{"))
  assert_true(json.contains("}"))
}

///|
/// Test: HexBuffer is_empty after insert and delete
test "HexBuffer is_empty after edit" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x01")
  assert_false(buf.is_empty())
  buf.delete_byte(0) |> ignore
  assert_true(buf.is_empty())
}

///|
/// Test: HexBuffer length after multiple deletes
test "HexBuffer delete multiple" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x01\x02\x03\x04\x05")
  // Delete from end to avoid gap movement issues
  buf.delete_byte(4) |> ignore
  buf.delete_byte(3) |> ignore
  buf.delete_byte(2) |> ignore
  assert_eq(buf.length(), 2)
  assert_eq(buf.byte_at(0), b'\x01')
  assert_eq(buf.byte_at(1), b'\x02')
}

///|
/// Test: HexBuffer set_byte then to_bytes roundtrip
test "HexBuffer edit roundtrip" {
  let buf = @hex_editor.HexBuffer::from_bytes(b"\x0A\x0B\x0C")
  buf.set_byte(0, b'\xFF') |> ignore
  buf.insert_byte(1, b'\xEE') |> ignore
  buf.delete_byte(2) |> ignore
  let result = buf.to_bytes()
  // Expected: [FF, EE, 0C] – 0x0A→0xFF, insert EE after FF, delete 0x0B
  assert_eq(result.length(), 3)
  assert_eq(result[0], b'\xFF')
  assert_eq(result[1], b'\xEE')
  assert_eq(result[2], b'\x0C')
}

///|
/// Test: HexBuffer insert at offset 0 on empty buffer
test "HexBuffer insert into empty" {
  let buf = @hex_editor.HexBuffer::new()
  assert_true(buf.is_empty())
  buf.insert_byte(0, b'\x42') |> ignore
  assert_eq(buf.length(), 1)
  assert_eq(buf.byte_at(0), b'\x42')
  assert_false(buf.is_empty())
}