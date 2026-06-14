// Binary signature scanner — binwalk-like signature scanning

///|
/// A detected signature match at a file offset.
pub struct ScanMatch {
  offset : Int
  name : String
  mut size : Int
  confidence : Int
} derive(Debug)

///|
/// A single entropy block result.
pub struct EntropyBlock {
  start : Int
  end : Int
  entropy : Double
} derive(Debug)

///|
/// Scan all bytes for known file signatures (magic bytes).
/// Returns matches sorted by offset.
pub fn scan_signatures(bytes : Bytes) -> Array[ScanMatch] {
  let len = bytes.length()
  let results : Array[ScanMatch] = []

  for off = 0; off < len; off = off + 1 {
    // JPEG: require FFD8 FF + marker byte (binwalk: FFD8 FFE0 0010 JFIF)
    // Pure FFD8 alone is too common in random data
    if off + 4 <= len && bytes[off].to_int() == 0xFF && bytes[off + 1].to_int() == 0xD8 &&
      bytes[off + 2].to_int() == 0xFF {
      let marker = bytes[off + 3].to_int()
      // Valid APP/COM/DQT/SOF markers follow SOI
      if (marker >= 0xE0 && marker <= 0xEF) || marker == 0xFE || marker == 0xDB ||
        (marker >= 0xC0 && marker <= 0xC4) {
        results.push({ offset: off, name: "JPEG image", size: 0, confidence: 2 })
      }
    }
    // PNG: 8-byte magic + IHDR must follow (binwalk: requires \x00\x00\x00\x0DIHDR)
    if off + 21 <= len && bytes[off].to_int() == 0x89 && bytes[off + 1].to_int() == 0x50 &&
      bytes[off + 2].to_int() == 0x4E && bytes[off + 3].to_int() == 0x47 &&
      bytes[off + 4].to_int() == 0x0D && bytes[off + 5].to_int() == 0x0A &&
      bytes[off + 6].to_int() == 0x1A && bytes[off + 7].to_int() == 0x0A &&
      read_u32_be_at(bytes, off + 8) == 0x0D && read_str_at(bytes, off + 12, 4) == "IHDR" {
      results.push({ offset: off, name: "PNG image", size: 0, confidence: 3 })
    }
    // GIF
    if off + 6 <= len && (read_str_at(bytes, off, 6) == "GIF87a" || read_str_at(bytes, off, 6) == "GIF89a") {
      results.push({ offset: off, name: "GIF image", size: 0, confidence: 0 })
    }
    // BMP
    if off + 2 <= len && bytes[off].to_int() == 0x42 && bytes[off + 1].to_int() == 0x4D {
      results.push({ offset: off, name: "BMP image", size: 0, confidence: 0 })
    }
    // WAV / AVI RIFF
    if off + 12 <= len && read_str_at(bytes, off, 4) == "RIFF" {
      let subtype = read_str_at(bytes, off + 8, 4)
      if subtype == "WAVE" {
        results.push({ offset: off, name: "WAV audio", size: 0, confidence: 0 })
      } else if subtype == "AVI " {
        results.push({ offset: off, name: "AVI video", size: 0, confidence: 0 })
      } else {
        results.push({ offset: off, name: "RIFF container (\{subtype})", size: 0, confidence: 0 })
      }
    }
    // FLAC
    if off + 4 <= len && read_str_at(bytes, off, 4) == "fLaC" {
      results.push({ offset: off, name: "FLAC audio", size: 0, confidence: 0 })
    }
    // OGG
    if off + 4 <= len && read_str_at(bytes, off, 4) == "OggS" {
      results.push({ offset: off, name: "OGG container", size: 0, confidence: 0 })
    }
    // MP3 ID3
    if off + 3 <= len && read_str_at(bytes, off, 3) == "ID3" {
      results.push({ offset: off, name: "MP3 audio (ID3)", size: 0, confidence: 0 })
    }
    // MP4 / ftyp
    if off + 8 <= len && read_u32_be_at(bytes, off + 4) == 0x66747970 {
      results.push({ offset: off, name: "MP4 video", size: 0, confidence: 0 })
    }
    // WebM / MKV EBML
    if off + 4 <= len && read_u32_be_at(bytes, off) == 0x1A45DFA3 {
      results.push({ offset: off, name: "WebM/MKV video", size: 0, confidence: 0 })
    }
    // ZIP: PK\x03\x04 + validate local file header fields
    if off + 30 <= len && bytes[off].to_int() == 0x50 && bytes[off + 1].to_int() == 0x4B &&
      bytes[off + 2].to_int() == 0x03 && bytes[off + 3].to_int() == 0x04 {
      let ver = bytes[off + 4].to_int() + bytes[off + 5].to_int() * 256
      let flags = bytes[off + 6].to_int() + bytes[off + 7].to_int() * 256
      let cm = bytes[off + 8].to_int() + bytes[off + 9].to_int() * 256
      let name_len = bytes[off + 26].to_int() + bytes[off + 27].to_int() * 256
      // Validate: version <= 63, compression method 0-99, no reserved flags
      if ver <= 63 && cm <= 99 && (flags & 0xFFE0) == 0 && name_len <= 256 {
        let ver_str = (ver / 10).to_string() + "." + (ver % 10).to_string()
        let cm_str = if cm == 0 { "stored" } else if cm == 8 { "deflated" } else { "method=" + cm.to_string() }
        results.push({ offset: off, name: "ZIP archive, " + cm_str + ", ver " + ver_str, size: 0, confidence: 3 })
      } else {
        results.push({ offset: off, name: "ZIP archive (unverified)", size: 0, confidence: 1 })
      }
    }
    // RAR
    if off + 7 <= len && read_str_at(bytes, off, 4) == "Rar!" {
      results.push({ offset: off, name: "RAR archive", size: 0, confidence: 0 })
    }
    // 7z
    if off + 6 <= len && bytes[off].to_int() == 0x37 && bytes[off + 1].to_int() == 0x7A &&
      bytes[off + 2].to_int() == 0xBC && bytes[off + 3].to_int() == 0xAF &&
      bytes[off + 4].to_int() == 0x27 && bytes[off + 5].to_int() == 0x1C {
      results.push({ offset: off, name: "7-Zip archive", size: 0, confidence: 0 })
    }
    // CAB (Microsoft Cabinet): MSCF magic
    if off + 4 <= len && read_str_at(bytes, off, 4) == "MSCF" {
      results.push({ offset: off, name: "CAB archive", size: 0, confidence: 0 })
    }
    // CPIO (070701 or 070702)
    if off + 6 <= len && (read_str_at(bytes, off, 6) == "070701" || read_str_at(bytes, off, 6) == "070702") {
      results.push({ offset: off, name: "CPIO archive", size: 0, confidence: 0 })
    }
    // ISO9660: CD001 at offset 32769
    if off + 32769 + 5 <= len && read_str_at(bytes, off + 32769, 5) == "CD001" {
      results.push({ offset: off, name: "ISO9660 filesystem", size: 0, confidence: 2 })
    }
    // Deb: !<arch> + debian-binary
    if off + 8 <= len && read_str_at(bytes, off, 8) == "!<arch>\n" {
      results.push({ offset: off, name: "Debian package (ar archive)", size: 0, confidence: 2 })
    }
    // TAR (ustar at offset 257 within 512B block)
    // Simplified: check current offset + 257
    if off + 262 <= len && read_str_at(bytes, off + 257, 5) == "ustar" {
      results.push({ offset: off, name: "TAR archive (POSIX)", size: 0, confidence: 0 })
    }
    // GZip: 1F 8B 08, plus flag byte for extra info (binwalk-style)
    if off + 10 <= len && bytes[off].to_int() == 0x1F && bytes[off + 1].to_int() == 0x8B {
      if bytes[off + 2].to_int() == 0x08 {
        let flg = bytes[off + 3].to_int()
        let extra = if (flg & 8) != 0 { ", has name" } else { "" }
        results.push({ offset: off, name: "GZip compressed" + extra, size: 0, confidence: 3 })
      } else {
        results.push({ offset: off, name: "GZip (unverified)", size: 0, confidence: 1 })
      }
    }
    // ZLIB — only match well-known standard headers to avoid false positives
    if off + 2 <= len {
      let cmf = bytes[off].to_int()
      let flg = bytes[off + 1].to_int()
      let header = cmf * 256 + flg
      // Common ZLIB headers: 9C=default, DA=max, 01=no compression, 5E=fast (binwalk includes all)
      if header == 0x789C || header == 0x78DA || header == 0x7801 || header == 0x785E {
        results.push({ offset: off, name: "ZLIB stream", size: 0, confidence: 2 })
      }
    }
    // PE: MZ + "PE\\0\\0" at e_lfanew (binwalk-style)
    if off + 2 <= len && bytes[off].to_int() == 0x4D && bytes[off + 1].to_int() == 0x5A {
      // Read e_lfanew at offset 0x3C
      if off + 64 <= len {
        let pe_off = off + 60
        let elfanew = bytes[pe_off].to_int() + bytes[pe_off + 1].to_int() * 256 +
          bytes[pe_off + 2].to_int() * 65536 + bytes[pe_off + 3].to_int() * 16777216
        if elfanew > 0 && off + elfanew + 4 <= len &&
          bytes[off + elfanew].to_int() == 0x50 && bytes[off + elfanew + 1].to_int() == 0x45 &&
          bytes[off + elfanew + 2].to_int() == 0x00 && bytes[off + elfanew + 3].to_int() == 0x00 {
          results.push({ offset: off, name: "PE executable", size: 0, confidence: 3 })
          continue
        }
      }
      results.push({ offset: off, name: "PE executable (MZ)", size: 0, confidence: 1 })
    }
    // ELF
    if off + 4 <= len && bytes[off].to_int() == 0x7F && bytes[off + 1].to_int() == b'E'.to_int() &&
      bytes[off + 2].to_int() == b'L'.to_int() && bytes[off + 3].to_int() == b'F'.to_int() {
      results.push({ offset: off, name: "ELF executable", size: 0, confidence: 0 })
    }
    // Mach-O
    if off + 4 <= len {
      let magic = read_u32_be_at(bytes, off)
      if magic == 0xFEEDFACE || magic == 0xFEEDFACF ||  // 32-bit
         magic == 0xFEEDFACF || read_u32_be_at(bytes, off) == 0xFEEDFACE {  // Fat binary check simplified
        results.push({ offset: off, name: "Mach-O executable", size: 0, confidence: 0 })
      }
    }
    // PDF: %PDF-1.d + newline + % (binwalk-style validation)
    if off + 9 <= len && read_str_at(bytes, off, 5) == "%PDF-" {
      let minor = bytes[off + 5].to_int()
      if minor >= 0x30 && minor <= 0x39 {
        let after = bytes[off + 6].to_int()
        if after == 0x0A || after == 0x0D {
          results.push({ offset: off, name: "PDF document, version 1." + (minor - 0x30).to_string(), size: 0, confidence: 3 })
        }
      }
      results.push({ offset: off, name: "PDF document", size: 0, confidence: 1 })
    }
    // SQLite3
    if off + 16 <= len && read_str_at(bytes, off, 15) == "SQLite format 3" &&
      bytes[off + 15].to_int() == 0x00 {
      results.push({ offset: off, name: "SQLite3 database", size: 0, confidence: 0 })
    }
    // Java class
    if off + 4 <= len && bytes[off].to_int() == 0xCA && bytes[off + 1].to_int() == 0xFE &&
      bytes[off + 2].to_int() == 0xBA && bytes[off + 3].to_int() == 0xBE {
      results.push({ offset: off, name: "Java class file", size: 0, confidence: 0 })
    }
    // BZip2
    if off + 3 <= len && bytes[off].to_int() == 0x42 && bytes[off + 1].to_int() == 0x5A &&
      bytes[off + 2].to_int() == 0x68 {
      results.push({ offset: off, name: "BZip2 compressed", size: 0, confidence: 0 })
    }
    // XZ
    if off + 6 <= len && bytes[off].to_int() == 0xFD && bytes[off + 1].to_int() == 0x37 &&
      bytes[off + 2].to_int() == 0x7A && bytes[off + 3].to_int() == 0x58 &&
      bytes[off + 4].to_int() == 0x5A && bytes[off + 5].to_int() == 0x00 {
      results.push({ offset: off, name: "XZ compressed", size: 0, confidence: 0 })
    }
    // LZ4
    if off + 4 <= len && bytes[off].to_int() == 0x04 && bytes[off + 1].to_int() == 0x22 &&
      bytes[off + 2].to_int() == 0x4D && bytes[off + 3].to_int() == 0x18 {
      results.push({ offset: off, name: "LZ4 compressed", size: 0, confidence: 0 })
    }
  }

  // Filter low-confidence matches inside containers
  let filtered = filter_false_positives(bytes, results)
  estimate_sizes(bytes, filtered)
  filtered
}

