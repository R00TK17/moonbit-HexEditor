// Binary signature scanner — CTF steganography focused

///|
pub struct ScanMatch {
  offset : Int
  name : String
  mut size : Int
  mut confidence : Int
} derive(Debug)

///|
/// Aho-Corasick automaton for multi-pattern matching
priv struct AcNode {
  next : FixedArray[Int]    // transition to child node
  mut fail : Int            // failure link
  mut pat_idx : Int         // pattern index, -1 = no output
}
priv struct AcPattern { bytes : Bytes }

fn build_ac(patterns : Array[Bytes]) -> (Array[AcNode], Array[AcPattern]) {
  let nodes : Array[AcNode] = []
  // Root node
  nodes.push({ next: FixedArray::make(256, -1), fail: 0, pat_idx: -1 })
  let ac_pats : Array[AcPattern] = []
  // Build trie
  for pi = 0; pi < patterns.length(); pi = pi + 1 {
    let pat = patterns[pi]; let mut n = 0
    for j = 0; j < pat.length(); j = j + 1 {
      let b = pat[j].to_int()
      if nodes[n].next[b] == -1 {
        nodes[n].next[b] = nodes.length()
        nodes.push({ next: FixedArray::make(256, -1), fail: 0, pat_idx: -1 })
      }
      n = nodes[n].next[b]
    }
    nodes[n].pat_idx = ac_pats.length()
    ac_pats.push({ bytes: pat })
  }
  // Build failure links (BFS)
  let queue : Array[Int] = []
  // Level 1
  for b = 0; b < 256; b = b + 1 {
    let child = nodes[0].next[b]
    if child != -1 { nodes[child].fail = 0; queue.push(child) }
    else { nodes[0].next[b] = 0 }
  }
  let mut qi = 0
  while qi < queue.length() {
    let v = queue[qi]; qi = qi + 1
    // If v has output, propagate output via fail link
    let f = nodes[v].fail
    if nodes[f].pat_idx != -1 && nodes[v].pat_idx == -1 { nodes[v].pat_idx = nodes[f].pat_idx }
    for b = 0; b < 256; b = b + 1 {
      let child = nodes[v].next[b]
      if child != -1 {
        nodes[child].fail = nodes[f].next[b]
        queue.push(child)
      } else {
        nodes[v].next[b] = nodes[f].next[b]
      }
    }
  }
  (nodes, ac_pats)
}

