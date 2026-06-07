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
  if magic_be == 0xFFD8 { parse_jpeg(bytes) }
  else if magic_be == 0x8950 { parse_png(bytes) }
  else if magic_be == 0x4D5A || magic_be == 0x5A4D { parse_pe(bytes) }
  else if magic_le == 0x04034B50 { parse_zip(bytes) }
  else if len >= 6 && (read_str(bytes, 0, 6) == "GIF87a" || read_str(bytes, 0, 6) == "GIF89a") { parse_gif(bytes) }
  else if magic_be == 0x424D { parse_bmp(bytes) }
  else if len >= 7 && read_str(bytes, 0, 4) == "Rar!" { parse_rar(bytes) }
  else if len >= 512 && read_str(bytes, 257, 5) == "ustar" { parse_tar(bytes) }
  else if len >= 4 && bytes[0] == b'\x7F' && bytes[1] == b'E' && bytes[2] == b'L' && bytes[3] == b'F' {
    parse_elf(bytes)
  }
  else { [] }
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
  if pos < len {
    fields.push(field(pos, len - pos, "Trailing", "\{len - pos} bytes", "Remaining data"))
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

      fields.push(group(pos, total, "LocalFile #\{file_count}", desc, [
        field(pos, 4, "Signature", "PK\\03\\04", ""),
        field(pos + 4, 2, "Version", "\{ver}", ""),
        field(pos + 6, 2, "Flags", "0x\{hex(flags, 4)}", ""),
        field(pos + 8, 2, "Method", cmethod_str, ""),
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
    let desc_text = if desc != "" { ": \{desc}" } else { "" }

    fields.push(group(pos, head_size, "\{type_str} Block #\{block_count + 1}", "\{head_size} bytes\{desc_text}", [
      field(pos, 2, "CRC16", "0x\{hex(head_crc, 4)}", ""),
      field(pos + 2, 1, "Type", type_str, ""),
      field(pos + 3, 2, "Flags", "0x\{hex(head_flags, 4)}", ""),
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

// ============== ELF ==============

fn parse_elf(bytes : Bytes) -> Array[StructField] {
  let len = bytes.length()
  guard len >= 52 else { return [field(0, len, "TRUNCATED", "", "Too small for ELF")] }
  let fields = []
  let is64 = bytes[4].to_int() == 2
  let isle = bytes[5].to_int() == 1

  fields.push(group(0, 16, "ELF Ident", "\{if is64 { "64-bit" } else { "32-bit" }} \{if isle { "LE" } else { "BE" }}", [
    field(0, 4, "Magic", "7F 45 4C 46", ""),
    field(4, 1, "Class", if is64 { "ELF64" } else { "ELF32" }, ""),
    field(5, 1, "Data", if isle { "LittleEndian" } else { "BigEndian" }, ""),
  ]))

  let r16 = if isle { fn(b, o) { read_u16_le(b, o) } } else { fn(b, o) { read_u16_be(b, o) } }
  let r32 = if isle { fn(b, o) { read_u32_le(b, o) } } else { fn(b, o) { read_u32_be(b, o) } }

  let e_type = r16(bytes, 16)
  let e_machine = r16(bytes, 18)
  let e_entry = r32(bytes, 24)
  let e_phoff = if is64 { r32(bytes, 32) } else { r32(bytes, 28) }
  let e_shoff = if is64 { r32(bytes, 40) } else { r32(bytes, 32) }
  let e_phnum = r16(bytes, if is64 { 56 } else { 44 })
  let e_shnum = r16(bytes, if is64 { 60 } else { 48 })

  let tname = match e_type { 1 => "REL"; 2 => "EXEC"; 3 => "DYN"; _ => "?" }
  let mname = match e_machine { 3 => "i386"; 62 => "AMD64"; 40 => "ARM"; 183 => "ARM64"; _ => "?" }
  let hdr_sz = if is64 { 64 } else { 52 }

  fields.push(group(16, hdr_sz - 16, "ELF Header", "Type:\{tname} Machine:\{mname}", [
    field(16, 2, "Type", tname, ""),
    field(18, 2, "Machine", mname, ""),
    field(24, 4, "Entry", "0x\{hex(e_entry, 8)}", "Entry point"),
    field(if is64 { 32 } else { 28 }, 4, "PHoff", "0x\{hex(e_phoff, 8)}", "Program header offset"),
    field(if is64 { 40 } else { 32 }, 4, "SHoff", "0x\{hex(e_shoff, 8)}", "Section header offset"),
    field(if is64 { 56 } else { 44 }, 2, "PHnum", "\{e_phnum}", "Program headers"),
    field(if is64 { 60 } else { 48 }, 2, "SHnum", "\{e_shnum}", "Section headers"),
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