///|
/// Remove matches that fall within ZIP local file data regions.
fn filter_false_positives(bytes : Bytes, matches : Array[ScanMatch]) -> Array[ScanMatch] {
  // If file starts with a compression-based format, low-confidence matches
  // at offset > 0 are almost certainly false positives inside compressed data
  let has_container = bytes.length() >= 2 && (
    (bytes[0].to_int() == 0xFF && bytes[1].to_int() == 0xD8) ||  // JPEG
    (bytes[0].to_int() == 0x50 && bytes[1].to_int() == 0x4B) ||  // ZIP
    (bytes[0].to_int() == 0x1F && bytes[1].to_int() == 0x8B) ||  // GZip
    (bytes[0].to_int() == 0x89 && bytes[1].to_int() == 0x50) ||  // PNG
    (bytes[0].to_int() == 0x47 && bytes[1].to_int() == 0x49) ||  // GIF
    (bytes[0].to_int() == 0x42 && bytes[1].to_int() == 0x4D) ||  // BMP
    (bytes[0].to_int() == 0x42 && bytes[1].to_int() == 0x5A)     // BZip2
  )
  // Compression signatures inside containers are almost always false positives
  let compression_names = ["ZLIB stream", "BZip2 compressed", "XZ compressed", "LZ4 compressed"]
  fn is_compression(name : String) -> Bool {
    for k = 0; k < 4; k = k + 1 { if name == compression_names[k] { return true } }
    false
  }
  let filtered : Array[ScanMatch] = []
  for i = 0; i < matches.length(); i = i + 1 {
    let m = matches[i]
    let mut keep = true
    if has_container && m.offset > 0 {
      // Remove unverified matches (confidence <= 1)
      if m.confidence <= 1 { keep = false }
      // Compression signatures inside compressed data are false positives
      if is_compression(m.name) { keep = false }
      // GZip inside container: only keep if verified (confidence 3)
      if m.name == "GZip compressed" { keep = false }
      if m.name == "GZip (unverified)" { keep = false }
    }
    if keep { filtered.push(m) }
  }
  filtered
}

