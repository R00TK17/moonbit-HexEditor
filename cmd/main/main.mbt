///|
/// Hex Editor CLI — Main Entry Point
///
/// A command-line hex editor for viewing and editing binary files.
///
/// Usage:
///   moon run cmd/main -- <command> [options]
///
/// Commands:
///   view <file>     Display hex dump of a file
///   info <file>     Show file information
///   search <file> <pattern>  Search for a hex pattern in a file

fn main {
  let argv = get_argv()
  let args = parse_args(argv)
  match args.command {
    "view" => cmd_view(args)
    "info" => cmd_info(args)
    "search" => cmd_search(args)
    "help" => cmd_help()
    _ => {
      println("Hex Editor — A binary file viewer and editor")
      println("Usage: moon run cmd/main -- <command> [options] [file]")
      println("Commands: view, info, search")
      println("Run with 'help' for more information")
    }
  }
}

///|
/// Parsed command-line arguments.
struct Args {
  command : String
  file_path : String?
  offset : Int
  length : Int?
  bytes_per_row : Int
  show_ascii : Bool
  uppercase_hex : Bool
  pattern : String?
} derive(Debug)

///|
/// Parses command-line arguments from argv array.
fn parse_args(argv : Array[String]) -> Args {
  let len = argv.length()
  // Detect command
  let command = if len > 0 { detect_command(argv[0]) } else { "" }
  let file_path = find_file_arg(argv, command)
  let pattern = find_pattern_arg(argv, command)
  let offset = find_int_option(argv, "-o", "--offset", 0)
  let length = find_maybe_int_option(argv, "-n", "--length")
  let bytes_per_row = find_int_option(argv, "-b", "--bytes-per-row", 16)
  let show_ascii = !has_flag(argv, "--no-ascii")
  let uppercase_hex = !has_flag(argv, "--lowercase")

  {
    command,
    file_path,
    offset,
    length,
    bytes_per_row,
    show_ascii,
    uppercase_hex,
    pattern,
  }
}

///|
/// Detects the command from first non-option argument.
fn detect_command(first : String) -> String {
  if first == "view" || first == "info" || first == "search" || first == "help" {
    first
  } else {
    ""
  }
}

///|
/// Finds the file path argument.
fn find_file_arg(argv : Array[String], command : String) -> String? {
  for i = 0; i < argv.length(); i = i + 1 {
    let arg = argv[i]
    // Skip the command itself
    if i == 0 && (arg == command) {
      continue i + 1
    }
    // Skip option flags and their values
    if is_option(arg) {
      if needs_value(arg) && i + 1 < argv.length() {
        continue i + 2
      }
      continue i + 1
    }
    // This is a positional arg
    return Some(arg)
  }
  None
}

///|
/// Finds the pattern argument for search command.
fn find_pattern_arg(argv : Array[String], command : String) -> String? {
  if command != "search" {
    return None
  }
  let mut found_file = false
  for i = 0; i < argv.length(); i = i + 1 {
    let arg = argv[i]
    if i == 0 && arg == command {
      continue i + 1
    }
    if is_option(arg) {
      if needs_value(arg) && i + 1 < argv.length() {
        continue i + 2
      }
      continue i + 1
    }
    if !found_file {
      found_file = true
      continue i + 1
    }
    return Some(arg)
  }
  None
}

///|
/// Checks if a string is a command-line option (starts with - or --).
fn is_option(arg : String) -> Bool {
  string_starts_with(arg, "-")
}

///|
/// Checks if an option needs a following value argument.
fn needs_value(arg : String) -> Bool {
  arg == "-o" || arg == "--offset" ||
  arg == "-n" || arg == "--length" ||
  arg == "-b" || arg == "--bytes-per-row"
}

///|
/// Checks if a flag is present in the arguments.
fn has_flag(argv : Array[String], flag : String) -> Bool {
  for i = 0; i < argv.length(); i = i + 1 {
    if argv[i] == flag {
      return true
    }
  }
  false
}

