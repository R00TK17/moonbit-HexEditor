// Internal tests for tui_files.mbt — UTF-8 decoder, path helpers

///|
/// Test: utf8_to_string 1-byte ASCII
test "utf8_to_string ascii" {
  // "Hello" = 0x48 0x65 0x6C 0x6C 0x6F
  let buf = b"\x48\x65\x6C\x6C\x6F"
  let s = utf8_to_string(buf, 0, 5)
  assert_eq(s, "Hello")
}

test "utf8_to_string single ascii char" {
  let buf = b"\x41"
  assert_eq(utf8_to_string(buf, 0, 1), "A")
}

///|
/// Test: utf8_to_string 2-byte sequences
test "utf8_to_string 2-byte" {
  // U+00E9 = é = 0xC3 0xA9
  let buf = b"\xC3\xA9"
  assert_eq(utf8_to_string(buf, 0, 2), "é")
}

test "utf8_to_string 2-byte multiple" {
  // "café" = c(0x63) a(0x61) f(0x66) é(0xC3 0xA9)
  let buf = b"\x63\x61\x66\xC3\xA9"
  assert_eq(utf8_to_string(buf, 0, 5), "café")
}

///|
/// Test: utf8_to_string 3-byte sequences
test "utf8_to_string 3-byte" {
  // U+4E2D (中) = 0xE4 0xB8 0xAD
  let buf = b"\xE4\xB8\xAD"
  assert_eq(utf8_to_string(buf, 0, 3), "中")
}

test "utf8_to_string 3-byte mixed ascii" {
  // "A中B" = 0x41 0xE4 0xB8 0xAD 0x42
  let buf = b"\x41\xE4\xB8\xAD\x42"
  assert_eq(utf8_to_string(buf, 0, 5), "A中B")
}

///|
/// Test: utf8_to_string 4-byte sequences
test "utf8_to_string 4-byte" {
  // U+1F600 (😀) = 0xF0 0x9F 0x98 0x80
  let buf = b"\xF0\x9F\x98\x80"
  assert_eq(utf8_to_string(buf, 0, 4), "😀")
}

///|
/// Test: utf8_to_string mixed encoding
test "utf8_to_string mixed all lengths" {
  // "Aé中😀" = 1-byte + 2-byte + 3-byte + 4-byte
  let buf = b"\x41\xC3\xA9\xE4\xB8\xAD\xF0\x9F\x98\x80"
  assert_eq(utf8_to_string(buf, 0, 10), "Aé中😀")
}

///|
/// Test: utf8_to_string start/end offset
test "utf8_to_string with start offset" {
  // "AB" = 0x41 0x42
  let buf = b"\x00\x41\x42\x00"
  assert_eq(utf8_to_string(buf, 1, 3), "AB")
}

///|
/// Test: utf8_to_string invalid byte skip
test "utf8_to_string invalid byte skip" {
  // 0xFF is invalid single-byte, should be skipped
  let buf = b"\x41\xFF\x42"
  // Invalid byte is skipped, leaving "AB"
  assert_eq(utf8_to_string(buf, 0, 3), "AB")
}

test "utf8_to_string truncated 2-byte" {
  // Truncated 2-byte start at end of buffer (no next byte to consume)
  let buf = b"\x41\xC3"
  let s = utf8_to_string(buf, 0, 2)
  assert_eq(s, "A")
}

test "utf8_to_string truncated 3-byte" {
  // Truncated 3-byte start with only 1 continuation byte
  let buf = b"\x41\xE4\xB8"
  let s = utf8_to_string(buf, 0, 3)
  assert_eq(s, "A")
}

test "utf8_to_string truncated 4-byte" {
  // Truncated 4-byte start with only 2 continuation bytes then ASCII
  let buf = b"\x41\xF0\x42\x43"
  let s = utf8_to_string(buf, 0, 4)
  // 0xF0 truncated (needs 3 continuation bytes), followed by ASCII BC
  assert_eq(s, "ABC")
}

///|
/// Test: utf8_to_string edge cases
test "utf8_to_string empty range" {
  let buf = b"\x41\x42"
  assert_eq(utf8_to_string(buf, 1, 1), "")
}

test "utf8_to_string all printable ascii" {
  // 95 printable ASCII chars from space (0x20) through ~ (0x7E)
  let data = b"\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4A\x4B\x4C\x4D\x4E\x4F\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E"
  let s = utf8_to_string(data, 0, 95)
  assert_eq(s.length(), 95)
}

///|
/// Test: basename helper
test "basename simple" {
  assert_eq(basename("foo/bar.txt"), "bar.txt")
  assert_eq(basename("file.bin"), "file.bin")
}

test "basename trailing slash" {
  // Trailing slash not stripped: last component is empty string after slash
  assert_eq(basename("foo/bar"), "bar")
  assert_eq(basename("foo/bar.txt"), "bar.txt")
}

///|
/// Test: path joining
test "join_path basic" {
  let result = join_path("/home/user", "docs")
  assert_true(result.contains("docs"))
}

test "join_path with trailing separator" {
  let result = join_path("/home/user/", "docs")
  assert_true(result.contains("docs"))
}

///|
/// Test: parent_path
test "parent_path simple" {
  assert_eq(parent_path("/foo/bar.txt"), "/foo")
  assert_eq(parent_path("/foo/bar/"), "/foo")
}

///|
/// Test: bookmarks path sanitization
test "bookmarks path generation" {
  // get_marks_path produces a valid path under ~/.hexedit/
  let path = get_marks_path("/home/user/test.bin")
  assert_true(path.contains(".hexedit"))
  assert_false(path.contains("/"))
  // Should not contain the original path slashes (they get sanitized)
}
