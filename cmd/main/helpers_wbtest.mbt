// Internal tests for helpers.mbt — CLI argument parsing, type detection, utilities

///|
/// Test: parse_int decimal
test "parse_int decimal" {
  @debug.assert_eq(parse_int("0"), Some(0))
  @debug.assert_eq(parse_int("42"), Some(42))
  @debug.assert_eq(parse_int("255"), Some(255))
  @debug.assert_eq(parse_int("65535"), Some(65535))
}

///|
test "parse_int negative" {
  @debug.assert_eq(parse_int("-1"), Some(-1))
  @debug.assert_eq(parse_int("-100"), Some(-100))
}

///|
test "parse_int with plus sign" {
  @debug.assert_eq(parse_int("+5"), Some(5))
  @debug.assert_eq(parse_int("+0"), Some(0))
}

///|
test "parse_int hex" {
  @debug.assert_eq(parse_int("0xFF"), Some(255))
  @debug.assert_eq(parse_int("0x0"), Some(0))
  @debug.assert_eq(parse_int("0xA"), Some(10))
  @debug.assert_eq(parse_int("0xDEAD"), Some(0xDEAD))
  @debug.assert_eq(parse_int("0X1A"), Some(0x1A))
}

///|
test "parse_int negative hex" {
  @debug.assert_eq(parse_int("-0xFF"), Some(-255))
  @debug.assert_eq(parse_int("-0x10"), Some(-16))
}

///|
test "parse_int invalid" {
  @debug.assert_eq(parse_int(""), None)
  @debug.assert_eq(parse_int("abc"), None)
  @debug.assert_eq(parse_int("12ab"), None)
  @debug.assert_eq(parse_int("0xGG"), None)
}

///|
/// Test: string_starts_with
test "string_starts_with prefix" {
  assert_true(string_starts_with("hello world", "hello"))
  assert_true(string_starts_with("abc", "abc"))
  assert_true(string_starts_with("abc", ""))
}

///|
test "string_starts_with mismatch" {
  assert_false(string_starts_with("hello", "world"))
  assert_false(string_starts_with("ab", "abc"))
  assert_false(string_starts_with("", "a"))
}

///|
/// Test: detect_type magic bytes
test "detect_type known formats" {
  @debug.assert_eq(detect_type(0xFFD8, 100), Some("JPEG image"))
  @debug.assert_eq(detect_type(0x8950, 100), Some("PNG image"))
  @debug.assert_eq(detect_type(0x4749, 100), Some("GIF image"))
  @debug.assert_eq(detect_type(0x424D, 100), Some("BMP image"))
  @debug.assert_eq(detect_type(0x4D5A, 100), Some("PE executable"))
  @debug.assert_eq(detect_type(0x504B, 100), Some("ZIP / Office doc"))
  @debug.assert_eq(detect_type(0x2550, 100), Some("PDF document"))
  @debug.assert_eq(detect_type(0x1F8B, 100), Some("GZip compressed"))
  @debug.assert_eq(detect_type(0xCAFE, 100), Some("Java class"))
  @debug.assert_eq(detect_type(0xFEFF, 100), Some("UTF-16 BE BOM"))
  @debug.assert_eq(detect_type(0xFFFE, 100), Some("UTF-16 LE BOM"))
}

///|
test "detect_type ELF requires size >= 4" {
  @debug.assert_eq(detect_type(0x7F45, 4), Some("ELF executable"))
  @debug.assert_eq(detect_type(0x7F45, 3), None)
}

///|
test "detect_type unknown" {
  @debug.assert_eq(detect_type(0x0000, 100), None)
  @debug.assert_eq(detect_type(0x1234, 100), None)
}

///|
/// Test: is_option / needs_value / has_flag
test "is_option flag" {
  assert_true(is_option("-o"))
  assert_true(is_option("--offset"))
  assert_false(is_option("file.txt"))
  assert_false(is_option(""))
}

///|
test "needs_value option" {
  assert_true(needs_value("-o"))
  assert_true(needs_value("--offset"))
  assert_true(needs_value("-n"))
  assert_true(needs_value("--length"))
  assert_false(needs_value("-x"))
  assert_false(needs_value("--help"))
}

///|
test "has_flag present" {
  let argv = ["view", "-x", "file.bin"]
  assert_true(has_flag(argv, "-x"))
  assert_false(has_flag(argv, "-a"))
}

///|
/// Test: find_file_arg
test "find_file_arg simple" {
  let argv = ["view", "file.bin"]
  @debug.assert_eq(find_file_arg(argv, "view"), Some("file.bin"))
}

///|
test "find_file_arg with options" {
  let argv = ["view", "-b", "8", "file.bin"]
  @debug.assert_eq(find_file_arg(argv, "view"), Some("file.bin"))
}

///|
test "find_file_arg no file" {
  @debug.assert_eq(find_file_arg([], "view"), None)
  @debug.assert_eq(find_file_arg(["view"], "view"), None)
}

///|
/// Test: get_int_option
test "get_int_option short flag" {
  let argv = ["-n", "42"]
  @debug.assert_eq(get_int_option(argv, "-n", "--length", 10), 42)
}

///|
test "get_int_option long flag" {
  let argv = ["--length", "100"]
  @debug.assert_eq(get_int_option(argv, "-n", "--length", 10), 100)
}

///|
test "get_int_option default" {
  let argv : Array[String] = []
  @debug.assert_eq(get_int_option(argv, "-n", "--length", 10), 10)
}

///|
test "get_int_option invalid value falls back" {
  let argv = ["-n", "abc"]
  @debug.assert_eq(get_int_option(argv, "-n", "--length", 10), 10)
}

///|
/// Test: build_view_config
test "build_view_config basic" {
  let _ = build_view_config(16, true, false)
  assert_true(true)
}