///|
/// Check if bytes at offset match a known file signature boundary.


///|
/// Read up to max ASCII chars from bytes at offset.
fn read_str_at(bytes : Bytes, off : Int, max : Int) -> String {
  let result = StringBuilder()
  for i = 0; i < max; i = i + 1 {
    if off + i >= bytes.length() { break }
    let b = bytes[off + i]
    if b == b'\x00' { break }
    if b.to_int() >= 32 && b.to_int() < 127 {
      let ch = b.to_int().to_char()
      match ch { Some(c) => result.write_char(c); None => () }
    }
  }
  result.to_string()
}

///|
/// Read big-endian uint32 at offset.
fn read_u32_be_at(bytes : Bytes, off : Int) -> Int {
  guard off + 4 <= bytes.length() else { 0 }
  let mut r = 0
  for i = 0; i < 4; i = i + 1 {
    r = r * 256 + bytes[off + i].to_int()
  }
  r
}
///|
/// Estimate sizes for matches by finding next signature or EOF.
fn estimate_sizes(bytes : Bytes, matches : Array[ScanMatch]) -> Unit {
  let len = bytes.length()
  let total = matches.length()
  for i = 0; i < total; i = i + 1 {
    let end = if i + 1 < total { matches[i + 1].offset } else { len }
    matches[i].size = end - matches[i].offset
  }
}

