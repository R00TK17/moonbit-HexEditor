// File Structure Parser — PE / ELF / JPEG / PNG header analysis

///|
/// A parsed field from a file structure.
struct StructField {
  offset : Int
  size : Int
  name : String
  value : String
  description : String
  children : Array[StructField]
} derive(Debug)

fn field(off : Int, sz : Int, name : String, val : String, desc : String) -> StructField {
  { offset: off, size: sz, name, value: val, description: desc, children: [] }
}

fn group(off : Int, sz : Int, name : String, desc : String, kids : Array[StructField]) -> StructField {
  { offset: off, size: sz, name, value: "", description: desc, children: kids }
}

///|
/// Parse structure of file bytes. Returns top-level fields or empty array.
pub fn parse_structure(bytes : Bytes) -> Array[StructField] {
  let len = bytes.length()
  guard len >= 4 else { return [] }
  let magic_le = read_u32_le(bytes, 0)
  let magic_be = read_u16_be(bytes, 0)
  if magic_be == 0xFFD8 { return parse_jpeg(bytes) }
  if magic_be == 0x8950 { return parse_png(bytes) }
  if magic_be == 0x4D5A || magic_be == 0x5A4D { return parse_pe(bytes) }
  if magic_le == 0x04034B50 { return parse_zip(bytes) }
  if len >= 6 && (read_str(bytes, 0, 6) == "GIF87a" || read_str(bytes, 0, 6) == "GIF89a") { return parse_gif(bytes) }
  if magic_be == 0x424D { return parse_bmp(bytes) }
  if len >= 7 && read_str(bytes, 0, 4) == "Rar!" { return parse_rar(bytes) }
  if len >= 512 && read_str(bytes, 257, 5) == "ustar" { return parse_tar(bytes) }
  if len >= 2 && is_zlib(bytes) { return parse_zlib(bytes) }
  // Audio/Video
  if len >= 12 && read_str(bytes, 0, 4) == "RIFF" && read_str(bytes, 8, 4) == "WAVE" { return parse_wav(bytes) }
  if len >= 12 && read_str(bytes, 0, 4) == "RIFF" && read_str(bytes, 8, 4) == "AVI " { return parse_avi(bytes) }
  if magic_be == 0x664C { return parse_flac(bytes) }  // "fL"
  if len >= 4 && read_str(bytes, 0, 4) == "OggS" { return parse_ogg(bytes) }
  if len >= 8 && read_str(bytes, 0, 3) == "ID3" { return parse_mp3(bytes) }
  if len >= 8 && (read_u32_be(bytes, 4) == 0x66747970) { return parse_mp4(bytes) }  // "ftyp"
  if read_u32_be(bytes, 0) == 0x1A45DFA3 { return parse_webm(bytes) }
  // ELF
  if len >= 4 && bytes[0] == b'\x7F' && bytes[1] == b'E' && bytes[2] == b'L' && bytes[3] == b'F' {
    return parse_elf(bytes)
  }
  return []
}

///|
/// Check if data starts with a valid ZLIB header.
fn is_zlib(bytes : Bytes) -> Bool {
  guard bytes.length() >= 2 else { return false }
  let cmf = bytes[0].to_int()
  let flg = bytes[1].to_int()
  let cm = cmf & 0x0F
  (cm == 8) && ((cmf * 256 + flg) % 31 == 0)
}

fn read_u16_be(bytes : Bytes, off : Int) -> Int {
  guard off + 2 <= bytes.length() else { 0 }
  bytes[off].to_int() * 256 + bytes[off + 1].to_int()
}

fn read_u32_be(bytes : Bytes, off : Int) -> Int {
  guard off + 4 <= bytes.length() else { 0 }
  let mut r = 0
  for i = 0; i < 4; i = i + 1 { r = r * 256 + bytes[off + i].to_int() }
  r
}

fn read_u16_le(bytes : Bytes, off : Int) -> Int {
  guard off + 2 <= bytes.length() else { 0 }
  bytes[off].to_int() + bytes[off + 1].to_int() * 256
}

fn read_u32_le(bytes : Bytes, off : Int) -> Int {
  guard off + 4 <= bytes.length() else { 0 }
  let mut r = 0
  for i = 3; i >= 0; i = i - 1 { r = r * 256 + bytes[off + i].to_int() }
  r
}

fn hex(n : Int, width : Int) -> String {
  format_offset(n, width=width)
}

fn read_str(bytes : Bytes, off : Int, max : Int) -> String {
  let result = StringBuilder()
  for i = 0; i < max; i = i + 1 {
    let b = bytes[off + i]
    if b == b'\x00' { break }
    if b.to_int() >= 32 && b.to_int() < 127 {
      let ch = b.to_int().to_char()
      match ch { Some(c) => result.write_char(c); None => () }
    }
  }
  result.to_string()
}

// ============== JPEG ==============

fn parse_jpeg(bytes : Bytes) -> Array[StructField] {
  let len = bytes.length()
  let fields = []
  fields.push(field(0, 2, "SOI", "FF D8", "Start of Image"))
  let mut pos = 2
  for iter = 0; pos + 2 < len && iter < 50; iter = iter + 1 {
    if bytes[pos].to_int() != 0xFF { break }
    let marker = bytes[pos + 1].to_int()
    if marker == 0xD9 {
      fields.push(field(pos, 2, "EOI", "FF D9", "End of Image"))
      break
    }
    if marker == 0xDA {
      let sl = read_u16_be(bytes, pos + 2)
      fields.push(field(pos, 2, "SOS", "FF DA", "Start of Scan"))
      let scan_start = pos + 2 + sl
      let mut scan_end = len
      for j = scan_start; j + 1 < len; j = j + 1 {
        if bytes[j].to_int() == 0xFF && bytes[j + 1].to_int() != 0x00 {
          scan_end = j
          break
        }
      }
      if scan_end > scan_start {
        fields.push(field(scan_start, scan_end - scan_start, "ScanData", "\{scan_end - scan_start} bytes", "Compressed image data"))
      }
      pos = scan_end
      continue
    }
    if marker >= 0xD0 && marker <= 0xD7 {
      let nm = match marker {
        0xD0 => "RST0"; 0xD1 => "RST1"; 0xD2 => "RST2"; 0xD3 => "RST3"
        0xD4 => "RST4"; 0xD5 => "RST5"; 0xD6 => "RST6"; 0xD7 => "RST7"
        _ => "RSTn"
      }
      fields.push(field(pos, 2, nm, "FF \{format_byte_hex(bytes[pos + 1])}", "Restart marker"))
      pos = pos + 2
      continue
    }
    if pos + 4 > len { break }
    let sl = read_u16_be(bytes, pos + 2)
    let nm = jpeg_marker_name(marker)
    // Extract dimensions for SOF markers
    let desc = if marker >= 0xC0 && marker <= 0xC2 && pos + 9 <= len {
      let h = read_u16_be(bytes, pos + 5)
      let w = read_u16_be(bytes, pos + 7)
      "\{nm}: \{w}x\{h} (0x\{hex(w, 4)} x 0x\{hex(h, 4)}), \{bytes[pos + 4].to_int()}bpp, \{sl} bytes"
    } else {
      "\{nm} segment, \{sl} bytes"
    }
    fields.push(field(pos, 2, nm, "FF \{format_byte_hex(bytes[pos + 1])}", desc))
    pos = pos + 2 + sl
  }
  // Fallback: check end of file for EOI if not found during scan
  if pos < len {
    if len >= 2 && bytes[len-2].to_int() == 0xFF && bytes[len-1].to_int() == 0xD9 {
      if pos < len - 2 { fields.push(field(pos, len - 2 - pos, "Trailing", "\{len - 2 - pos} bytes", "Remaining data")) }
      fields.push(field(len - 2, 2, "EOI", "FF D9", "End of Image"))
    } else {
      fields.push(field(pos, len - pos, "Trailing", "\{len - pos} bytes", "Remaining data"))
    }
  }
  fields
}