pub fn scan_signatures(bytes : Bytes) -> Array[ScanMatch] {
  let len = bytes.length()
  let results : Array[ScanMatch] = []

  // Collect magic patterns from validators
  let magics = [
    b"\xFF\xD8\xFF",                         // JPEG
    b"\x89\x50\x4E\x47",                     // PNG
    b"\x47\x49\x46\x38",                     // GIF
    b"\x42\x4D",                             // BMP
    b"\x52\x49\x46\x46",                     // RIFF/WAV
    b"\x50\x4B\x03\x04",                     // ZIP
    b"\x52\x61\x72\x21",                     // RAR
    b"\x37\x7A\xBC\xAF\x27\x1C",             // 7z
    b"\x1F\x8B",                             // GZip
    b"\x78\x9C", b"\x78\xDA", b"\x78\x01", b"\x78\x5E", // Zlib variants
    b"\x42\x5A\x68",                         // BZip2
    b"\x4D\x5A",                             // PE (exe/dll)
    b"\x7F\x45\x4C\x46",                     // ELF
    b"\x25\x50\x44\x46",                     // PDF
    b"\x3C\x3F\x78\x6D",                     // XML
    b"\x2D\x2D\x2D\x2D",                     // PEM
    b"\x53\x61\x6C\x74\x65\x64\x5F\x5F",     // OpenSSL
    b"\x53\x51\x4C\x69",                     // SQLite
    b"\x4C\x55\x4B\x53",                     // LUKS
    b"\xA3\x01",                             // GPG
    b"\x75\x73\x74\x61\x72",                 // TAR (ustar)
  ]
  let (nodes, ac_pats) = build_ac(magics)

  // Walk AC automaton through data
  let mut state = 0
  let mut off = 0
  while off < len && results.length() < 2000 {
    let b = bytes[off].to_int()
    state = nodes[state].next[b]
    if nodes[state].pat_idx != -1 {
      let pi = nodes[state].pat_idx
      if pi < ac_pats.length() {
        let p = ac_pats[pi]
        let match_off = off - p.bytes.length() + 1
        if match_off >= 0 { check_sigs(bytes, match_off, len, results) }
      }
      // Follow fail links for additional patterns
      let mut fs = nodes[state].fail
      while nodes[fs].pat_idx != -1 {
        let fpi = nodes[fs].pat_idx
        if fpi < ac_pats.length() {
          let fp = ac_pats[fpi]
          let fmatch_off = off - fp.bytes.length() + 1
          if fmatch_off >= 0 { check_sigs(bytes, fmatch_off, len, results) }
        }
        fs = nodes[fs].fail
      }
    }
    off = off + 1
  }

  let filtered = filter_false_positives(bytes, results)
  let trusted : Array[ScanMatch] = []
  for i = 0; i < filtered.length(); i = i + 1 {
    if filtered[i].confidence >= 2 { trusted.push(filtered[i]) }
  }
  estimate_sizes(bytes, trusted)
  // Tail detection: boost header confidence when end markers found
  if len >= 2 && bytes[len-2].to_int() == 0xFF && bytes[len-1].to_int() == 0xD9 &&
     bytes[0].to_int() == 0xFF && bytes[1].to_int() == 0xD8 {
    for i = 0; i < trusted.length(); i = i + 1 {
      if trusted[i].name.contains("JPEG") && trusted[i].confidence < 3 { trusted[i].confidence = 3 }
    }
  }
  if len >= 12 && bytes[0].to_int() == 0x89 && bytes[1].to_int() == 0x50 &&
     bytes[len-12].to_int() == 0x00 && bytes[len-11].to_int() == 0x00 && bytes[len-10].to_int() == 0x00 && bytes[len-9].to_int() == 0x00 &&
     bytes[len-8].to_int() == 0x49 && bytes[len-7].to_int() == 0x45 && bytes[len-6].to_int() == 0x4E && bytes[len-5].to_int() == 0x44 {
    for i = 0; i < trusted.length(); i = i + 1 {
      if trusted[i].name.contains("PNG image") && trusted[i].confidence < 3 { trusted[i].confidence = 3 }
    }
  }
  if len >= 3 && read_str_at(bytes, 0, 3) == "GIF" && bytes[len-1].to_int() == 0x3B {
    for i = 0; i < trusted.length(); i = i + 1 {
      if trusted[i].name.contains("GIF image") && trusted[i].confidence < 3 { trusted[i].confidence = 3 }
    }
  }
  // Trailing data
  if trusted.length() > 0 {
    let last = trusted[trusted.length() - 1]
    let tail_off = last.offset + last.size
    if tail_off > 0 && tail_off + 256 < len {
      trusted.push({ offset: tail_off, name: "Trailing data (" + format_size(len - tail_off) + ")", size: len - tail_off, confidence: 1 })
    }
  }
  trusted
}

///| Each format has a dedicated validator (binwalk-style per-signature parser)
fn validate_jpeg(bytes : Bytes, off : Int, len : Int) -> ScanMatch? {
  guard off + 4 <= len && bytes[off].to_int() == 0xFF && bytes[off + 1].to_int() == 0xD8 && bytes[off + 2].to_int() == 0xFF else { None }
  let marker = bytes[off + 3].to_int()
  guard (marker >= 0xE0 && marker <= 0xEF) || marker == 0xFE || marker == 0xDB || (marker >= 0xC0 && marker <= 0xC4) else { None }
  Some({ offset: off, name: "JPEG image", size: 0, confidence: 2 })
}
fn validate_png(bytes : Bytes, off : Int, len : Int) -> ScanMatch? {
  guard off + 25 <= len && bytes[off].to_int() == 0x89 && bytes[off + 1].to_int() == 0x50 && bytes[off + 2].to_int() == 0x4E && bytes[off + 3].to_int() == 0x47 && bytes[off + 4].to_int() == 0x0D && bytes[off + 5].to_int() == 0x0A && bytes[off + 6].to_int() == 0x1A && bytes[off + 7].to_int() == 0x0A else { None }
  guard read_u32_be_at(bytes, off + 8) == 0x0D && read_str_at(bytes, off + 12, 4) == "IHDR" else { None }
  let w = read_u32_be_at(bytes, off + 16); let h = read_u32_be_at(bytes, off + 20)
  Some({ offset: off, name: "PNG image, " + w.to_string() + " x " + h.to_string(), size: 0, confidence: 3 })
}
fn validate_gif(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 6 <= _len && (read_str_at(bytes, off, 6) == "GIF87a" || read_str_at(bytes, off, 6) == "GIF89a") else { None }
  Some({ offset: off, name: "GIF image", size: 0, confidence: 3 })
}
fn validate_bmp(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 30 <= _len && bytes[off].to_int() == 0x42 && bytes[off + 1].to_int() == 0x4D else { None }
  let hdr_size = bytes[off+14].to_int() + bytes[off+15].to_int() * 256 + bytes[off+16].to_int() * 65536 + bytes[off+17].to_int() * 16777216
  let planes = bytes[off+26].to_int() + bytes[off+27].to_int() * 256
  let bpp = bytes[off+28].to_int() + bytes[off+29].to_int() * 256
  guard hdr_size >= 12 && hdr_size <= 256 else { None }
  guard planes == 1 && bpp > 0 && bpp <= 32 else { None }
  Some({ offset: off, name: "BMP image", size: 0, confidence: 3 })
}
fn validate_wav(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 12 <= _len && read_str_at(bytes, off, 4) == "RIFF" && read_str_at(bytes, off + 8, 4) == "WAVE" else { None }
  Some({ offset: off, name: "WAV audio", size: 0, confidence: 2 })
}

