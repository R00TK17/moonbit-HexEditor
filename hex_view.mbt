// Hex Editor — Display Formatting
// Renders binary data in the classic hex dump format.

///|
/// Configuration for hex dump display formatting.
struct HexViewConfig {
  bytes_per_row : Int     // bytes per row (default 16)
  show_ascii : Bool       // show ASCII column
  uppercase_hex : Bool    // use uppercase hex digits
  show_offset : Bool      // show offset column
  offset_width : Int      // width of offset column in hex digits
  group_bytes : Int       // bytes per group for spacing (0 = no grouping)
}

///|
/// Creates a default HexViewConfig.
pub fn HexViewConfig::default() -> HexViewConfig {
  {
    bytes_per_row: 16,
    show_ascii: true,
    uppercase_hex: true,
    show_offset: true,
    offset_width: 8,
    group_bytes: 8,
  }
}

///|
/// Creates a compact HexViewConfig (no ASCII, no grouping).
pub fn HexViewConfig::compact() -> HexViewConfig {
  {
    bytes_per_row: 16,
    show_ascii: false,
    uppercase_hex: true,
    show_offset: true,
    offset_width: 8,
    group_bytes: 0,
  }
}

///|
/// Creates a HexViewConfig with custom bytes per row.
pub fn HexViewConfig::with_bytes_per_row(
  self : HexViewConfig,
  bpr : Int,
) -> HexViewConfig {
  { ..self, bytes_per_row: bpr }
}

///|
/// Creates a HexViewConfig with custom show_ascii setting.
pub fn HexViewConfig::with_ascii(
  self : HexViewConfig,
  show : Bool,
) -> HexViewConfig {
  { ..self, show_ascii: show }
}

///|
/// Creates a HexViewConfig with custom uppercase_hex setting.
pub fn HexViewConfig::with_uppercase(
  self : HexViewConfig,
  upper : Bool,
) -> HexViewConfig {
  { ..self, uppercase_hex: upper }
}

///|
/// Creates a HexViewConfig with custom group_bytes setting.
pub fn HexViewConfig::with_group_bytes(
  self : HexViewConfig,
  group : Int,
) -> HexViewConfig {
  { ..self, group_bytes: group }
}

///|
/// Converts a nibble (4-bit value) to a hex character.
fn nibble_to_char(n : Int, uppercase : Bool) -> Char {
  match n {
    0 => '0'
    1 => '1'
    2 => '2'
    3 => '3'
    4 => '4'
    5 => '5'
    6 => '6'
    7 => '7'
    8 => '8'
    9 => '9'
    10 => if uppercase { 'A' } else { 'a' }
    11 => if uppercase { 'B' } else { 'b' }
    12 => if uppercase { 'C' } else { 'c' }
    13 => if uppercase { 'D' } else { 'd' }
    14 => if uppercase { 'E' } else { 'e' }
    15 => if uppercase { 'F' } else { 'f' }
    _ => '?'
  }
}

///|
/// Converts a byte to a 2-character hex string.
pub fn format_byte_hex(byte : Byte, uppercase? : Bool = true) -> String {
  let i = byte.to_int()
  let hi = nibble_to_char((i >> 4) & 0xF, uppercase)
  let lo = nibble_to_char(i & 0xF, uppercase)
  "\{hi}\{lo}"
}

///|
/// Formats an integer offset as a hex address string.
pub fn format_offset(
  offset : Int,
  width? : Int = 8,
  uppercase? : Bool = true,
) -> String {
  let w = width
  // Build hex digits from right to left in an array
  let chars = FixedArray::make(w, '0')
  let mut n_val = offset
  for i = w - 1; i >= 0; i = i - 1 {
    let d = n_val & 0xF
    n_val = n_val >> 4
    chars[i] = nibble_to_char(d, uppercase)
  }
  // Build result string
  let sb = StringBuilder()
  for i = 0; i < w; i = i + 1 {
    sb.write_char(chars[i])
  }
  sb.to_string()
}

///|
/// Converts a byte to its ASCII representation for the text column.
/// Printable ASCII characters (0x20-0x7E) are shown as-is.
/// Non-printable bytes are shown as '.'.
pub fn format_ascii(byte : Byte) -> Char {
  let i = byte.to_int()
  if i >= 0x20 && i <= 0x7E {
    match i.to_char() {
      Some(ch) => ch
      None => '.'
    }
  } else {
    '.'
  }
}