fn jpeg_marker_name(m : Int) -> String {
  match m {
    0xE0 => "APP0"; 0xE1 => "APP1"; 0xE2 => "APP2"; 0xE3 => "APP3"
    0xE4 => "APP4"; 0xE5 => "APP5"; 0xE6 => "APP6"; 0xE7 => "APP7"
    0xE8 => "APP8"; 0xE9 => "APP9"; 0xEA => "APP10"; 0xEB => "APP11"
    0xEC => "APP12"; 0xED => "APP13"; 0xEE => "APP14"; 0xEF => "APP15"
    0xDB => "DQT"; 0xC0 => "SOF0"; 0xC1 => "SOF1"; 0xC2 => "SOF2"
    0xC4 => "DHT"; 0xDD => "DRI"; 0xFE => "COM"
    _ => "UNK"
  }
}

// ============== PNG ==============

fn parse_png(bytes : Bytes) -> Array[StructField] {
  let len = bytes.length()
  let fields = []
  fields.push(field(0, 8, "Signature", "89 50 4E 47 0D 0A 1A 0A", "PNG signature"))
  let mut pos = 8
  for _i = 0; pos + 12 <= len && _i < 50; _i = _i + 1 {
    let dlen = read_u32_be(bytes, pos)
    let ctype = read_str(bytes, pos + 4, 4)
    let total = 12 + dlen
    let desc = match ctype {
      "IHDR" => {
        let w = read_u32_be(bytes, pos + 8)
        let h = read_u32_be(bytes, pos + 12)
        "Image Header: \{w}x\{h} (0x\{hex(w, 8)} x 0x\{hex(h, 8)}), \{bytes[pos + 16].to_int()}bpp"
      }
      "PLTE" => "Palette: \{dlen / 3} colors"
      "IDAT" => "Image data block"
      "IEND" => "Image end"
      "tEXt" => "Text metadata"
      "tIME" => "Last modification time"
      "pHYs" => "Physical dimensions"
      _ => "\{dlen} bytes"
    }
    fields.push(field(pos, total, ctype, "\{dlen} bytes", desc))
    if ctype == "IEND" { break }
    pos = pos + total
  }
  fields
}

// ============== PE ==============

fn parse_pe(bytes : Bytes) -> Array[StructField] {
  let len = bytes.length()
  guard len >= 64 else { return [field(0, len, "TRUNCATED", "", "Too small for PE")] }
  let fields = []
  let e_lfanew = read_u32_le(bytes, 60)
  fields.push(group(0, 64, "DOS Header", "MZ signature", [
    field(0, 2, "e_magic", "MZ", "DOS signature"),
    field(60, 4, "e_lfanew", "0x\{hex(e_lfanew, 8)}", "PE offset"),
  ]))

  let pe_off = e_lfanew
  if pe_off > 64 {
    fields.push(field(64, pe_off - 64, "DOS Stub", "\{pe_off - 64} bytes", "DOS stub program"))
  }
  guard pe_off + 4 <= len else { return fields }

  let sig = read_str(bytes, pe_off, 4)
  guard sig == "PE" else {
    fields.push(field(pe_off, 4, "PE Sig?", sig, "Expected PE"))
    return fields
  }
  fields.push(field(pe_off, 4, "Signature", "PE\\0\\0", "PE signature"))

  let coff = pe_off + 4
  guard coff + 20 <= len else { return fields }

  let machine = read_u16_le(bytes, coff)
  let nsections = read_u16_le(bytes, coff + 2)
  let sz_opt = read_u16_le(bytes, coff + 16)
  let mach_name = match machine {
    0x014C => "i386"; 0x8664 => "AMD64"; 0x01C4 => "ARM"; 0xAA64 => "ARM64"; _ => "0x\{hex(machine, 4)}"
  }

  fields.push(group(coff, 20, "COFF Header", "Machine: \{mach_name}, \{nsections} sections", [
    field(coff, 2, "Machine", mach_name, ""),
    field(coff + 2, 2, "NumSections", "\{nsections}", ""),
    field(coff + 4, 4, "Timestamp", "0x\{hex(read_u32_le(bytes, coff + 4), 8)}", ""),
    field(coff + 16, 2, "SizeOfOptional", "\{sz_opt}", ""),
  ]))

  let opt = coff + 20
  guard opt + sz_opt <= len else { return fields }
  if sz_opt >= 2 {
    let omagic = read_u16_le(bytes, opt)
    let pe_type = if omagic == 0x20B { "PE32+" } else if omagic == 0x10B { "PE32" } else { "?" }
    let ep = if sz_opt >= 20 { read_u32_le(bytes, opt + 16) } else { 0 }
    let ibase = if sz_opt >= 32 { read_u32_le(bytes, opt + 28) } else { 0 }
    let kids = [
      field(opt, 2, "Magic", pe_type, ""),
      field(opt + 16, 4, "EntryPoint", "0x\{hex(ep, 8)}", ""),
      field(opt + 28, 4, "ImageBase", "0x\{hex(ibase, 8)}", ""),
    ]
    fields.push(group(opt, sz_opt, "Optional Header", pe_type, kids))
  }

  let sec_start = opt + sz_opt
  for i = 0; i < nsections; i = i + 1 {
    let so = sec_start + i * 40
    if so + 40 > len { break }
    let sn = read_str(bytes, so, 8)
    let vs = read_u32_le(bytes, so + 8)
    let va = read_u32_le(bytes, so + 12)
    let rs = read_u32_le(bytes, so + 16)
    let ro = read_u32_le(bytes, so + 20)
    fields.push(group(so, 40, "Section: \{sn}", "VAddr=0x\{hex(va, 8)} RawSize=0x\{hex(rs, 8)}", [
      field(so, 8, "Name", sn, ""),
      field(so + 8, 4, "VirtualSize", "0x\{hex(vs, 8)}", ""),
      field(so + 12, 4, "VirtualAddress", "0x\{hex(va, 8)}", ""),
      field(so + 16, 4, "RawSize", "0x\{hex(rs, 8)}", ""),
      field(so + 20, 4, "RawOffset", "0x\{hex(ro, 8)}", ""),
    ]))
  }
  fields
}

