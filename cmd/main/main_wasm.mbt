///|
/// Minimal main for wasm-gc target — CLI view/info/search only (no TUI)
/// For full TUI mode, use: moon build --target native

fn main {
  let argv = get_argv()
  if argv.length() == 0 {
    println("Hex Editor - CLI mode (wasm target)")
    println("Usage: moon run cmd/main -- <command> [options]")
    println("Commands: view, info, search, help")
    println("For TUI interactive mode, use: moon run --target native cmd/main")
    return
  }

  let cmd = argv[0]
  match cmd {
    "view" => cmd_view(argv)
    "info" => cmd_info(argv)
    "search" => cmd_search(argv)
    "help" => cmd_help()
    _ => {
      println("Unknown command: \{cmd}")
      println("Try: view <file>, info <file>, search <file> <pattern>, help")
    }
  }
}

///|
/// Get command-line args.
fn get_argv() -> Array[String] {
  let raw = @sys.get_cli_args()
  if raw.length() <= 1 { return [] }
  let result = []
  for i = 1; i < raw.length(); i = i + 1 {
    result.push(raw[i])
  }
  result
}

///|
/// Find file path in argv.
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

fn is_option(arg : String) -> Bool { string_starts_with(arg, "-") }
fn needs_value(arg : String) -> Bool {
  arg == "-o" || arg == "--offset" || arg == "-n" || arg == "--length" || arg == "-b" || arg == "--bytes-per-row"
}

fn get_flag(argv : Array[String], flag : String) -> Bool {
  for i = 0; i < argv.length(); i = i + 1 { if argv[i] == flag { return true } }
  false
}

fn get_int_option(argv : Array[String], short : String, long : String, default : Int) -> Int {
  for i = 0; i < argv.length(); i = i + 1 {
    if (argv[i] == short || argv[i] == long) && i + 1 < argv.length() {
      match parse_int(argv[i + 1]) { Some(v) => return v; None => return default }
    }
  }
  default
}

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
/// View command.
fn cmd_view(argv : Array[String]) -> Unit {
  let file_path = match find_file_arg(argv, "view") {
    Some(p) => p
    None => { println("Usage: view <file> [-n N] [-o N]"); return }
  }
  let result = load_file(file_path)
  match result {
    Err(m) => { println("Error: \{m}"); return }
    Ok(buf) => {
      let offset = get_int_option(argv, "-o", "--offset", 0)
      let length = get_int_option(argv, "-n", "--length", -1)
      let bpr = get_int_option(argv, "-b", "--bytes-per-row", 16)
      let ascii = !get_flag(argv, "--no-ascii")
      let upper = !get_flag(argv, "--lowercase")
      let len = buf.length()
      let display_len = if length < 0 || offset + length > len { len - offset } else { length }
      guard display_len > 0 else { return }

      println(@lib.format_buffer_info(buf))
      println("")
      let config = @lib.HexViewConfig::default()
        .with_bytes_per_row(bpr).with_ascii(ascii).with_uppercase(upper)
      println(@lib.format_hex_dump(buf, start_offset=offset, length=display_len, config=config))
      let remaining = len - offset - display_len
      if remaining > 0 { println("... (\{remaining} more bytes)") }
    }
  }
}

///|
/// Info command.
fn cmd_info(argv : Array[String]) -> Unit {
  let file_path = match find_file_arg(argv, "info") {
    Some(p) => p
    None => { println("Usage: info <file>"); return }
  }
  let result = load_file(file_path)
  match result {
    Err(m) => { println("Error: \{m}"); return }
    Ok(buf) => {
      let len = buf.length()
      println("File: \{file_path}")
      println("Size: \{len} bytes (\{@lib.format_size(len)})")
      if len >= 2 {
        let b0 = buf.get_byte(0).unwrap()
        let b1 = buf.get_byte(1).unwrap()
        let magic = b0.to_int() * 256 + b1.to_int()
        match detect_type(magic, len) {
          Some(t) => println("Type: \{t}")
          None => println("Magic: \{@lib.format_byte_hex(b0)} \{@lib.format_byte_hex(b1)}")
        }
      }
    }
  }
}

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
/// Search command.
fn cmd_search(argv : Array[String]) -> Unit {
  let file_path = match find_file_arg(argv, "search") {
    Some(p) => p
    None => { println("Usage: search <file> <pattern>"); return }
  }
  let pattern_str = match find_second_arg(argv, "search") {
    Some(p) => p
    None => { println("Usage: search <file> <pattern>"); return }
  }
  let result = load_file(file_path)
  match result {
    Err(m) => { println("Error: \{m}"); return }
    Ok(buf) => {
      let data = buf.to_bytes()
      let hex_parsed = @lib.parse_hex_string(pattern_str)
      let search_bytes = match hex_parsed {
        Some(b) => { println("Search hex: \{pattern_str}"); b }
        None => {
          println("Search text: \"\{pattern_str}\"")
          Bytes::makei(pattern_str.length(), i => {
            let ch = pattern_str.get_char(i).unwrap()
            let code = ch.to_int()
            if code >= 0 && code <= 127 { code.to_byte() } else { b'?' }
          })
        }
      }
      let results = @lib.find_all_bytes(data, search_bytes)
      let count = results.length()
      if count == 0 { println("Not found."); return }
      println("Found \{count} match(es):")
      let show = if count < 10 { count } else { 10 }
      let config = @lib.HexViewConfig::default()
      for idx = 0; idx < show; idx = idx + 1 {
        let off = results[idx]
        let ctx = if off >= 16 { off - 16 } else { 0 }
        let clen = if off >= 16 { 48 } else { 32 }
        println("  #\{idx + 1} @ 0x\{@lib.to_hex_string(off, width=8)}")
        println(@lib.format_hex_dump(buf, start_offset=ctx, length=clen, config=config))
      }
      if count > show { println("  ... +\{count - show} more") }
    }
  }
}

///|
/// Help.
fn cmd_help() -> Unit {
  println("Hex Editor - CLI mode")
  println("  view <file> [-n N] [-o N]    Display hex dump")
  println("  info <file>                   File information")
  println("  search <file> <pattern>       Search")
  println("  help                          This help")
  println("For TUI: moon run --target native cmd/main")
}

///|
/// Load file.
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
/// Parse int (supports 0x hex).
fn parse_int(s : String) -> Int? {
  let len = s.length()
  guard len > 0 else { None }
  let mut i = 0
  let mut sign = 1
  let ch0 = s.get_char(0).unwrap()
  if ch0 == '-' { sign = -1; i = 1 } else if ch0 == '+' { i = 1 }
  if i + 1 < len && s.get_char(i).unwrap() == '0' {
    let next = s.get_char(i + 1).unwrap()
    if next == 'x' || next == 'X' { return parse_hex(s, i + 2, sign) }
  }
  let mut result = 0
  for j = i; j < len; j = j + 1 {
    let d = s.get_char(j).unwrap().to_int() - '0'.to_int()
    if d < 0 || d > 9 { return None }
    result = result * 10 + d
  }
  Some(result * sign)
}

fn parse_hex(s : String, start : Int, sign : Int) -> Int? {
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
