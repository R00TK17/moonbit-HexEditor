///|
/// Hex Editor — CLI + TUI Entry Point (Native Target)
/// Shared helpers in helpers.mbt, TUI in tui.mbt + tui_draw.mbt + tui_edit.mbt

fn main {
  let argv = get_argv()
  if argv.length() == 0 {
    run_tui(None)
    return
  }

  let cmd = argv[0]
  match cmd {
    "view" => cmd_view(argv)
    "info" => cmd_info(argv)
    "search" => cmd_search(argv)
    "struct" => cmd_struct(argv)
    "strings" => cmd_strings(argv)
    "entropy" => cmd_entropy(argv)
    "scan" => cmd_scan(argv)
    "base64" => cmd_base64(argv)
    "unbase64" => cmd_unbase64(argv)
    "encode" => cmd_encode(argv)
    "decode" => cmd_decode(argv)
    "help" => cmd_help()
    "interactive" | "tui" => run_tui(find_file_arg(argv, cmd))
    _ => {
      if cmd.contains(".") || cmd.contains("/") || cmd.contains("\\") {
        run_tui(Some(cmd))
      } else {
        run_tui(None)
      }
    }
  }
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
      if bpr != 8 && bpr != 16 { println("Error: -b supports 8 or 16 only"); return }
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

///|
/// Search command: -x hex, -a text, default auto-detect.
fn cmd_search(argv : Array[String]) -> Unit {
  let path = match find_file_arg(argv, "search") {
    Some(p) => p
    None => { println("Usage: search [-x|-a] <file> <pattern>"); return }
  }
  let pattern_str = match find_second_arg(argv, "search") {
    Some(p) => p
    None => { println("Usage: search [-x|-a] <file> <pattern>"); return }
  }
  let force_hex = has_flag(argv, "-x") || has_flag(argv, "--hex")
  let force_text = has_flag(argv, "-a") || has_flag(argv, "--text")
  match load_file(path) {
    Err(m) => { println("Error: \{m}"); return }
    Ok(buf) => {
      let data = buf.to_bytes()
      let (label, results, lens) = if force_text {
        match @lib.find_text_pattern(data, pattern_str) {
          Some((r, l)) => ("Text: \"" + pattern_str + "\"", r, l)
          None => { println("Invalid text pattern"); return }
        }
      } else if force_hex {
        match @lib.find_hex_pattern(data, pattern_str) {
          Some((r, l)) => ("Hex: " + pattern_str, r, l)
          None => { println("Invalid hex pattern"); return }
        }
      } else {
        match @lib.find_hex_pattern(data, pattern_str) {
          Some((r, l)) => ("Hex: " + pattern_str, r, l)
          None => match @lib.find_text_pattern(data, pattern_str) {
            Some((r, l)) => ("Text: \"" + pattern_str + "\"", r, l)
            None => { println("Invalid pattern"); return }
          }
        }
      }
      println(label)
      let count = results.length()
      if count == 0 { println("Not found."); return }
      println("Found \{count} match(es):")
      let show = if count < 10 { count } else { 10 }
      for idx = 0; idx < show; idx = idx + 1 {
        let off = results[idx]
        let mlen = if idx < lens.length() { lens[idx] } else { 1 }
        let ctx = if off >= 16 { ((off - 16) / 16) * 16 } else { 0 }
        let clen = ((off + mlen - ctx + 15) / 16 + 1) * 16
        println("  #\{idx + 1} @ 0x" + @lib.to_hex_string(off, width=8))
        hl_print_hex(buf, ctx, clen, off, mlen)
      }
      if count > show { println("  ... +\{count - show} more") }
    }
  }
}

///|
/// Struct command: parse and display file structure.
fn cmd_struct(argv : Array[String]) -> Unit {
  let file_path = match find_file_arg(argv, "struct") {
    Some(p) => p
    None => { println("Usage: struct <file>"); return }
  }
  let result = load_file(file_path)
  match result {
    Err(m) => { println("Error: \{m}"); return }
    Ok(buf) => {
      let bytes = buf.to_bytes()
      let fields = @lib.parse_structure(bytes)
      if fields.length() == 0 {
        println("No known structure detected.")
      } else {
        println("File: \{file_path} (\{@lib.format_size(buf.length())})")
        println("")
        println(@lib.format_structure(fields))
      }
    }
  }
}

///|
/// Strings command.
fn cmd_strings(argv : Array[String]) -> Unit {
  let path = match find_file_arg(argv, "strings") {
    Some(p) => p
    None => { println("Usage: strings <file>"); return }
  }
  match load_file(path) {
    Err(m) => { println("Error: \{m}"); return }
    Ok(buf) => {
      let matches = @lib.find_strings(buf.to_bytes())
      for i = 0; i < matches.length(); i = i + 1 {
        println("0x" + @lib.to_hex_string(matches[i].offset, width=8) + "  " + matches[i].text)
      }
      println("\{matches.length()} strings found")
    }
  }
}

///|
/// Entropy command.
fn cmd_entropy(argv : Array[String]) -> Unit {
  let path = match find_file_arg(argv, "entropy") {
    Some(p) => p
    None => { println("Usage: entropy <file>"); return }
  }
  match load_file(path) {
    Err(m) => { println("Error: \{m}"); return }
    Ok(buf) => {
      let blocks = @lib.entropy_scan(buf.to_bytes())
      for i = 0; i < blocks.length(); i = i + 1 {
        let b = blocks[i]
        let n = ((b.entropy / 8.0) * 40.0).to_int()
        let c = if n > 40 { 40 } else { n }
        let bar = StringBuilder()
        for j = 0; j < c; j = j + 1 { bar.write_char('|') }
        let ev = (b.entropy * 10.0).to_int()
        let es = (ev / 10).to_string() + "." + (ev % 10).to_string()
        println("0x" + @lib.to_hex_string(b.start, width=8) + "  " + bar.to_string() + "  " + es)
      }
    }
  }
}

///|
/// Scan command.
fn cmd_scan(argv : Array[String]) -> Unit {
  let path = match find_file_arg(argv, "scan") {
    Some(p) => p
    None => { println("Usage: scan <file>"); return }
  }
  match load_file(path) {
    Err(m) => { println("Error: \{m}"); return }
    Ok(buf) => {
      let matches = @lib.scan_signatures(buf.to_bytes())
      for i = 0; i < matches.length(); i = i + 1 {
        let m = matches[i]
        println("0x" + @lib.to_hex_string(m.offset, width=8) + "  " + m.name + " (" + @lib.format_size(m.size) + ")")
      }
      println("\{matches.length()} signatures found")
    }
  }
}

fn hl_print_hex(buf : @lib.HexBuffer, ctx : Int, clen : Int, match_off : Int, match_len : Int) -> Unit {
  let stop = if ctx + clen > buf.length() { buf.length() } else { ctx + clen }
  let mut row_off = (ctx / 16) * 16
  while row_off < stop {
    let out = StringBuilder()
    out.write_string("0x" + @lib.to_hex_string(row_off, width=8) + "  ")
    for col = 0; col < 16; col = col + 1 {
      if col == 8 { out.write_char(' ') }
      let bo = row_off + col
      if bo >= ctx && bo < stop {
        let in_match = bo >= match_off && bo < match_off + match_len
        if in_match { out.write_string("\u001b[42;30m") }
        let b = match buf.get_byte(bo) { Some(x) => x; None => b'\x00' }
        out.write_string(@lib.format_byte_hex(b, uppercase=true))
        if in_match { out.write_string("\u001b[0m") }
        out.write_char(' ')
      } else { out.write_string("   ") }
    }
    out.write_string(" |")
    for col = 0; col < 16; col = col + 1 {
      let bo = row_off + col
      if bo >= ctx && bo < stop {
        let in_match = bo >= match_off && bo < match_off + match_len
        if in_match { out.write_string("\u001b[42;30m") }
        let b = match buf.get_byte(bo) { Some(x) => x; None => b'\x00' }
        let ch = @lib.format_ascii(b)
        let cs = StringBuilder(); cs.write_char(ch); out.write_string(cs.to_string())
        if in_match { out.write_string("\u001b[0m") }
      } else { out.write_char(' ') }
    }
    out.write_string("|")
    println(out.to_string())
    row_off = row_off + 16
  }
}

///|
/// Base64 encode file.
fn cmd_base64(argv : Array[String]) -> Unit {
  let path = match find_file_arg(argv, "base64") { Some(p) => p; None => { println("Usage: base64 <file>"); return } }
  match load_file(path) {
    Err(m) => { println("Error: \{m}"); return }
    Ok(buf) => { println(@lib.base64_encode(buf.to_bytes())) }
  }
}

///|
/// Base64 decode file/string.
fn cmd_unbase64(argv : Array[String]) -> Unit {
  let path = match find_file_arg(argv, "unbase64") { Some(p) => p; None => { println("Usage: unbase64 <file>"); return } }
  match load_file(path) {
    Err(m) => { println("Error: \{m}"); return }
    Ok(buf) => {
      let text = buf.to_bytes()
      let sb = StringBuilder()
      for i = 0; i < text.length(); i = i + 1 {
        let b = text[i].to_int()
        if b != 0x0A && b != 0x0D { match b.to_char() { Some(c) => sb.write_char(c); None => () } }
      }
      match @lib.base64_decode(sb.to_string()) {
        Some(decoded) => {
          try { @fs.write_bytes_to_file(path + ".decoded", decoded); println("Saved: " + path + ".decoded") }
          catch { @fs.IOError::IOError(_) => println("Write error") }
        }
        None => println("Invalid Base64")
      }
    }
  }
}

///|
/// Unified encode command: encode <type> <file|string>
fn cmd_encode(argv : Array[String]) -> Unit {
  let enc_type = match find_file_arg(argv, "encode") {
    Some(t) => t
    None => { println("Usage: encode <base64|url|unicode|hex> <file|string>"); return }
  }
  let input = match find_second_arg(argv, "encode") {
    Some(p) => p
    None => { println("Usage: encode <base64|url|unicode|hex> <file|string>"); return }
  }
  let data = if @fs.path_exists(input) {
    match load_file(input) {
      Err(m) => { println("Error: \{m}"); return }
      Ok(buf) => buf.to_bytes()
    }
  } else {
    ascii_to_bytes(input)
  }
  let result = match enc_type {
    "base64" => @lib.base64_encode(data)
    "url" => @lib.url_encode(data)
    "unicode" => @lib.unicode_encode(data)
    "hex" => @lib.hex_encode(data)
    _ => { println("Unknown type: \{enc_type}. Supported: base64, url, unicode, hex"); return }
  }
  println(result)
}

///|
/// Unified decode command: decode <type> <file|string>
fn cmd_decode(argv : Array[String]) -> Unit {
  let dec_type = match find_file_arg(argv, "decode") {
    Some(t) => t
    None => { println("Usage: decode <base64|url|unicode|hex> <file|string>"); return }
  }
  let input = match find_second_arg(argv, "decode") {
    Some(p) => p
    None => { println("Usage: decode <base64|url|unicode|hex> <file|string>"); return }
  }
  let is_file = @fs.path_exists(input)
  let text = if is_file {
    match load_file(input) {
      Err(m) => { println("Error: \{m}"); return }
      Ok(buf) => {
        let raw = buf.to_bytes()
        let sb = StringBuilder()
        for i = 0; i < raw.length(); i = i + 1 {
          let b = raw[i].to_int()
          if b != 0x0A && b != 0x0D {
            match b.to_char() { Some(c) => sb.write_char(c); None => () }
          }
        }
        sb.to_string()
      }
    }
  } else {
    input
  }
  let decoded : Bytes? = match dec_type {
    "base64" => @lib.base64_decode(text)
    "url" => @lib.url_decode(text)
    "unicode" => @lib.unicode_decode(text)
    "hex" => @lib.hex_decode(text)
    _ => { println("Unknown type: \{dec_type}. Supported: base64, url, unicode, hex"); return }
  }
  match decoded {
    Some(bytes) => {
      if is_file {
        try { @fs.write_bytes_to_file(input + ".decoded", bytes); println("Saved: " + input + ".decoded (\{bytes.length()} bytes)") }
        catch { @fs.IOError::IOError(_) => println("Write error") }
      } else {
        let sb = StringBuilder()
        for i = 0; i < bytes.length(); i = i + 1 {
          let b = bytes[i].to_int()
          if b >= 0x20 && b <= 0x7E {
            sb.write_char(b.to_char().unwrap())
          } else {
            sb.write_string("\\x")
            sb.write_string(@lib.format_byte_hex(bytes[i], uppercase=true))
          }
        }
        println(sb.to_string())
      }
    }
    None => println("Invalid \{dec_type} input")
  }
}

///|
/// Help.
fn cmd_help() -> Unit {
  println("Hex Editor — TUI & CLI")
  println("")
  println("  moon run --target native cmd/main              Start TUI mode")
  println("  moon run --target native cmd/main -- <file>    Open file in TUI")
  println("  moon run --target native cmd/main -- view <f>  Quick hex dump")
  println("  moon run --target native cmd/main -- info <f>  File info")
  println("  moon run --target native cmd/main -- search <f> <p>  Search")
  println("")
  println("Codec Commands:")
  println("  encode <type> <file>   Encode file (base64/url/unicode/ascii)")
  println("  decode <type> <file>   Decode file (base64/url/unicode/ascii)")
  println("  base64 <file>          Shorthand: encode base64")
  println("  unbase64 <file>        Shorthand: decode base64")
  println("")
  println("TUI Keys:")
  println("  UD/arrows   Scroll       g     Goto offset")
  println("  LR          Page U/D     /     Hex search")
  println("  f           Text search  n/N   Next/prev match")
  println("  e           Edit mode    Esc   Exit edit")
  println("  q           Quit")
}