///|
/// Finds an integer option value.
fn find_int_option(
  argv : Array[String],
  short : String,
  long : String,
  default : Int,
) -> Int {
  for i = 0; i < argv.length(); i = i + 1 {
    let arg = argv[i]
    if (arg == short || arg == long) && i + 1 < argv.length() {
      match parse_int(argv[i + 1]) {
        Some(v) => return v
        None => return default
      }
    }
  }
  default
}

///|
/// Finds an optional integer option value.
fn find_maybe_int_option(
  argv : Array[String],
  short : String,
  long : String,
) -> Int? {
  for i = 0; i < argv.length(); i = i + 1 {
    let arg = argv[i]
    if (arg == short || arg == long) && i + 1 < argv.length() {
      return parse_int(argv[i + 1])
    }
  }
  None
}

///|
/// Gets command-line arguments from system.
fn get_argv() -> Array[String] {
  let raw = @sys.get_cli_args()
  // raw[0] is program name, skip it
  if raw.length() <= 1 {
    return []
  }
  let result = []
  for i = 1; i < raw.length(); i = i + 1 {
    result.push(raw[i])
  }
  result
}

///|
/// Checks if a string starts with a given prefix.
fn string_starts_with(s : String, prefix : String) -> Bool {
  let s_len = s.length()
  let p_len = prefix.length()
  guard s_len >= p_len else { false }
  for i = 0; i < p_len; i = i + 1 {
    if s.get_char(i).unwrap() != prefix.get_char(i).unwrap() {
      return false
    }
  }
  true
}

///|
/// Parses a string to an integer.
fn parse_int(s : String) -> Int? {
  let len = s.length()
  guard len > 0 else { None }

  let mut i = 0
  let mut sign = 1

  let first_char = s.get_char(0).unwrap()
  if first_char == '-' {
    sign = -1
    i = 1
  } else if first_char == '+' {
    i = 1
  }

  // Handle hex prefix
  if i + 1 < len &&
    s.get_char(i).unwrap() == '0' &&
    (s.get_char(i + 1).unwrap() == 'x' || s.get_char(i + 1).unwrap() == 'X') {
    return parse_hex(s, i + 2, sign)
  }

  let mut result = 0
  for j = i; j < len; j = j + 1 {
    let ch = s.get_char(j).unwrap()
    let digit = ch.to_int() - '0'.to_int()
    if digit < 0 || digit > 9 {
      return None
    }
    result = result * 10 + digit
  }

  Some(result * sign)
}

///|
/// Parses hex digits from a string.
fn parse_hex(s : String, start : Int, sign : Int) -> Int? {
  let len = s.length()
  let mut result = 0
  for i = start; i < len; i = i + 1 {
    let ch = s.get_char(i).unwrap()
    let code = ch.to_int()
    let digit = if code >= '0'.to_int() && code <= '9'.to_int() {
      code - '0'.to_int()
    } else if code >= 'A'.to_int() && code <= 'F'.to_int() {
      code - 'A'.to_int() + 10
    } else if code >= 'a'.to_int() && code <= 'f'.to_int() {
      code - 'a'.to_int() + 10
    } else {
      return None
    }
    result = result * 16 + digit
  }
  Some(result * sign)
}

///|
/// Displays help information.
fn cmd_help() -> Unit {
  println("Hex Editor — A command-line hex editor for binary files")
  println("")
  println("USAGE:")
  println("  moon run cmd/main -- <command> [options] [file]")
  println("")
  println("COMMANDS:")
  println("  view <file>       Display hex dump of a file")
  println("  info <file>       Show file information (size, type)")
  println("  search <file> <pattern>")
  println("                    Search for a hex pattern in a file")
  println("  help              Show this help message")
  println("")
  println("OPTIONS:")
  println("  -o, --offset N    Start at byte offset N (default: 0)")
  println("  -n, --length N    Display N bytes (default: all)")
  println("  -b, --bytes-per-row N")
  println("                    Bytes per row in hex dump (default: 16)")
  println("  --no-ascii        Hide the ASCII/character column")
  println("  --lowercase       Use lowercase hex digits (a-f)")
  println("")
  println("EXAMPLES:")
  println("  moon run cmd/main -- view myfile.bin")
  println("  moon run cmd/main -- view myfile.bin -o 0x100 -n 256")
  println("  moon run cmd/main -- view myfile.bin -b 8 --lowercase")
  println("  moon run cmd/main -- info myfile.bin")
  println("  moon run cmd/main -- search myfile.bin \"FF FE\"")
  println("  moon run cmd/main -- search myfile.bin 0xFF00AB")
}