///|
/// Formats a single row of a hex dump.
pub fn format_hex_row(
  data : FixedArray[Byte],
  start : Int,
  length : Int,
  base_offset : Int,
  config : HexViewConfig,
) -> String {
  let sb = StringBuilder()

  // Offset column
  if config.show_offset {
    sb.write_string(format_offset(base_offset, width=config.offset_width, uppercase=config.uppercase_hex))
    sb.write_string("  ")
  }

  // Hex bytes
  for i = 0; i < length; i = i + 1 {
    if config.group_bytes > 0 && i > 0 && i % config.group_bytes == 0 {
      sb.write_char(' ')
    }
    sb.write_string(format_byte_hex(data[start + i], uppercase=config.uppercase_hex))
    sb.write_char(' ')
  }

  // Pad missing hex positions if row is shorter than bytes_per_row
  if length < config.bytes_per_row {
    let missing = config.bytes_per_row - length
    for j = 0; j < missing; j = j + 1 {
      sb.write_string("   ")
    }
    // Extra space for group boundary in the padding
    if config.group_bytes > 0 && length <= config.group_bytes && config.bytes_per_row > config.group_bytes {
      sb.write_char(' ')
    }
  }

  // ASCII column
  if config.show_ascii {
    sb.write_string(" |")
    for i = 0; i < length; i = i + 1 {
      sb.write_char(format_ascii(data[start + i]))
    }
    for j = length; j < config.bytes_per_row; j = j + 1 {
      sb.write_char(' ')
    }
    sb.write_char('|')
  }

  sb.to_string()
}

///|
/// Formats a complete hex dump from a HexBuffer.
pub fn format_hex_dump(
  buffer : HexBuffer,
  start_offset? : Int = 0,
  length? : Int,
  config? : HexViewConfig,
) -> String {
  let cfg = match config {
    Some(c) => c
    None => HexViewConfig::default()
  }
  let total_len = buffer.length()
  let start = start_offset
  let max_len = total_len - start
  let display_len = match length {
    None => max_len
    Some(l) => if l < max_len { l } else { max_len }
  }

  guard display_len > 0 else { return "" }

  let data = buffer.to_fixedarray()
  let sb = StringBuilder()

  let mut offset = 0
  for _i = 0; offset < display_len; _i = _i + 1 {
    let row_len = if offset + cfg.bytes_per_row <= display_len {
      cfg.bytes_per_row
    } else {
      display_len - offset
    }
    let row = format_hex_row(data, start + offset, row_len, start + offset, cfg)
    sb.write_string(row)
    sb.write_char('\n')
    offset = offset + cfg.bytes_per_row
  }

  sb.to_string()
}

///|
/// Formats a hex dump from raw Bytes data.
pub fn format_bytes_hex_dump(
  bytes : Bytes,
  start_offset? : Int = 0,
  length? : Int,
  config? : HexViewConfig,
) -> String {
  let buffer = HexBuffer::from_bytes(bytes)
  format_hex_dump(buffer, start_offset=start_offset, length?=length, config?=config)
}

///|
/// Returns a brief summary of a HexBuffer.
pub fn format_buffer_info(buffer : HexBuffer) -> String {
  let len = buffer.length()
  let size_str = format_size(len)
  let file_str = match buffer.get_file_path() {
    None => "<no file>"
    Some(p) => p
  }
  let modified_str = if buffer.is_modified() { " [modified]" } else { "" }
  "File: \{file_str}, Size: \{len} bytes (\{size_str})\{modified_str}"
}

///|
/// Formats a byte count in human-readable form.
pub fn format_size(len : Int) -> String {
  if len < 1024 {
    return "\{len} B"
  }
  if len < 1024 * 1024 {
    let kb = len.to_double() / 1024.0
    return "\{format_double(kb, 1)} KB"
  }
  if len < 1024 * 1024 * 1024 {
    let mb = len.to_double() / (1024.0 * 1024.0)
    return "\{format_double(mb, 1)} MB"
  }
  let gb = len.to_double() / (1024.0 * 1024.0 * 1024.0)
  "\{format_double(gb, 1)} GB"
}

///|
/// Formats a Double to a fixed number of decimal places.
fn format_double(value : Double, places : Int) -> String {
  let multiplier = ipow10(places).to_double()
  let scaled = value * multiplier
  let rounded = scaled.round().to_int()
  let int_part = rounded / ipow10(places)
  let frac_part = rounded % ipow10(places)
  if places <= 0 {
    return "\{int_part}"
  }
  let sb = StringBuilder()
  sb.write_string("\{int_part}.")
  // Format fractional part with leading zeros
  let mut remaining = frac_part
  let mut divisor = ipow10(places - 1)
  for _i = 0; _i < places; _i = _i + 1 {
    let digit = remaining / divisor
    sb.write_char(nibble_to_char(digit, false))
    remaining = remaining % divisor
    divisor = divisor / 10
    if divisor < 1 {
      break
    }
  }
  // Handle the case where divisor hits 0
  sb.to_string()
}

///|
/// Computes 10^n for non-negative n.
fn ipow10(n : Int) -> Int {
  let mut result = 1
  for _i = 0; _i < n; _i = _i + 1 {
    result = result * 10
  }
  result
}

///|
/// Converts a number to a fixed-width hex string (useful for UI).
pub fn to_hex_string(n : Int, width? : Int = 2) -> String {
  format_offset(n, width=width)
}