// ============== ZIP ==============

fn parse_zip(bytes : Bytes) -> Array[StructField] {
  let len = bytes.length()
  let fields = []

  // Scan local file headers
  let mut pos = 0
  let mut file_count = 0
  for iter = 0; pos + 30 <= len && iter < 200; iter = iter + 1 {
    let sig = read_u32_le(bytes, pos)
    if sig == 0x04034B50 {
      file_count = file_count + 1
      let ver = read_u16_le(bytes, pos + 4)
      let flags = read_u16_le(bytes, pos + 6)
      let cmethod = read_u16_le(bytes, pos + 8)
      let crc = read_u32_le(bytes, pos + 14)
      let comp_size = read_u32_le(bytes, pos + 18)
      let uncomp_size = read_u32_le(bytes, pos + 22)
      let name_len = read_u16_le(bytes, pos + 26)
      let file_time = read_u16_le(bytes, pos + 10)
      let file_date = read_u16_le(bytes, pos + 12)
      let extra_len = read_u16_le(bytes, pos + 28)

      let cmethod_str = match cmethod {
        0 => "Stored"; 8 => "Deflated"; 12 => "BZip2"; 14 => "LZMA"
        _ => "Unknown(\{cmethod})"
      }
      let name = if name_len > 0 && pos + 30 + name_len <= len {
        read_str(bytes, pos + 30, name_len)
      } else { "" }
      let total = 30 + name_len + extra_len

      let mut desc = cmethod_str
      if comp_size > 0 && uncomp_size > 0 {
        desc = "\{desc}, \{comp_size} -> \{uncomp_size} bytes"
      }
      if name != "" { desc = "\{desc}: \{name}" }
      // Check encryption flag
      let encrypted = (flags & 1) != 0
      if encrypted {
        let pseudo = (crc == 0 && comp_size == 0 && uncomp_size == 0)
        desc = if pseudo { "\{desc} [Encrypted? - CRC/size in data descriptor]" }
               else { "\{desc} [Encrypted]" }
      }

      fields.push(group(pos, total, "LocalFile #\{file_count}", desc, [
        field(pos, 4, "Signature", "PK\\03\\04", ""),
        field(pos + 4, 2, "Version", "\{ver}", ""),
        field(pos + 6, 2, "Flags", "0x\{hex(flags, 4)}", if (flags & 1) != 0 { "Encrypted" } else if (flags & 8) != 0 { "DataDescriptor" } else { "" }),
        field(pos + 8, 2, "Method", cmethod_str, ""),
        field(pos + 10, 2, "FileTime", "0x" + hex(file_time, 4), ""),
        field(pos + 12, 2, "FileDate", "0x" + hex(file_date, 4), ""),
        field(pos + 14, 4, "CRC32", "0x\{hex(crc, 8)}", ""),
        field(pos + 18, 4, "CompressedSize", "\{comp_size}", ""),
        field(pos + 22, 4, "UncompressedSize", "\{uncomp_size}", ""),
        field(pos + 26, 2, "FileNameLen", "\{name_len}", ""),
        field(pos + 28, 2, "ExtraLen", "\{extra_len}", ""),
      ]))

      // File data follows
      let data_start = pos + total
      if comp_size > 0 && data_start + comp_size <= len {
        fields.push(field(data_start, comp_size, "FileData #\{file_count}", "\{comp_size} bytes", "Compressed data"))
        pos = data_start + comp_size
      } else {
        pos = pos + total
      }
    } else if sig == 0x02014B50 {
      // Central directory entry - stop scanning local files
      break
    } else if sig == 0x06054B50 {
      // EOCD
      let disk = read_u16_le(bytes, pos + 4)
      let cd_entries = read_u16_le(bytes, pos + 10)
      let cd_size = read_u32_le(bytes, pos + 12)
      let cd_offset = read_u32_le(bytes, pos + 16)
      let comment_len = read_u16_le(bytes, pos + 20)
      fields.push(group(pos, 22 + comment_len, "EOCD", "\{cd_entries} entries in central dir", [
        field(pos, 4, "Signature", "PK\\05\\06", ""),
        field(pos + 4, 2, "DiskNumber", "\{disk}", ""),
        field(pos + 10, 2, "CentralDirEntries", "\{cd_entries}", ""),
        field(pos + 12, 4, "CentralDirSize", "\{cd_size} bytes", ""),
        field(pos + 16, 4, "CentralDirOffset", "0x\{hex(cd_offset, 8)}", ""),
        field(pos + 20, 2, "CommentLen", "\{comment_len}", ""),
      ]))
      break
    } else {
      break
    }
  }

  if fields.length() == 0 {
    fields.push(field(0, len, "Unknown ZIP", "\{len} bytes", "ZIP signature not found"))
  }
  fields
}

// ============== GIF ==============

