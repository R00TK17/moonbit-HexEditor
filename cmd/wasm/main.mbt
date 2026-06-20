///|
/// MoonBit Hex Editor — Wasm CLI (lightweight, no TUI)
/// Provides core analysis functions without native terminal dependencies.

fn main {
  let all_args = @sys.get_cli_args()
  // Skip program name (args[0])
  let args : Array[String] = []
  for i = 1; i < all_args.length(); i = i + 1 { args.push(all_args[i]) }
  if args.length() == 0 { print_help(); return }
  let cmd = args[0]
  match cmd {
    "view" => cmd_view(args)
    "struct" => cmd_struct(args)
    "scan" => cmd_scan(args)
    "strings" => cmd_strings(args)
    "entropy" => cmd_entropy(args)
    "search" => cmd_search(args)
    "encode" => cmd_encode(args)
    "decode" => cmd_decode(args)
    "help" => print_help()
    _ => {
      if cmd.contains(".") || cmd.contains("/") || cmd.contains("\\") {
        cmd_view([cmd, cmd])
      } else { print_help() }
    }
  }
}

fn load(path : String) -> Bytes? {
  let mut data : Bytes = Bytes::new(0)
  try { data = @fs.read_file_to_bytes(path) } catch { _ => { println("Error: cannot read " + path); return None } }
  Some(data)
}

fn find_arg(args : Array[String], cmd : String) -> String? {
  for i = 0; i < args.length(); i = i + 1 {
    if args[i] != cmd && !args[i].contains("-") { return Some(args[i]) }
  }
  None
}

fn cmd_view(args : Array[String]) -> Unit {
  let path = match find_arg(args, "view") { Some(p) => p; None => { println("Usage: view <file>"); return } }
  let data = match load(path) { Some(d) => d; None => return }
  let buf = @lib.HexBuffer::from_bytes(data)
  println(@lib.format_buffer_info(buf))
  println("")
  let len = if buf.length() > 256 { 256 } else { buf.length() }
  println(@lib.format_hex_dump(buf, length=len))
  if buf.length() > 256 { println("... (\{buf.length() - 256} more bytes)") }
}

fn cmd_struct(args : Array[String]) -> Unit {
  let path = match find_arg(args, "struct") { Some(p) => p; None => { println("Usage: struct <file>"); return } }
  let data = match load(path) { Some(d) => d; None => return }
  let fields = @lib.parse_structure(data)
  if fields.length() == 0 { println("No known structure detected."); return }
  println("File: \{path} (\{@lib.format_size(data.length())})")
  println("")
  println(@lib.format_structure(fields))
}

fn cmd_scan(args : Array[String]) -> Unit {
  let path = match find_arg(args, "scan") { Some(p) => p; None => { println("Usage: scan <file>"); return } }
  let data = match load(path) { Some(d) => d; None => return }
  let matches = @lib.scan_signatures(data)
  for i = 0; i < matches.length(); i = i + 1 {
    let m = matches[i]
    println("0x\{@lib.to_hex_string(m.offset, width=8)}  \{m.name} (\{@lib.format_size(m.size)})")
  }
  println("\{matches.length()} signatures found")
}

fn cmd_strings(args : Array[String]) -> Unit {
  let path = match find_arg(args, "strings") { Some(p) => p; None => { println("Usage: strings <file>"); return } }
  let data = match load(path) { Some(d) => d; None => return }
  let matches = @lib.find_strings(data)
  for i = 0; i < matches.length(); i = i + 1 {
    println("0x\{@lib.to_hex_string(matches[i].offset, width=8)}  \{matches[i].text}")
  }
  println("\{matches.length()} strings found")
}

fn cmd_entropy(args : Array[String]) -> Unit {
  let path = match find_arg(args, "entropy") { Some(p) => p; None => { println("Usage: entropy <file>"); return } }
  let data = match load(path) { Some(d) => d; None => return }
  let blocks = @lib.entropy_scan(data)
  for i = 0; i < blocks.length(); i = i + 1 {
    let b = blocks[i]
    let ev = (b.entropy * 10.0).to_int()
    let es = (ev / 10).to_string() + "." + (ev % 10).to_string()
    println("0x\{@lib.to_hex_string(b.start, width=8)}  \{es}")
  }
}