///|
/// View command: display hex dump of a file.
fn cmd_view(args : Args) -> Unit {
  let file_path = match args.file_path {
    None => {
      println("Error: No file specified for view command")
      println("Usage: moon run cmd/main -- view <file> [options]")
      return
    }
    Some(p) => p
  }

  let load_result = load_file(file_path)
  match load_result {
    Err(msg) => {
      println("Error loading file: \{msg}")
      return
    }
    Ok(_) => ()
  }

  let buffer = load_result.unwrap()

  println(@lib.format_buffer_info(buffer))
  println("")

  // Configure view
  let config = build_view_config(args.bytes_per_row, args.show_ascii, args.uppercase_hex)

  // Calculate display length
  let total_len = buffer.length()
  let display_len = match args.length {
    None => total_len - args.offset
    Some(l) => {
      let max_len = total_len - args.offset
      if l < max_len { l } else { max_len }
    }
  }

  guard display_len > 0 else {
    println("(No data to display at offset \{args.offset})")
    return
  }

  let dump = @lib.format_hex_dump(
    buffer,
    start_offset=args.offset,
    length=display_len,
    config=config,
  )
  println(dump)

  let end_offset = args.offset + display_len
  if end_offset < total_len {
    println("... (\{total_len - end_offset} more bytes)")
  }
}

///|
/// Info command: display file information.
fn cmd_info(args : Args) -> Unit {
  let file_path = match args.file_path {
    None => {
      println("Error: No file specified")
      println("Usage: moon run cmd/main -- info <file>")
      return
    }
    Some(p) => p
  }

  if !@fs.path_exists(file_path) {
    println("Error: File not found: \{file_path}")
    return
  }

  let load_result = load_file(file_path)
  match load_result {
    Err(msg) => {
      println("Error loading file: \{msg}")
      return
    }
    Ok(_) => ()
  }

  let buffer = load_result.unwrap()
  let len = buffer.length()

  println("File Information")
  println("================")
  println("Path:     \{file_path}")
  println("Size:     \{len} bytes (\{@lib.format_size(len)})")

  if len >= 2 {
    let b0 = buffer.get_byte(0).unwrap()
    let b1 = buffer.get_byte(1).unwrap()
    let magic = b0.to_int() * 256 + b1.to_int()
    let file_type = detect_file_type(magic, len)
    match file_type {
      Some(t) => println("Type:     \{t}")
      None => println(
        "Type:     Unknown (magic: \{@lib.format_byte_hex(b0)}\{@lib.format_byte_hex(b1)})",
      )
    }
  }

  if len > 0 {
    let preview_len = if len < 16 { len } else { 16 }
    let sb = StringBuilder()
    for i = 0; i < preview_len; i = i + 1 {
      sb.write_string(@lib.format_byte_hex(buffer.get_byte(i).unwrap(), uppercase=true))
      sb.write_char(' ')
    }
    println("First \{preview_len} bytes: \{sb.to_string()}")
  }

  if len > 0 {
    println("")
    println("Hex Dump (first 256 bytes):")
    let dump_len = if len < 256 { len } else { 256 }
    let config = @lib.HexViewConfig::default()
    let dump = @lib.format_hex_dump(buffer, start_offset=0, length=dump_len, config=config)
    println(dump)
  }
}

///|
/// Detects file type from magic bytes.
fn detect_file_type(magic : Int, size : Int) -> String? {
  match magic {
    0x4D5A => Some("Windows PE executable (.exe/.dll)")
    0x5A4D => Some("Windows PE executable (.exe/.dll)")
    0xCAFE => Some("Java class file")
    0xFEFF => Some("UTF-16 BE BOM")
    0xFFFE => Some("UTF-16 LE BOM")
    0xFFD8 => Some("JPEG image")
    0x8950 => Some("PNG image")
    0x4749 => Some("GIF image")
    0x424D => Some("BMP image")
    0x504B => Some("ZIP archive / Office document")
    0x1F8B => Some("GZip compressed")
    0x425A => Some("BZip2 compressed")
    0x2550 => Some("PDF document")
    0xD0CF => Some("MS Office document (OLE2)")
    0x4949 => Some("TIFF image (little-endian)")
    0x4D4D => Some("TIFF image (big-endian)")
    0x0000 => Some("Binary data (likely)")
    _ => {
      let first_byte = magic >> 8
      if first_byte == 0x7F && size >= 4 {
        Some("ELF executable (Linux)")
      } else {
        None
      }
    }
  }
}