fn parse_gif(bytes : Bytes) -> Array[StructField] {
  let len = bytes.length()
  let fields = []
  let ver = read_str(bytes, 0, 6)
  fields.push(field(0, 6, "Signature", ver, "GIF signature"))

  let w = read_u16_le(bytes, 6)
  let h = read_u16_le(bytes, 8)
  let packed = bytes[10].to_int()
  let bg = bytes[11].to_int()
  let gct_size = 1 << ((packed & 7) + 1)
  let has_gct = (packed >> 7) & 1

  fields.push(group(6, 7, "Screen Descriptor", "\{w}x\{h} (0x\{hex(w, 4)} x 0x\{hex(h, 4)}), GCT=\{gct_size} colors", [
    field(6, 2, "Width", "\{w} (0x\{hex(w, 4)})", ""),
    field(8, 2, "Height", "\{h} (0x\{hex(h, 4)})", ""),
    field(10, 1, "Packed", "0x\{hex(packed, 2)}", "GCT=\{has_gct}, Size=\{gct_size}"),
    field(11, 1, "Background", "\{bg}", "Background color index"),
    field(12, 1, "Aspect", "\{bytes[12].to_int()}", "Pixel aspect ratio"),
  ]))

  let mut pos = 13
  if has_gct != 0 {
    let gct_bytes = gct_size * 3
    fields.push(field(pos, gct_bytes, "Global Color Table", "\{gct_size} colors x 3 bytes", ""))
    pos = pos + gct_bytes
  }

  let mut img_count = 0
  for iter = 0; pos < len && iter < 50; iter = iter + 1 {
    let b = bytes[pos].to_int()
    if b == 0x2C {
      img_count = img_count + 1
      let iw = read_u16_le(bytes, pos + 5)
      let ih = read_u16_le(bytes, pos + 7)
      fields.push(group(pos, 10, "Image #\{img_count}", "\{iw}x\{ih} at (\{read_u16_le(bytes, pos + 1)}, \{read_u16_le(bytes, pos + 3)})", [
        field(pos, 1, "Separator", "0x2C", "Image descriptor"),
        field(pos + 1, 2, "Left", "\{read_u16_le(bytes, pos + 1)}", ""),
        field(pos + 3, 2, "Top", "\{read_u16_le(bytes, pos + 3)}", ""),
        field(pos + 5, 2, "Width", "\{iw}", ""),
        field(pos + 7, 2, "Height", "\{ih}", ""),
        field(pos + 9, 1, "Packed", "0x\{hex(bytes[pos + 9].to_int(), 2)}", ""),
      ]))
      pos = pos + 10
      // Skip LZW code size and image data
      if pos < len {
        let lzw_size = bytes[pos].to_int()
        fields.push(field(pos, 1, "LZWMinCode", "\{lzw_size}", "LZW minimum code size"))
        pos = pos + 1
        while pos < len {
          let block_size = bytes[pos].to_int()
          if block_size == 0 { pos = pos + 1; break }
          if pos + 1 + block_size <= len {
            fields.push(field(pos, 1 + block_size, "DataBlock", "\{block_size} bytes", ""))
            pos = pos + 1 + block_size
          } else { break }
        }
      }
    } else if b == 0x21 {
      if pos + 1 < len {
        let ext_type = bytes[pos + 1].to_int()
        let ext_name = match ext_type { 0xF9 => "GCE"; 0xFE => "Comment"; 0xFF => "App"; 0x01 => "Text"; _ => "Ext" }
        let mut ext_pos = pos + 2
        while ext_pos < len {
          let bs = bytes[ext_pos].to_int()
          if bs == 0 { ext_pos = ext_pos + 1; break }
          if ext_pos + 1 + bs <= len {
            fields.push(field(ext_pos, 1 + bs, "\{ext_name}Data", "\{bs} bytes", ""))
            ext_pos = ext_pos + 1 + bs
          } else { break }
        }
        pos = ext_pos
      } else { break }
    } else if b == 0x3B {
      fields.push(field(pos, 1, "Trailer", "0x3B", "End of GIF"))
      break
    } else { break }
  }
  fields
}

// ============== BMP ==============

fn parse_bmp(bytes : Bytes) -> Array[StructField] {
  let len = bytes.length()
  let fields = []
  guard len >= 14 else { return [field(0, len, "TRUNCATED", "", "Too small for BMP")] }

  let file_size = read_u32_le(bytes, 2)
  let data_off = read_u32_le(bytes, 10)
  let hdr_size = read_u32_le(bytes, 14)
  let w = read_u32_le(bytes, 18)
  let h = read_u32_le(bytes, 22)
  let planes = read_u16_le(bytes, 26)
  let bpp = read_u16_le(bytes, 28)
  let comp = read_u32_le(bytes, 30)
  let comp_str = match comp { 0 => "RGB"; 1 => "RLE8"; 2 => "RLE4"; 3 => "Bitfields"; _ => "?" }

  fields.push(group(0, 14, "BMP Header", "\{file_size} bytes, data at 0x\{hex(data_off, 8)}", [
    field(0, 2, "Signature", "BM", ""),
    field(2, 4, "FileSize", "\{file_size}", ""),
    field(10, 4, "DataOffset", "0x\{hex(data_off, 8)}", ""),
  ]))

  fields.push(group(14, hdr_size, "DIB Header", "\{w}x\{h} (0x\{hex(w, 8)} x 0x\{hex(h, 8)}), \{bpp}bpp, \{comp_str}", [
    field(14, 4, "HeaderSize", "\{hdr_size}", ""),
    field(18, 4, "Width", "\{w} (0x\{hex(w, 8)})", ""),
    field(22, 4, "Height", "\{h} (0x\{hex(h, 8)})", ""),
    field(26, 2, "Planes", "\{planes}", ""),
    field(28, 2, "BitsPerPixel", "\{bpp}", ""),
    field(30, 4, "Compression", comp_str, ""),
  ]))

  let pixel_start = 14 + hdr_size
  if data_off > pixel_start {
    fields.push(field(pixel_start, data_off - pixel_start, "Palette/Gap", "\{data_off - pixel_start} bytes", "Color table or gap"))
  }
  if data_off < len {
    fields.push(field(data_off, len - data_off, "PixelData", "\{len - data_off} bytes", "Bitmap pixels"))
  }
  fields
}

// ============== RAR ==============

fn parse_rar(bytes : Bytes) -> Array[StructField] {
  let len = bytes.length()
  let fields = []
  let ver = read_str(bytes, 0, 4)
  fields.push(field(0, 7, "Signature", "\{ver}!\\x1A\\x07", "RAR archive"))
  let is_rar5 = len >= 8 && bytes[7].to_int() == 1
  fields.push(field(7, 1, "Version", if is_rar5 { "RAR5" } else { "RAR4" }, ""))

  let mut pos = 8
  let mut block_count = 0
  for iter = 0; pos + 7 <= len && iter < 100; iter = iter + 1 {
    let head_crc = read_u16_le(bytes, pos)
    let head_type = bytes[pos + 2].to_int()
    let head_flags = read_u16_le(bytes, pos + 3)
    let head_size = read_u16_le(bytes, pos + 5)
    if head_size == 0 || pos + head_size > len { break }

    let type_str = match head_type {
      0x72 => "Marker"; 0x73 => "Archive"; 0x74 => "File"
      0x75 => "Comment"; 0x76 => "Extra"; 0x77 => "OldRecovery"
      0x78 => "SubBlock"; 0x79 => "Recovery"; 0x7A => "Authenticity"
      _ => "Type_\{head_type}"
    }
    let desc = if head_type == 0x74 {
      let name_len = if pos + 32 <= len { read_u16_le(bytes, pos + 7) } else { 0 }
      if name_len > 0 && pos + 32 + name_len <= len { read_str(bytes, pos + 32, name_len) } else { "" }
    } else { "" }
    let encrypted = if is_rar5 { (head_flags & 0x80) != 0 } else { (head_flags & 0x01) != 0 }
    let mut desc_text = if desc != "" { ": \{desc}" } else { "" }
    if encrypted { desc_text = "\{desc_text} [Encrypted]" }

    fields.push(group(pos, head_size, "\{type_str} Block #\{block_count + 1}", "\{head_size} bytes\{desc_text}", [
      field(pos, 2, "CRC16", "0x\{hex(head_crc, 4)}", ""),
      field(pos + 2, 1, "Type", type_str, ""),
      field(pos + 3, 2, "Flags", "0x\{hex(head_flags, 4)}", if encrypted { "Encrypted" } else { "" }),
      field(pos + 5, 2, "Size", "\{head_size}", ""),
    ]))
    block_count = block_count + 1
    pos = pos + head_size
  }
  if pos < len {
    fields.push(field(pos, len - pos, "Trailing", "\{len - pos} bytes", ""))
  }
  fields
}