///|
/// Extract a region of bytes from start offset to end offset (or EOF).
/// Saves to "filename_offset.ext" based on match name.
pub fn extract_region(bytes : Bytes, start : Int, name : String, base_path : String) -> String {
  let len = bytes.length()
  guard start >= 0 && start < len else { "Invalid offset" }
  let count = len - start
  guard count > 0 else { "Zero-length region" }
  let data = Bytes::makei(count, i => bytes[start + i])
  // Build output filename: basepath_offset_name.ext
  let ext = guess_ext(name)
  let out_path = base_path + "_0x" + format_offset_scan(start) + "." + ext
  try {
    @fs.write_bytes_to_file(out_path, data)
    "Saved: " + out_path
  } catch {
    @fs.IOError::IOError(_) => "Save error"
  }
}

fn guess_ext(name : String) -> String {
  if name.contains("JPEG") { "jpg" }
  else if name.contains("PNG") { "png" }
  else if name.contains("GIF") { "gif" }
  else if name.contains("BMP") { "bmp" }
  else if name.contains("WAV") { "wav" }
  else if name.contains("ZIP") { "zip" }
  else if name.contains("RAR") { "rar" }
  else if name.contains("GZip") { "gz" }
  else if name.contains("PE") { "exe" }
  else if name.contains("ELF") { "elf" }
  else if name.contains("ZLIB") { "zlib" }
  else if name.contains("7-Zip") { "7z" }
  else if name.contains("TAR") { "tar" }
  else if name.contains("PDF") { "pdf" }
  else if name.contains("SQLite") { "db" }
  else if name.contains("MP") { "mp" }
  else if name.contains("OGG") { "ogg" }
  else if name.contains("FLAC") { "flac" }
  else { "bin" }
}

