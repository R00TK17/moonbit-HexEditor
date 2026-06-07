// Shared helpers used by main.mbt, main_wasm.mbt, and tui modules

///|
/// Get command-line args (skip program name).
fn get_argv() -> Array[String] {
  let raw = @sys.get_cli_args()
  if raw.length() <= 1 { return [] }
  let result = []
  for i = 1; i < raw.length(); i = i + 1 { result.push(raw[i]) }
  result
}

///|
/// Check string prefix.
fn string_starts_with(s : String, prefix : String) -> Bool {
  let sl = s.length()
  let pl = prefix.length()
  guard sl >= pl else { false }
  for i = 0; i < pl; i = i + 1 {
    if s.get_char(i).unwrap() != prefix.get_char(i).unwrap() { return false }
  }
  true
}

///|
/// Parse integer (decimal or 0x hex).
fn parse_int(s : String) -> Int? {
  let len = s.length()
  guard len > 0 else { None }
  let mut i = 0
  let mut sign = 1
  let ch0 = s.get_char(0).unwrap()
  if ch0 == '-' { sign = -1; i = 1 } else if ch0 == '+' { i = 1 }
  if i + 1 < len && s.get_char(i).unwrap() == '0' {
    let next = s.get_char(i + 1).unwrap()
    if next == 'x' || next == 'X' { return parse_hex_digits(s, i + 2, sign) }
  }
  let mut result = 0
  for j = i; j < len; j = j + 1 {
    let d = s.get_char(j).unwrap().to_int() - '0'.to_int()
    if d < 0 || d > 9 { return None }
    result = result * 10 + d
  }
  Some(result * sign)
}

///|
/// Parse hex digits from a string.
fn parse_hex_digits(s : String, start : Int, sign : Int) -> Int? {
  let mut result = 0
  for i = start; i < s.length(); i = i + 1 {
    let c = s.get_char(i).unwrap().to_int()
    let d = if c >= '0'.to_int() && c <= '9'.to_int() { c - '0'.to_int() }
    else if c >= 'A'.to_int() && c <= 'F'.to_int() { c - 'A'.to_int() + 10 }
    else if c >= 'a'.to_int() && c <= 'f'.to_int() { c - 'a'.to_int() + 10 }
    else { return None }
    result = result * 16 + d
  }
  Some(result * sign)
}

///|
/// Load file into HexBuffer.
fn load_file(path : String) -> Result[@lib.HexBuffer, String] {
  if !@fs.path_exists(path) { return Err("Not found: \{path}") }
  try {
    Ok(@lib.HexBuffer::from_file(path))
  } catch {
    @fs.IOError::IOError(m) => Err("IO: \{m}")
    _ => Err("Unknown error")
  }
}

///|
/// Detect file type from magic bytes.
fn detect_type(magic : Int, size : Int) -> String? {
  match magic {
    0xFFD8 => Some("JPEG image")
    0x8950 => Some("PNG image")
    0x4749 => Some("GIF image")
    0x424D => Some("BMP image")
    0x4D5A | 0x5A4D => Some("PE executable")
    0x504B => Some("ZIP / Office doc")
    0x2550 => Some("PDF document")
    0x1F8B => Some("GZip compressed")
    0xCAFE => Some("Java class")
    0xFEFF => Some("UTF-16 BE BOM")
    0xFFFE => Some("UTF-16 LE BOM")
    _ => if magic >> 8 == 0x7F && size >= 4 { Some("ELF executable") } else { None }
  }
}

///|
/// Is arg an option flag?
fn is_option(arg : String) -> Bool { string_starts_with(arg, "-") }

///|
/// Does option need a value?
fn needs_value(arg : String) -> Bool {
  arg == "-o" || arg == "--offset" || arg == "-n" || arg == "--length" || arg == "-b" || arg == "--bytes-per-row"
}

///|
/// Find file path arg (first positional after command).
fn find_file_arg(argv : Array[String], command : String) -> String? {
  for i = 0; i < argv.length(); i = i + 1 {
    if i == 0 && argv[i] == command { continue i + 1 }
    if is_option(argv[i]) {
      if needs_value(argv[i]) && i + 1 < argv.length() { continue i + 2 }
      continue i + 1
    }
    return Some(argv[i])
  }
  None
}

///|
/// Find second positional arg (for search command).
fn find_second_arg(argv : Array[String], cmd : String) -> String? {
  let mut found_first = false
  for i = 0; i < argv.length(); i = i + 1 {
    if argv[i] == cmd { continue i + 1 }
    if is_option(argv[i]) {
      if needs_value(argv[i]) { continue i + 2 }
      continue i + 1
    }
    if !found_first { found_first = true; continue i + 1 }
    return Some(argv[i])
  }
  None
}

///|
/// Check if flag is present.
fn has_flag(argv : Array[String], flag : String) -> Bool {
  for i = 0; i < argv.length(); i = i + 1 { if argv[i] == flag { return true } }
  false
}

///|
/// Get integer option value.
fn get_int_option(argv : Array[String], short : String, long : String, default : Int) -> Int {
  for i = 0; i < argv.length(); i = i + 1 {
    if (argv[i] == short || argv[i] == long) && i + 1 < argv.length() {
      match parse_int(argv[i + 1]) { Some(v) => return v; None => return default }
    }
  }
  default
}

///|
/// Build HexViewConfig from CLI options.
fn build_view_config(bpr : Int, ascii : Bool, upper : Bool) -> @lib.HexViewConfig {
  @lib.HexViewConfig::default()
    .with_bytes_per_row(bpr)
    .with_ascii(ascii)
    .with_uppercase(upper)
}