// ============== TAR ==============

fn parse_tar(bytes : Bytes) -> Array[StructField] {
  let len = bytes.length()
  let fields = []
  fields.push(field(257, 5, "USTAR", "ustar", "POSIX tar format"))

  let mut pos = 0
  let mut file_count = 0
  for iter = 0; pos + 512 <= len && iter < 200; iter = iter + 1 {
    // Check for end: two zero blocks
    let mut empty = true
    for i = pos; i < pos + 512 && i < len; i = i + 1 {
      if bytes[i] != b'\x00' { empty = false; break }
    }
    if empty { break }

    let name = read_str(bytes, pos, 100)
    let sz_str = read_str(bytes, pos + 124, 12)
    let size = parse_octal(sz_str)
    let typeflag = bytes[pos + 156].to_int()
    let tf = if typeflag == 0 || typeflag == '0'.to_int() { "File" }
    else if typeflag == '5'.to_int() { "Dir" }
    else if typeflag == '2'.to_int() { "Symlink" }
    else if typeflag == '1'.to_int() { "Hardlink" }
    else { "?" }

    let blocks = (size + 511) / 512
    let total = if size > 0 { (blocks + 1) * 512 } else { 512 }

    if name != "" || size > 0 {
      file_count = file_count + 1
      fields.push(group(pos, total, "\{tf} #\{file_count}", "\{name} (\{size} bytes)", [
        field(pos, 100, "Name", name, ""),
        field(pos + 100, 8, "Mode", read_str(bytes, pos + 100, 8), ""),
        field(pos + 124, 12, "Size", "\{size}", "\{blocks} data blocks"),
        field(pos + 136, 12, "MTime", read_str(bytes, pos + 136, 12), "Unix timestamp"),
        field(pos + 156, 1, "Type", tf, ""),
      ]))
    }
    pos = pos + total
  }
  if pos < len {
    fields.push(field(pos, len - pos, "Trailing", "\{len - pos} bytes", ""))
  }
  fields
}

///|
/// Parse octal string to integer (used by TAR).
fn parse_octal(s : String) -> Int {
  let mut result = 0
  for i = 0; i < s.length(); i = i + 1 {
    let c = s.get_char(i).unwrap().to_int()
    if c >= '0'.to_int() && c <= '7'.to_int() {
      result = result * 8 + (c - '0'.to_int())
    }
  }
  result
}

// ============== ZLIB ==============

fn parse_zlib(bytes : Bytes) -> Array[StructField] {
  let len = bytes.length()
  let fields = []
  let cmf = bytes[0].to_int()
  let flg = bytes[1].to_int()
  let cm = cmf & 0x0F
  let cinfo = (cmf >> 4) & 0x0F
  let fdict = (flg >> 5) & 1
  let flevel = (flg >> 6) & 3

  let level_str = match flevel {
    0 => "Fastest"; 1 => "Fast"; 2 => "Default"; 3 => "Slowest/Best"
    _ => "?"
  }
  let window = 1 << (cinfo + 8)

  fields.push(group(0, 2, "ZLIB Header", "Deflate, window=\{window}B, \{level_str}", [
    field(0, 1, "CMF", "0x\{hex(cmf, 2)}", "Method=\{cm}, WinSize=\{window}"),
    field(1, 1, "FLG", "0x\{hex(flg, 2)}", "Level=\{level_str}, FDICT=\{fdict}"),
  ]))

  let mut pos = 2
  if fdict != 0 && pos + 4 <= len {
    let dict_id = read_u32_be(bytes, pos)
    fields.push(field(pos, 4, "DictID", "0x\{hex(dict_id, 8)}", "Preset dictionary ID"))
    pos = pos + 4
  }

  // Compressed data - until 4 bytes before end (Adler-32)
  let data_end = len - 4
  if data_end > pos {
    fields.push(field(pos, data_end - pos, "CompressedData", "\{data_end - pos} bytes", "Deflate stream"))
  }

  // Adler-32 checksum at end
  if len >= 4 {
    let adler = read_u32_be(bytes, len - 4)
    fields.push(field(len - 4, 4, "Adler32", "0x\{hex(adler, 8)}", "Checksum"))
  }

  fields
}

// ============== WAV ==============