fn validate_zip(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 30 <= _len && bytes[off].to_int() == 0x50 && bytes[off + 1].to_int() == 0x4B && bytes[off + 2].to_int() == 0x03 && bytes[off + 3].to_int() == 0x04 else { None }
  let ver = bytes[off + 4].to_int() + bytes[off + 5].to_int() * 256
  let flags = bytes[off + 6].to_int() + bytes[off + 7].to_int() * 256
  let cm = bytes[off + 8].to_int() + bytes[off + 9].to_int() * 256
  let name_len = bytes[off + 26].to_int() + bytes[off + 27].to_int() * 256
  if ver <= 63 && cm <= 99 && (flags & 0xFFE0) == 0 && name_len <= 256 {
    let cm_str = if cm == 0 { "stored" } else if cm == 8 { "deflated" } else { "method=" + cm.to_string() }
    Some({ offset: off, name: "ZIP archive, " + cm_str, size: 0, confidence: 3 })
  } else { Some({ offset: off, name: "ZIP archive (unverified)", size: 0, confidence: 1 }) }
}
fn validate_rar(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 7 <= _len && read_str_at(bytes, off, 4) == "Rar!" else { None }
  Some({ offset: off, name: "RAR archive", size: 0, confidence: 3 })
}
fn validate_7z(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 6 <= _len && bytes[off].to_int() == 0x37 && bytes[off + 1].to_int() == 0x7A && bytes[off + 2].to_int() == 0xBC && bytes[off + 3].to_int() == 0xAF && bytes[off + 4].to_int() == 0x27 && bytes[off + 5].to_int() == 0x1C else { None }
  Some({ offset: off, name: "7-Zip archive", size: 0, confidence: 3 })
}

fn validate_gzip(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 10 <= _len && bytes[off].to_int() == 0x1F && bytes[off + 1].to_int() == 0x8B else { None }
  if bytes[off + 2].to_int() == 0x08 {
    let flg = bytes[off + 3].to_int(); let extra = if (flg & 8) != 0 { ", has name" } else { "" }
    Some({ offset: off, name: "GZip compressed" + extra, size: 0, confidence: 3 })
  } else { Some({ offset: off, name: "GZip (unverified)", size: 0, confidence: 1 }) }
}
fn validate_zlib(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 2 <= _len else { None }
  let header = bytes[off].to_int() * 256 + bytes[off + 1].to_int()
  guard header == 0x789C || header == 0x78DA || header == 0x7801 || header == 0x785E else { None }
  let flevel = (bytes[off + 1].to_int() >> 6) & 3
  let level_str = if flevel == 0 { "fastest" } else if flevel == 1 { "fast" } else if flevel == 2 { "default" } else { "best" }
  Some({ offset: off, name: "Zlib compressed data, " + level_str + " compression", size: 0, confidence: 2 })
}
fn validate_bzip2(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 4 <= _len && bytes[off].to_int() == 0x42 && bytes[off + 1].to_int() == 0x5A && bytes[off + 2].to_int() == 0x68 else { None }
  let level = bytes[off + 3].to_int()
  if level >= 0x31 && level <= 0x39 { Some({ offset: off, name: "BZip2 compressed, level " + (level - 0x30).to_string(), size: 0, confidence: 3 }) }
  else { Some({ offset: off, name: "BZip2 (unverified)", size: 0, confidence: 1 }) }
}