fn cmd_search(args : Array[String]) -> Unit {
  let path = match find_arg(args, "search") { Some(p) => p; None => { println("Usage: search <file> <pattern>"); return } }
  let mut pattern = ""
  let mut found_file = false
  for i = 0; i < args.length(); i = i + 1 {
    if args[i] != "search" && !args[i].contains("-") {
      if !found_file { found_file = true }
      else { pattern = args[i]; break }
    }
  }
  if pattern == "" { println("Usage: search <file> <pattern>"); return }
  let data = match load(path) { Some(d) => d; None => return }
  match @lib.find_hex_pattern(data, pattern) {
    Some((offsets, _lens)) => {
      println("Found \{offsets.length()} match(es):")
      let show = if offsets.length() < 10 { offsets.length() } else { 10 }
      for i = 0; i < show; i = i + 1 {
        println("  #\{i + 1} @ 0x\{@lib.to_hex_string(offsets[i], width=8)}")
      }
      if offsets.length() > show { println("  ... +\{offsets.length() - show} more") }
    }
    None => match @lib.find_text_pattern(data, pattern) {
      Some((offsets, _lens)) => {
        println("Found \{offsets.length()} match(es):")
        let show = if offsets.length() < 10 { offsets.length() } else { 10 }
        for i = 0; i < show; i = i + 1 {
          println("  #\{i + 1} @ 0x\{@lib.to_hex_string(offsets[i], width=8)}")
        }
      }
      None => println("Invalid pattern")
    }
  }
}

fn cmd_encode(args : Array[String]) -> Unit {
  let enc_type = match find_arg(args, "encode") { Some(t) => t; None => { println("Usage: encode <base64|url|unicode|hex> <input>"); return } }
  let mut input = ""
  let mut found_type = false
  for i = 0; i < args.length(); i = i + 1 {
    if args[i] != "encode" && !args[i].contains("-") {
      if !found_type { found_type = true }
      else { input = args[i]; break }
    }
  }
  if input == "" { println("Usage: encode <base64|url|unicode|hex> <input>"); return }
  let data = Bytes::makei(input.length(), fn(i) {
    let c = input.get_char(i).unwrap().to_int()
    if c <= 127 { c.to_byte() } else { b'?' }
  })
  let result = match enc_type {
    "base64" => @lib.base64_encode(data)
    "url" => @lib.url_encode(data)
    "unicode" => @lib.unicode_encode(data)
    "hex" => @lib.hex_encode(data)
    _ => { println("Unknown type. Supported: base64, url, unicode, hex"); return }
  }
  println(result)
}

fn cmd_decode(args : Array[String]) -> Unit {
  let dec_type = match find_arg(args, "decode") { Some(t) => t; None => { println("Usage: decode <base64|url|unicode|hex> <input>"); return } }
  let mut input = ""
  let mut found_type = false
  for i = 0; i < args.length(); i = i + 1 {
    if args[i] != "decode" && !args[i].contains("-") {
      if !found_type { found_type = true }
      else { input = args[i]; break }
    }
  }
  if input == "" { println("Usage: decode <base64|url|unicode|hex> <input>"); return }
  let decoded : Bytes? = match dec_type {
    "base64" => @lib.base64_decode(input)
    "url" => @lib.url_decode(input)
    "unicode" => @lib.unicode_decode(input)
    "hex" => @lib.hex_decode(input)
    _ => { println("Unknown type. Supported: base64, url, unicode, hex"); return }
  }
  match decoded {
    Some(bytes) => {
      let sb = StringBuilder()
      for i = 0; i < bytes.length(); i = i + 1 {
        let b = bytes[i].to_int()
        if b >= 0x20 && b <= 0x7E { sb.write_char(b.to_char().unwrap()) }
        else { sb.write_char('.') }
      }
      println(sb.to_string())
    }
    None => println("Invalid input")
  }
}

fn print_help() -> Unit {
  println("MoonBit Hex Editor — Wasm CLI")
  println("")
  println("Commands:")
  println("  view <file>              Hex dump (first 256 bytes)")
  println("  struct <file>            Structure analysis")
  println("  scan <file>              Signature scan")
  println("  strings <file>           String extraction")
  println("  entropy <file>           Entropy analysis")
  println("  search <file> <pattern>  Search (hex: FF ?? 00 | text)")
  println("  encode <type> <input>    Encode (base64/url/unicode/hex)")
  println("  decode <type> <input>    Decode (base64/url/unicode/hex)")
  println("  help                     This help")
}