fn parse_wav(bytes : Bytes) -> Array[StructField] {
  let len = bytes.length()
  let fields = []
  fields.push(field(0, 4, "RIFF", "RIFF", "Resource Interchange File Format"))
  let file_size = read_u32_le(bytes, 4)
  fields.push(field(4, 4, "FileSize", "\{file_size} (0x\{hex(file_size, 8)})", "File size - 8"))
  fields.push(field(8, 4, "WAVE", "WAVE", "WAVE format"))

  let mut pos = 12
  for iter = 0; pos + 8 <= len && iter < 30; iter = iter + 1 {
    let ck_id = read_str(bytes, pos, 4)
    let ck_size = read_u32_le(bytes, pos + 4)
    if ck_size == 0 || pos + 8 + ck_size > len { break }

    if ck_id == "fmt " {
      let audio_fmt = read_u16_le(bytes, pos + 8)
      let channels = read_u16_le(bytes, pos + 10)
      let sample_rate = read_u32_le(bytes, pos + 12)
      let bps = read_u16_le(bytes, pos + 22)
      let fmt_str = match audio_fmt { 1 => "PCM"; 3 => "IEEE Float"; 6 => "ALaw"; 7 => "MuLaw"; _ => "0x\{hex(audio_fmt, 4)}" }
      fields.push(group(pos, 8 + ck_size, "fmt ", "\{fmt_str}, \{channels}ch, \{sample_rate}Hz, \{bps}bit", [
        field(pos, 4, "ChunkID", "fmt ", ""),
        field(pos + 4, 4, "ChunkSize", "\{ck_size}", ""),
        field(pos + 8, 2, "AudioFormat", fmt_str, ""),
        field(pos + 10, 2, "Channels", "\{channels}", ""),
        field(pos + 12, 4, "SampleRate", "\{sample_rate} Hz", ""),
        field(pos + 16, 4, "ByteRate", "\{read_u32_le(bytes, pos + 16)}", "Bytes/sec"),
        field(pos + 20, 2, "BlockAlign", "\{read_u16_le(bytes, pos + 20)}", ""),
        field(pos + 22, 2, "BitsPerSample", "\{bps}", ""),
      ]))
    } else if ck_id == "fact" {
      let fcount_val = read_u32_le(bytes, pos + 8)
      fields.push(group(pos, 8 + ck_size, "fact", fcount_val.to_string() + " samples", [
        field(pos, 4, "ChunkID", "fact", ""),
        field(pos + 4, 4, "ChunkSize", ck_size.to_string(), ""),
        field(pos + 8, 4, "SampleLength", fcount_val.to_string(), "Uncompressed samples"),
      ]))
    } else if ck_id == "data" {
      fields.push(field(pos, 8 + ck_size, "data", "{ck_size} bytes", "Audio samples"))
    } else {
      fields.push(field(pos, 8 + ck_size, ck_id, "\{ck_size} bytes", "RIFF chunk"))
      }
    pos = pos + 8 + ck_size
    if ck_size % 2 != 0 { pos = pos + 1 }
      }
    if pos < len { fields.push(field(pos, len - pos, "Trailing", "\{len - pos} bytes", "")) }
  fields
}

// ============== FLAC ==============

fn parse_flac(bytes : Bytes) -> Array[StructField] {
  let len = bytes.length()
  let fields = []
  fields.push(field(0, 4, "Signature", "fLaC", "FLAC magic"))

  let mut pos = 4
  let mut last_block = false
  for iter = 0; pos + 4 <= len && iter < 50 && !last_block; iter = iter + 1 {
    let header = bytes[pos].to_int()
    last_block = (header >> 7) != 0
    let block_type = header & 0x7F
    let block_size = read_u24_be(bytes, pos + 1)
    if block_size == 0 || pos + 4 + block_size > len { break }

    let type_str = match block_type {
      0 => "STREAMINFO"; 1 => "PADDING"; 2 => "APPLICATION"
      3 => "SEEKTABLE"; 4 => "VORBIS_COMMENT"; 5 => "CUESHEET"
      6 => "PICTURE"; _ => "UNKNOWN"
    }
    let desc = if block_type == 0 && pos + 4 + 18 <= len {
      let _min_block = read_u16_be(bytes, pos + 4)
      let _max_block = read_u16_be(bytes, pos + 6)
      let sample_rate = (bytes[pos + 10].to_int() << 12) | (bytes[pos + 11].to_int() << 4) | (bytes[pos + 12].to_int() >> 4)
      let bps = ((bytes[pos + 12].to_int() & 1) << 4) | ((bytes[pos + 13].to_int() >> 4) & 0xF)
      let bps = bps + 1
      let mut total_samples = bytes[pos + 13].to_int() & 0xF
      for j = 14; j < 18; j = j + 1 { total_samples = total_samples * 256 + bytes[pos + j].to_int() }
      "\{sample_rate}Hz, \{bps}bit, \{if bps > 1 { bps } else { 0 }}ch, \{total_samples} samples"
    } else { "\{block_size} bytes" }

    fields.push(group(pos, 4 + block_size, type_str, desc, [
      field(pos, 1, "Header", "0x\{hex(header, 2)}", "Last=\{last_block}, Type=\{block_type}"),
      field(pos + 1, 3, "BlockSize", "\{block_size}", ""),
    ]))
    pos = pos + 4 + block_size
  }
  if pos < len { fields.push(field(pos, len - pos, "Trailing", "\{len - pos} bytes", "")) }
  fields
}

///|
/// Read big-endian uint24 from bytes.
fn read_u24_be(bytes : Bytes, off : Int) -> Int {
  guard off + 3 <= bytes.length() else { 0 }
  bytes[off].to_int() * 65536 + bytes[off + 1].to_int() * 256 + bytes[off + 2].to_int()
}

// ============== OGG ==============

fn parse_ogg(bytes : Bytes) -> Array[StructField] {
  let len = bytes.length()
  let fields = []
  let mut pos = 0
  let mut page = 0
  for iter = 0; pos + 27 <= len && iter < 100; iter = iter + 1 {
    let sig = read_str(bytes, pos, 4)
    if sig != "OggS" { break }
    page = page + 1
    let version = bytes[pos + 4].to_int()
    let hdr_type = bytes[pos + 5].to_int()
    // granule position (unused for display, just skip)
    let serial = read_u32_le(bytes, pos + 14)
    let page_seq = read_u32_le(bytes, pos + 18)
    let segments = bytes[pos + 26].to_int()
    let mut total_seg_size = 0
    for i = 0; i < segments; i = i + 1 {
      if pos + 27 + i < len { total_seg_size = total_seg_size + bytes[pos + 27 + i].to_int() }
    }
    let page_size = 27 + segments + total_seg_size

    fields.push(group(pos, page_size, "Page #\{page}", "Seq=\{page_seq}, \{segments} segments, \{total_seg_size}B data", [
      field(pos, 4, "Signature", "OggS", ""),
      field(pos + 4, 1, "Version", "\{version}", ""),
      field(pos + 5, 1, "Flags", "0x\{hex(hdr_type, 2)}", ""),
      field(pos + 14, 4, "Serial", "0x\{hex(serial, 8)}", ""),
      field(pos + 18, 4, "PageNo", "\{page_seq}", ""),
      field(pos + 26, 1, "Segments", "\{segments}", ""),
    ]))
    pos = pos + page_size
  }
  if pos < len { fields.push(field(pos, len - pos, "Trailing", "\{len - pos} bytes", "")) }
  fields
}

// ============== MP4 ==============

