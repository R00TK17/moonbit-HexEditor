///|
/// Minimal main for wasm-gc target — CLI only (no TUI)
/// For full TUI mode, use: moon build --target native

fn main {
  let argv = get_argv()
  if argv.length() == 0 {
    println("Hex Editor - CLI mode (wasm target)")
    println("Usage: moon run cmd/main -- <command> [options]")
    println("Commands: view, info, search, help")
    println("For TUI: moon run --target native cmd/main")
    return
  }

  let cmd = argv[0]
  match cmd {
    "view" => cmd_view(argv)
    "info" => cmd_info(argv)
    "search" => cmd_search(argv)
    "help" => cmd_help()
    _ => println("Try: view <file>, info <file>, search <file> <pattern>, help")
  }
}

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
      let ascii = !has_flag(argv, "--no-ascii")
      let upper = !has_flag(argv, "--lowercase")
      let len = buf.length()
      let display_len = if length < 0 || offset + length > len { len - offset } else { length }
      guard display_len > 0 else { return }
      println(@lib.format_buffer_info(buf))
      println("")
      let config = build_view_config(bpr, ascii, upper)
      println(@lib.format_hex_dump(buf, start_offset=offset, length=display_len, config=config))
      let remaining = len - offset - display_len
      if remaining > 0 { println("... (\{remaining} more bytes)") }
    }
  }
}

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

fn cmd_help() -> Unit {
  println("Hex Editor - CLI mode")
  println("  view <file> [-n N] [-o N]    Display hex dump")
  println("  info <file>                   File information")
  println("  search <file> <pattern>       Search")
  println("For TUI: moon run --target native cmd/main")
}