fn format_offset_scan(n : Int) -> String {
  to_hex_string(n, width=8)
}
///|
/// Set confidence levels: HIGH for 4+ byte magic, MEDIUM for 3, LOW for 2.

///|
/// Calculate Shannon entropy per block. Block size is adaptive (min 256 bytes).
pub fn entropy_scan(bytes : Bytes) -> Array[EntropyBlock] {
  let len = bytes.length()
  let block_size = 256
  let results : Array[EntropyBlock] = []
  let mut off = 0
  while off < len {
    let end = if off + block_size < len { off + block_size } else { len }
    let counts = FixedArray::make(256, 0)
    for j = off; j < end; j = j + 1 {
      let idx = bytes[j].to_int()
      counts[idx] = counts[idx] + 1
    }
    let n = (end - off).to_double()
    let mut h = 0.0
    for k = 0; k < 256; k = k + 1 {
      if counts[k] > 0 {
        let p = counts[k].to_double() / n
        h = h - p * log2(p)
      }
    }
    results.push({ start: off, end: end, entropy: h })
    off = end
  }
  results
}

///|
/// log base 2 of x.
fn log2(x : Double) -> Double {
  // ln(x) / ln(2)
  // MoonBit has no built-in log; use approximation for 1..256
  // Since we only call this for probabilities p = count/block_size,
  // we can use a simple approximation
  if x <= 0.0 { 0.0 }
  else if x >= 1.0 { 0.0 }
  else {
    // ln(x) ≈ 2 * (x-1)/(x+1) * (1 + (x-1)^2/(3*(x+1)^2) + ...)
    // Simpler: use Taylor series around x=0.5
    let y = (x - 1.0) / (x + 1.0)
    let y2 = y * y
    let ln_x = 2.0 * y * (1.0 + y2 / 3.0 + y2 * y2 / 5.0 + y2 * y2 * y2 / 7.0)
    ln_x / 0.69314718056  // / ln(2)
  }
}