fn parse_mp4(bytes : Bytes) -> Array[StructField] {
  let len = bytes.length()
  let fields = []
  let mut pos = 0
  let mut box_count = 0
  for iter = 0; pos + 8 <= len && iter < 60; iter = iter + 1 {
    let box_size = read_u32_be(bytes, pos)
    let box_type = read_str(bytes, pos + 4, 4)
    if box_size < 8 || pos + box_size > len { break }
    box_count = box_count + 1

    let desc = if box_type == "ftyp" && box_size >= 12 {
      let brand = read_str(bytes, pos + 8, 4)
      "Brand: \{brand}"
    } else if box_type == "moov" { "Movie metadata" }
    else if box_type == "moof" { "Movie fragment" }
    else if box_type == "mdat" { "Media data" }
    else if box_type == "trak" { "Track" }
    else if box_type == "mdia" { "Media" }
    else { "\{box_size} bytes" }

    fields.push(field(pos, box_size, box_type, "\{box_size} bytes", desc))
    pos = pos + box_size
  }
  if pos < len { fields.push(field(pos, len - pos, "Trailing", "\{len - pos} bytes", "")) }
  fields
}

// ============== WebM/MKV ==============

fn parse_webm(bytes : Bytes) -> Array[StructField] {
  let len = bytes.length()
  let fields = []
  let ebml_id = read_u32_be(bytes, 0)
  fields.push(field(0, 4, "EBML", "0x\{hex(ebml_id, 8)}", "EBML header"))

  let mut pos = 4
  let mut el_count = 0
  for iter = 0; pos + 2 <= len && iter < 80; iter = iter + 1 {
    let (el_id, id_len) = read_ebml_id(bytes, pos, len)
    let (el_size, size_len) = read_ebml_size(bytes, pos + id_len, len)
    if el_size == 0 || pos + id_len + size_len + el_size > len { break }
    el_count = el_count + 1

    let el_name = ebml_name(el_id)
    let total = id_len + size_len + el_size
    fields.push(group(pos, total, el_name, "\{el_size} bytes", [
      field(pos, id_len, "ElementID", "0x\{el_id}", ""),
      field(pos + id_len, size_len, "ElementSize", "\{el_size}", ""),
    ]))
    pos = pos + total
  }
  if pos < len { fields.push(field(pos, len - pos, "Trailing", "\{len - pos} bytes", "")) }
  fields
}

fn read_ebml_id(bytes : Bytes, off : Int, len : Int) -> (Int, Int) {
  guard off < len else { (0, 0) }
  let first = bytes[off].to_int()
  let mut id_len = 1
  if (first & 0x80) != 0 { id_len = 1 }
  else if (first & 0x40) != 0 { id_len = 2 }
  else if (first & 0x20) != 0 { id_len = 3 }
  else { id_len = 4 }
  if off + id_len > len { return (0, id_len) }
  let mut id = 0
  for i = 0; i < id_len; i = i + 1 { id = (id << 8) | bytes[off + i].to_int() }
  (id, id_len)
}

fn read_ebml_size(bytes : Bytes, off : Int, len : Int) -> (Int, Int) {
  guard off < len else { (0, 0) }
  let first = bytes[off].to_int()
  let mut size_len = 1
  let mut mask = 0x80
  for i = 0; i < 8; i = i + 1 {
    if (first & mask) != 0 { size_len = i + 1; break }
    mask = mask >> 1
  }
  if off + size_len > len { return (0, size_len) }
  // Clear the marker bit
  let mut size = first & (mask - 1)
  for i = 1; i < size_len; i = i + 1 { size = (size << 8) | bytes[off + i].to_int() }
  (size, size_len)
}

fn ebml_name(id : Int) -> String {
  if id == 0x1A45DFA3 { "EBML" }
  else if id == 0x4286 { "EBMLVersion" }
  else if id == 0x42F7 { "EBMLReadVersion" }
  else if id == 0x42F2 { "EBMLMaxIDLength" }
  else if id == 0x42F3 { "EBMLMaxSizeLength" }
  else if id == 0x4282 { "DocType" }
  else if id == 0x4287 { "DocTypeVersion" }
  else if id == 0x4285 { "DocTypeReadVersion" }
  else if id == 0x18538067 { "Segment" }
  else if id == 0x114D9B74 { "SeekHead" }
  else if id == 0x1549A966 { "Info" }
  else if id == 0x1654AE6B { "Tracks" }
  else if id == 0x1F43B675 { "Cluster" }
  else if id == 0x1254C367 { "Tags" }
  else if id == 0x1C53BB6B { "Cues" }
  else if id == 0xE7 { "Void" }
  else if id == 0xEC { "CRC32" }
  else { "EBML_0x\{hex(id, 8)}" }
}

// ============== AVI ==============

fn parse_avi(bytes : Bytes) -> Array[StructField] {
  let len = bytes.length()
  let fields = []
  fields.push(field(0, 4, "RIFF", "RIFF", ""))
  fields.push(field(4, 4, "FileSize", "\{read_u32_le(bytes, 4)}", ""))
  fields.push(field(8, 4, "AVI ", "AVI ", "AVI container"))
  fields.push(field(12, len - 12, "AVI Data", "\{len - 12} bytes", "AVI chunks"))
  fields
}

// ============== MP3 ==============

fn parse_mp3(bytes : Bytes) -> Array[StructField] {
  let len = bytes.length()
  let fields = []
  let ver = read_str(bytes, 0, 3)
  let major = bytes[3].to_int()
  let rev = bytes[4].to_int()
  let flags = bytes[5].to_int()
  let tag_size = read_u32_syncsafe(bytes, 6)

  fields.push(group(0, 10, "ID3v2 Header", "ID3v2.\{major}.\{rev}, \{tag_size} bytes", [
    field(0, 3, "Signature", ver, ""),
    field(3, 1, "Version", "2.\{major}.\{rev}", ""),
    field(5, 1, "Flags", "0x\{hex(flags, 2)}", ""),
    field(6, 4, "Size", "\{tag_size}", "Syncsafe integer"),
  ]))

  let total_header = 10 + tag_size
  if total_header < len {
    fields.push(field(10, tag_size, "ID3v2 Frames", "\{tag_size} bytes", "ID3 tag data"))
    // Try to detect first MPEG frame after ID3 tag
    let data_start = total_header
    if data_start + 2 <= len {
      let sync = read_u16_be(bytes, data_start)
      if (sync >> 5) == 0x7FF {
        let mpeg_ver = (sync >> 3) & 3
        let layer = (sync >> 1) & 3
        let _bitrate_idx = bytes[data_start + 2].to_int() >> 4
        let sample_rate_idx = (bytes[data_start + 2].to_int() >> 2) & 3
        let mpeg_ver_str = match mpeg_ver { 3 => "MPEG1"; 2 => "MPEG2"; _ => "?" }
        let layer_str = match layer { 3 => "LayerI"; 2 => "LayerII"; 1 => "LayerIII"; _ => "?" }
        let sr = match (mpeg_ver, sample_rate_idx) {
          (3, 0) => "44100"; (3, 1) => "48000"; (3, 2) => "32000"
          (2, 0) => "22050"; (2, 1) => "24000"; (2, 2) => "16000"
          _ => "?"
        }
        fields.push(group(data_start, len - data_start, "MPEG Frames", "\{mpeg_ver_str} \{layer_str}, \{sr}Hz", [
          field(data_start, 2, "Sync", "0x\{hex(sync, 4)}", "Frame sync"),
          field(data_start + 2, 1, "Bitrate/SR", "0x\{hex(bytes[data_start + 2].to_int(), 2)}", ""),
        ]))
      } else {
        fields.push(field(data_start, len - data_start, "AudioData", "\{len - data_start} bytes", "MPEG audio"))
      }
    }
  }
  fields
}