///|
/// Search command: search for a pattern in a file.
fn cmd_search(args : Args) -> Unit {
  let file_path = match args.file_path {
    None => {
      println("Error: No file specified for search command")
      println("Usage: moon run cmd/main -- search <file> <pattern>")
      return
    }
    Some(p) => p
  }

  let pattern_str = match args.pattern {
    None => {
      println("Error: No search pattern specified")
      println("Usage: moon run cmd/main -- search <file> <pattern>")
      println("Pattern can be hex (FF FE, 0xFF00AB, ff:00:ab) or ASCII text")
      return
    }
    Some(p) => p
  }

  let load_result = load_file(file_path)
  match load_result {
    Err(msg) => {
      println("Error loading file: \{msg}")
      return
    }
    Ok(_) => ()
  }

  let buffer = load_result.unwrap()
  let data = buffer.to_bytes()

  let hex_parsed = @lib.parse_hex_string(pattern_str)
  let (pattern, _search_type) = match hex_parsed {
    Some(bytes) => {
      println("Searching for hex pattern: \{pattern_str} (\{bytes.length()} bytes)")
      (bytes, "hex")
    }
    None => {
      println("Searching for text: \"\{pattern_str}\"")
      (ascii_to_bytes(pattern_str), "text")
    }
  }

  if pattern.is_empty() {
    println("Error: Invalid or empty search pattern")
    return
  }

  let results = @lib.find_all_bytes(data, pattern)
  let count = results.length()

  if count == 0 {
    println("Pattern not found.")
    return
  }

  println("Found \{count} occurrence(s):")
  println("")

  let max_show = if count < 20 { count } else { 20 }
  let config = @lib.HexViewConfig::default()

  for idx = 0; idx < max_show; idx = idx + 1 {
    let offset = results[idx]
    let row_start = (offset / 16) * 16
    let context_start = if row_start >= 16 { row_start - 16 } else { 0 }
    let context_len = if row_start >= 16 { 48 } else { 32 }

    println("Match #\{idx + 1} at offset 0x\{@lib.to_hex_string(offset, width=8)}:")
    let dump = @lib.format_hex_dump(
      buffer,
      start_offset=context_start,
      length=context_len,
      config=config,
    )
    println(dump)
    println("")
  }

  if count > max_show {
    println("... and \{count - max_show} more matches")
  }
}

///|
/// Converts a string to ASCII bytes.
fn ascii_to_bytes(text : String) -> Bytes {
  let len = text.length()
  Bytes::makei(len, i => {
    let ch = text.get_char(i).unwrap()
    let code = ch.to_int()
    if code >= 0 && code <= 127 {
      code.to_byte()
    } else {
      b'?'
    }
  })
}

///|
/// Builds a HexViewConfig with the specified options.
fn build_view_config(
  bytes_per_row : Int,
  show_ascii : Bool,
  uppercase_hex : Bool,
) -> @lib.HexViewConfig {
  @lib.HexViewConfig::default()
    .with_bytes_per_row(bytes_per_row)
    .with_ascii(show_ascii)
    .with_uppercase(uppercase_hex)
}

///|
/// Loads a file into a HexBuffer.
fn load_file(path : String) -> Result[@lib.HexBuffer, String] {
  if !@fs.path_exists(path) {
    return Err("File not found: \{path}")
  }
  try {
    let buf = @lib.HexBuffer::from_file(path)
    Ok(buf)
  } catch {
    @fs.IOError::IOError(msg) => Err("IO error: \{msg}")
    _ => Err("Unknown error loading file")
  }
}