fn validate_pe(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 64 <= _len && bytes[off].to_int() == 0x4D && bytes[off + 1].to_int() == 0x5A else { None }
  let elfanew = bytes[off + 60].to_int() + bytes[off + 61].to_int() * 256 + bytes[off + 62].to_int() * 65536 + bytes[off + 63].to_int() * 16777216
  if elfanew > 0 && off + elfanew + 4 <= _len && bytes[off + elfanew].to_int() == 0x50 && bytes[off + elfanew + 1].to_int() == 0x45 && bytes[off + elfanew + 2].to_int() == 0x00 && bytes[off + elfanew + 3].to_int() == 0x00 {
    Some({ offset: off, name: "PE executable", size: 0, confidence: 3 })
  } else { Some({ offset: off, name: "PE executable (MZ)", size: 0, confidence: 1 }) }
}
fn validate_elf(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 4 <= _len && bytes[off].to_int() == 0x7F && bytes[off + 1].to_int() == 0x45 && bytes[off + 2].to_int() == 0x4C && bytes[off + 3].to_int() == 0x46 else { None }
  Some({ offset: off, name: "ELF executable", size: 0, confidence: 3 })
}

fn validate_pdf(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 9 <= _len && read_str_at(bytes, off, 5) == "%PDF-" else { None }
  let minor = bytes[off + 5].to_int()
  if minor >= 0x30 && minor <= 0x39 && (bytes[off + 6].to_int() == 0x0A || bytes[off + 6].to_int() == 0x0D) {
    Some({ offset: off, name: "PDF document, version 1." + (minor - 0x30).to_string(), size: 0, confidence: 3 })
  } else { Some({ offset: off, name: "PDF document", size: 0, confidence: 1 }) }
}
fn validate_xml(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 5 <= _len && read_str_at(bytes, off, 5) == "<?xml" else { None }
  Some({ offset: off, name: "XML document", size: 0, confidence: 2 })
}
fn validate_openssl(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 8 <= _len && read_str_at(bytes, off, 8) == "Salted__" else { None }
  Some({ offset: off, name: "OpenSSL encrypted", size: 0, confidence: 2 })
}
fn validate_pem(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 11 <= _len && read_str_at(bytes, off, 11) == "-----BEGIN " else { None }
  Some({ offset: off, name: "PEM certificate/key", size: 0, confidence: 3 })
}
fn validate_luks(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 6 <= _len && read_str_at(bytes, off, 4) == "LUKS" && bytes[off + 4].to_int() == 0xBA && bytes[off + 5].to_int() == 0xBE else { None }
  Some({ offset: off, name: "LUKS encryption header", size: 0, confidence: 3 })
}
fn validate_tar(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  // ustar magic at offset 257 from block start; check alignment + full magic
  guard off >= 257 && (off - 257) % 512 == 0 && off + 6 <= _len else { None }
  guard read_str_at(bytes, off, 5) == "ustar" && (bytes[off+5].to_int() == 0x00 || bytes[off+5].to_int() == 0x20) else { None }
  Some({ offset: off - 257, name: "TAR archive", size: 0, confidence: 3 })
}

fn validate_gpg(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off == 0 && off + 2 <= _len && bytes[off].to_int() == 0xA3 && bytes[off + 1].to_int() == 0x01 else { None }
  Some({ offset: off, name: "GPG signed data", size: 0, confidence: 2 })
}
fn validate_sqlite(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 16 <= _len && read_str_at(bytes, off, 15) == "SQLite format 3" && bytes[off + 15].to_int() == 0x00 else { None }
  Some({ offset: off, name: "SQLite3 database", size: 0, confidence: 3 })
}

fn check_sigs(bytes : Bytes, off : Int, len : Int, results : Array[ScanMatch]) -> Unit {
  let parsers = [
    validate_jpeg, validate_png, validate_gif, validate_bmp,
    validate_wav,
    validate_zip, validate_rar, validate_7z,
    validate_gzip, validate_zlib, validate_bzip2,
    validate_pe, validate_elf,
    validate_pdf, validate_xml,
    validate_openssl, validate_pem, validate_luks, validate_gpg, validate_tar,
    validate_sqlite,
  ]
  for i = 0; i < parsers.length(); i = i + 1 {
    match parsers[i](bytes, off, len) { Some(m) => results.push(m); None => () }
  }
}