///|
/// Read syncsafe integer (ID3v2 uses this — each byte has MSB=0).
fn read_u32_syncsafe(bytes : Bytes, off : Int) -> Int {
  guard off + 4 <= bytes.length() else { 0 }
  ((bytes[off].to_int() & 0x7F) << 21) | ((bytes[off + 1].to_int() & 0x7F) << 14) |
  ((bytes[off + 2].to_int() & 0x7F) << 7) | (bytes[off + 3].to_int() & 0x7F)
}

// ============== ELF ==============

fn parse_elf(bytes : Bytes) -> Array[StructField] {
  let len = bytes.length()
  guard len >= 52 else { return [field(0, len, "TRUNCATED", "", "Too small for ELF")] }
  let fields = []
  let is64 = bytes[4].to_int() == 2
  let isle = bytes[5].to_int() == 1

  let ei_ver = bytes[6].to_int()
  let ei_osabi = bytes[7].to_int()
  let ei_abiver = bytes[8].to_int()
  let osabi_s = match ei_osabi { 0 => "UNIX"; 2 => "NetBSD"; 3 => "Linux"; 6 => "Solaris"; 9 => "FreeBSD"; _ => "?" }
  fields.push(group(0, 16, "ELF Ident", "\{if is64 { "64-bit" } else { "32-bit" }} \{if isle { "LE" } else { "BE" }}, \{osabi_s}", [
    field(0, 4, "Magic", "7F 45 4C 46", ""),
    field(4, 1, "ei_class", if is64 { "ELF64" } else { "ELF32" }, ""),
    field(5, 1, "ei_data", if isle { "LittleEndian" } else { "BigEndian" }, ""),
    field(6, 1, "ei_version", "\{ei_ver}", ""),
    field(7, 1, "ei_osabi", osabi_s, ""),
    field(8, 1, "ei_abiversion", "\{ei_abiver}", ""),
  ]))

  let r16 = if isle { fn(b, o) { read_u16_le(b, o) } } else { fn(b, o) { read_u16_be(b, o) } }
  let r32 = if isle { fn(b, o) { read_u32_le(b, o) } } else { fn(b, o) { read_u32_be(b, o) } }

  let e_type = r16(bytes, 16)
  let e_machine = r16(bytes, 18)
  let e_entry = r32(bytes, 24)
  let e_flags = r32(bytes, if is64 { 48 } else { 36 })
  let e_ehsize = r16(bytes, if is64 { 52 } else { 40 })
  let e_phentsize = r16(bytes, if is64 { 54 } else { 42 })
  let e_phnum = r16(bytes, if is64 { 56 } else { 44 })
  let e_shentsize = r16(bytes, if is64 { 58 } else { 46 })
  let e_shnum = r16(bytes, if is64 { 60 } else { 48 })
  let e_shstrndx = r16(bytes, if is64 { 62 } else { 50 })
  let e_phoff = if is64 { r32(bytes, 32) } else { r32(bytes, 28) }
  let e_shoff = if is64 { r32(bytes, 40) } else { r32(bytes, 32) }

  let tname = match e_type { 1 => "REL"; 2 => "EXEC"; 3 => "DYN"; _ => "?" }
  let mname = match e_machine { 3 => "i386"; 62 => "AMD64"; 40 => "ARM"; 183 => "ARM64"; _ => "?" }
  let hdr_sz = if is64 { 64 } else { 52 }

  fields.push(group(16, hdr_sz - 16, "ELF Header", "Type:\{tname} Machine:\{mname}", [
    field(16, 2, "e_type", tname, ""),
    field(18, 2, "e_machine", mname, ""),
    field(24, 4, "e_entry", "0x\{hex(e_entry, 8)}", "Entry point"),
    field(if is64 { 48 } else { 36 }, 4, "e_flags", "0x\{hex(e_flags, 8)}", ""),
    field(if is64 { 32 } else { 28 }, 4, "e_phoff", "0x\{hex(e_phoff, 8)}", "Program header offset"),
    field(if is64 { 40 } else { 32 }, 4, "e_shoff", "0x\{hex(e_shoff, 8)}", "Section header offset"),
    field(if is64 { 52 } else { 40 }, 2, "e_ehsize", "\{e_ehsize}", ""),
    field(if is64 { 54 } else { 42 }, 2, "e_phentsize", "\{e_phentsize}", ""),
    field(if is64 { 56 } else { 44 }, 2, "e_phnum", "\{e_phnum}", "Program headers"),
    field(if is64 { 58 } else { 46 }, 2, "e_shentsize", "\{e_shentsize}", ""),
    field(if is64 { 60 } else { 48 }, 2, "e_shnum", "\{e_shnum}", "Section headers"),
    field(if is64 { 62 } else { 50 }, 2, "e_shstrndx", "\{e_shstrndx}", "String table index"),
  ]))
  fields
}

///|
/// Display parsed structure as readable text.
pub fn format_structure(fields : Array[StructField]) -> String {
  format_fields(fields, 0)
}

fn format_fields(fields : Array[StructField], indent : Int) -> String {
  let sb = StringBuilder()
  let pfx = StringBuilder()
  for _i = 0; _i < indent; _i = _i + 1 { pfx.write_string("  ") }
  let pad = pfx.to_string()
  for i = 0; i < fields.length(); i = i + 1 {
    let f = fields[i]
    if f.children.length() > 0 {
      sb.write_string("\{pad}0x\{hex(f.offset, 8)}  \{f.name}\n")
      if f.description != "" { sb.write_string("\{pad}  \{f.description}\n") }
      sb.write_string(format_fields(f.children, indent))
    } else {
      sb.write_string("\{pad}0x\{hex(f.offset, 8)}  \{f.name} = \{f.value}")
      if f.description != "" { sb.write_string("  -- \{f.description}") }
      sb.write_char('\n')
    }
  }
  sb.to_string()
}