///| Filter false positives inside containers
fn filter_false_positives(bytes : Bytes, matches : Array[ScanMatch]) -> Array[ScanMatch] {
  let has_container = bytes.length() >= 4 && (
    (bytes[0].to_int() == 0x42 && bytes[1].to_int() == 0x4D) ||  // BMP
    (bytes[0].to_int() == 0xFF && bytes[1].to_int() == 0xD8) ||  // JPEG
    (bytes[0].to_int() == 0x50 && bytes[1].to_int() == 0x4B) ||  // ZIP
    (bytes[0].to_int() == 0x89 && bytes[1].to_int() == 0x50) ||  // PNG
    (bytes[0].to_int() == 0x1F && bytes[1].to_int() == 0x8B) ||  // GZip
    (bytes[0].to_int() == 0x4D && bytes[1].to_int() == 0x5A) ||  // PE
    (read_str_at(bytes, 0, 4) == "Rar!") ||                        // RAR
    (bytes[0].to_int() == 0x37 && bytes[1].to_int() == 0x7A) ||     // 7z
    (read_str_at(bytes, 257, 5) == "ustar")                          // TAR
  )
  fn is_fp(m : ScanMatch) -> Bool {
    m.confidence <= 1 ||
    m.name.contains("Zlib") || m.name.contains("GZip") || m.name.contains("BZip2") ||
    m.name.contains("PE executable (MZ)")
  }
  let filtered : Array[ScanMatch] = []
  for i = 0; i < matches.length(); i = i + 1 {
    let m = matches[i]
    if !(has_container && m.offset > 0 && is_fp(m)) { filtered.push(m) }
  }
  filtered
}

// === Utilities ===
fn read_str_at(bytes : Bytes, off : Int, max : Int) -> String {
  let result = StringBuilder()
  for i = 0; i < max; i = i + 1 {
    if off + i >= bytes.length() { break }
    let b = bytes[off + i]
    if b == b'\x00' { break }
    if b.to_int() >= 32 && b.to_int() < 127 { match b.to_int().to_char() { Some(c) => result.write_char(c); None => () } }
  }
  result.to_string()
}

fn read_u32_be_at(bytes : Bytes, off : Int) -> Int {
  guard off + 4 <= bytes.length() else { 0 }
  let mut r = 0
  for i = 0; i < 4; i = i + 1 { r = r * 256 + bytes[off + i].to_int() }
  r
}

fn estimate_sizes(bytes : Bytes, matches : Array[ScanMatch]) -> Unit {
  let len = bytes.length(); let total = matches.length()
  for i = 0; i < total; i = i + 1 {
    let end = if i + 1 < total { matches[i + 1].offset } else { len }
    matches[i].size = end - matches[i].offset
  }
}

pub fn extract_region(bytes : Bytes, start : Int, name : String, base_path : String) -> String {
  let len = bytes.length()
  guard start >= 0 && start < len else { "Invalid offset" }
  let count = len - start
  guard count > 0 else { "Zero-length region" }
  let data = Bytes::makei(count, i => bytes[start + i])
  let ext = guess_ext(name)
  let out_path = base_path + "_0x" + to_hex_string(start, width=8) + "." + ext
  try { @fs.write_bytes_to_file(out_path, data); "Saved: " + out_path } catch { @fs.IOError::IOError(_) => "Save error" }
}

fn guess_ext(name : String) -> String {
  if name.contains("JPEG") { "jpg" } else if name.contains("PNG") { "png" } else if name.contains("GIF") { "gif" }
  else if name.contains("BMP") { "bmp" } else if name.contains("WAV") { "wav" }
  else if name.contains("ZIP") { "zip" } else if name.contains("RAR") { "rar" } else if name.contains("7-Zip") { "7z" }
  else if name.contains("GZip") { "gz" } else if name.contains("Zlib") { "zlib" }
  else if name.contains("PE") { "exe" } else if name.contains("ELF") { "elf" }
  else if name.contains("PDF") { "pdf" } else if name.contains("SQLite") { "db" }
  else { "bin" }
}
