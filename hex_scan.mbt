// Hex Editor — Signature Scanner
// Multi-pattern matching using Aho-Corasick automaton O(n + m + z).
//
// Algorithm: builds a trie from all magic byte patterns, adds failure
// links via BFS, then walks the automaton over input in a single pass.
// Each match triggers per-format validators with confidence scoring.
// Results filtered for false positives inside container formats.

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
    b"\x52\x49\x46\x46",                     // RIFF/WAV/AVI
    b"\x50\x4B\x03\x04",                     // ZIP
    b"\x52\x61\x72\x21",                     // RAR
    b"\x37\x7A\xBC\xAF\x27\x1C",             // 7z
    b"\x1F\x8B",                             // GZip
    b"\x78\x9C", b"\x78\xDA", b"\x78\x01", b"\x78\x5E", // Zlib variants
    b"\x42\x5A\x68",                         // BZip2
    b"\x4D\x5A",                             // PE (exe/dll)
    b"\x7F\x45\x4C\x46",                     // ELF
    b"\x75\x73\x74\x61\x72",                 // TAR (ustar)
    b"\x4F\x67\x67\x53",                     // OGG (OggS)
    b"\x49\x44\x33",                         // MP3 (ID3)
    b"\x66\x4C\x61\x43",                     // FLAC (fLaC)
    b"\x1A\x45\xDF\xA3",                     // WebM (EBML)
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
  // Dedup: suppress compressed-format matches nested inside earlier payloads
  let deduped : Array[ScanMatch] = []
  for i = 0; i < trusted.length(); i = i + 1 {
    let m = trusted[i]
    let is_compressed = m.name.contains("Zlib") || m.name.contains("GZip") || m.name.contains("BZip2")
    let mut nested = false
    if is_compressed {
      for j = 0; j < i; j = j + 1 {
        let prev = trusted[j]
        if m.offset > prev.offset && m.offset < prev.offset + prev.size { nested = true }
      }
    }
    if !nested { deduped.push(m) }
  }
  // Tail detection: boost header confidence when end markers found
  if len >= 2 && bytes[len-2].to_int() == 0xFF && bytes[len-1].to_int() == 0xD9 &&
     bytes[0].to_int() == 0xFF && bytes[1].to_int() == 0xD8 {
    for i = 0; i < deduped.length(); i = i + 1 {
      if deduped[i].name.contains("JPEG") && deduped[i].confidence < 3 { deduped[i].confidence = 3 }
    }
  }
  if len >= 12 && bytes[0].to_int() == 0x89 && bytes[1].to_int() == 0x50 &&
     bytes[len-12].to_int() == 0x00 && bytes[len-11].to_int() == 0x00 && bytes[len-10].to_int() == 0x00 && bytes[len-9].to_int() == 0x00 &&
     bytes[len-8].to_int() == 0x49 && bytes[len-7].to_int() == 0x45 && bytes[len-6].to_int() == 0x4E && bytes[len-5].to_int() == 0x44 {
    for i = 0; i < deduped.length(); i = i + 1 {
      if deduped[i].name.contains("PNG image") && deduped[i].confidence < 3 { deduped[i].confidence = 3 }
    }
  }
  if len >= 3 && read_str(bytes, 0, 3) == "GIF" && bytes[len-1].to_int() == 0x3B {
    for i = 0; i < deduped.length(); i = i + 1 {
      if deduped[i].name.contains("GIF image") && deduped[i].confidence < 3 { deduped[i].confidence = 3 }
    }
  }
  // Trailing data
  if deduped.length() > 0 {
    let last = deduped[deduped.length() - 1]
    let tail_off = last.offset + last.size
    if tail_off > 0 && tail_off + 256 < len {
      deduped.push({ offset: tail_off, name: "Trailing data (" + format_size(len - tail_off) + ")", size: len - tail_off, confidence: 1 })
    }
  }
  deduped
}

///| Each format has a dedicated validator (binwalk-style per-signature parser)
fn validate_jpeg(bytes : Bytes, off : Int, len : Int) -> ScanMatch? {
  guard off + 4 <= len && bytes[off].to_int() == 0xFF && bytes[off + 1].to_int() == 0xD8 && bytes[off + 2].to_int() == 0xFF else { None }
  let marker = bytes[off + 3].to_int()
  guard (marker >= 0xE0 && marker <= 0xEF) || marker == 0xFE || marker == 0xDB || (marker >= 0xC0 && marker <= 0xC4) else { None }
  // Verify JPEG structure: require JFIF/EXIF identifier or valid marker chain
  let end = if off + 300 < len { off + 300 } else { len }
  let mut markers = 0
  let mut pos = off + 2
  while pos + 4 <= end {
    if bytes[pos].to_int() != 0xFF { pos = pos + 1; continue }
    let nm = bytes[pos + 1].to_int()
    if nm == 0x00 { pos = pos + 2; continue }   // escaped FF
    if nm == 0xD9 { break }                       // EOI
    if nm == 0xD8 { pos = pos + 2; continue }     // nested SOI
    // Valid marker: check segment length is sane
    if pos + 4 > end { break }
    let seg_len = bytes[pos + 2].to_int() * 256 + bytes[pos + 3].to_int()
    if seg_len < 2 || pos + 2 + seg_len > len { pos = pos + 2; continue }
    // Count structural markers
    if nm == 0xE0 && seg_len >= 7 &&
       bytes[pos + 4].to_int() == 0x4A && bytes[pos + 5].to_int() == 0x46 &&
       bytes[pos + 6].to_int() == 0x49 && bytes[pos + 7].to_int() == 0x46 { markers = markers + 1 }  // JFIF
    if nm == 0xE1 && seg_len >= 8 &&
       bytes[pos + 4].to_int() == 0x45 && bytes[pos + 5].to_int() == 0x78 &&
       bytes[pos + 6].to_int() == 0x69 && bytes[pos + 7].to_int() == 0x66 { markers = markers + 1 }  // Exif
    if nm == 0xDB || (nm >= 0xC0 && nm <= 0xC2) { markers = markers + 1 }  // DQT or SOF
    if markers >= 1 { break }
    pos = pos + 2 + seg_len
  }
  guard markers >= 1 else { None }
  Some({ offset: off, name: "JPEG image", size: 0, confidence: 3 })
}
fn validate_png(bytes : Bytes, off : Int, len : Int) -> ScanMatch? {
  guard off + 25 <= len && bytes[off].to_int() == 0x89 && bytes[off + 1].to_int() == 0x50 && bytes[off + 2].to_int() == 0x4E && bytes[off + 3].to_int() == 0x47 && bytes[off + 4].to_int() == 0x0D && bytes[off + 5].to_int() == 0x0A && bytes[off + 6].to_int() == 0x1A && bytes[off + 7].to_int() == 0x0A else { None }
  guard read_u32_be(bytes, off + 8) == 0x0D && read_str(bytes, off + 12, 4) == "IHDR" else { None }
  let w = read_u32_be(bytes, off + 16); let h = read_u32_be(bytes, off + 20)
  // Validate IHDR: color type and bit depth must be a valid combination
  let bpp = bytes[off + 24].to_int()
  let color_type = bytes[off + 25].to_int()
  let valid_bpp_ct = match color_type {
    0 => bpp == 1 || bpp == 2 || bpp == 4 || bpp == 8 || bpp == 16
    2 => bpp == 8 || bpp == 16
    3 => bpp == 1 || bpp == 2 || bpp == 4 || bpp == 8
    4 => bpp == 8 || bpp == 16
    6 => bpp == 8 || bpp == 16
    _ => false
  }
  guard valid_bpp_ct else { None }
  Some({ offset: off, name: "PNG image, " + w.to_string() + " x " + h.to_string(), size: 0, confidence: 3 })
}
fn validate_gif(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 6 <= _len && (read_str(bytes, off, 6) == "GIF87a" || read_str(bytes, off, 6) == "GIF89a") else { None }
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
  guard off + 12 <= _len && read_str(bytes, off, 4) == "RIFF" else { None }
  let fcc = read_str(bytes, off + 8, 4)
  if fcc == "WAVE" { return Some({ offset: off, name: "WAV audio", size: 0, confidence: 2 }) }
  if fcc == "AVI " { return Some({ offset: off, name: "AVI video", size: 0, confidence: 2 }) }
  None
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
  guard off + 7 <= _len && read_str(bytes, off, 4) == "Rar!" else { None }
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
  // RFC 1950 FCHECK: (CMF*256+FLG) % 31 == 0, compression method must be deflate (8)
  let cmf = bytes[off].to_int()
  let flg = bytes[off + 1].to_int()
  guard cmf % 16 == 8 && (cmf * 256 + flg) % 31 == 0 else { None }
  let flevel = (flg / 64) % 4
  let level_str = if flevel == 0 { "fastest" } else if flevel == 1 { "fast" } else if flevel == 2 { "default" } else { "best" }
  Some({ offset: off, name: "Zlib compressed data, " + level_str + " compression", size: 0, confidence: 3 })
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

fn validate_tar(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  // ustar magic at offset 257 from block start; check alignment + full magic
  guard off >= 257 && (off - 257) % 512 == 0 && off + 6 <= _len else { None }
  guard read_str(bytes, off, 5) == "ustar" && (bytes[off+5].to_int() == 0x00 || bytes[off+5].to_int() == 0x20) else { None }
  Some({ offset: off - 257, name: "TAR archive", size: 0, confidence: 3 })
}

fn validate_ogg(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 4 <= _len && read_str(bytes, off, 4) == "OggS" else { None }
  Some({ offset: off, name: "OGG audio", size: 0, confidence: 3 })
}
fn validate_mp3(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 10 <= _len && read_str(bytes, off, 3) == "ID3" else { None }
  // Validate ID3v2 header: version (2.2, 2.3, 2.4), flags, syncsafe size
  let ver_major = bytes[off + 3].to_int()
  let ver_minor = bytes[off + 4].to_int()
  guard ver_major >= 2 && ver_major <= 4 && ver_minor <= 255 else { None }
  let flags = bytes[off + 5].to_int()
  guard flags % 16 == 0 else { None }  // low 4 bits must be 0
  // Syncsafe size: each byte uses 7 bits, highest bit must be 0
  let mut syncsafe_ok = true
  for i = 6; i < 10; i = i + 1 {
    if bytes[off + i].to_int() > 0x7F { syncsafe_ok = false }
  }
  guard syncsafe_ok else { None }
  Some({ offset: off, name: "MP3 audio (ID3v2.\{ver_major})", size: 0, confidence: 3 })
}
fn validate_flac(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 4 <= _len && read_str(bytes, off, 4) == "fLaC" else { None }
  Some({ offset: off, name: "FLAC audio", size: 0, confidence: 3 })
}
fn validate_webm(bytes : Bytes, off : Int, _len : Int) -> ScanMatch? {
  guard off + 4 <= _len && bytes[off].to_int() == 0x1A && bytes[off + 1].to_int() == 0x45 && bytes[off + 2].to_int() == 0xDF && bytes[off + 3].to_int() == 0xA3 else { None }
  Some({ offset: off, name: "WebM/Matroska", size: 0, confidence: 3 })
}

fn check_sigs(bytes : Bytes, off : Int, len : Int, results : Array[ScanMatch]) -> Unit {
  let parsers = [
    validate_jpeg, validate_png, validate_gif, validate_bmp,
    validate_wav,
    validate_zip, validate_rar, validate_7z,
    validate_gzip, validate_zlib, validate_bzip2,
    validate_pe, validate_elf,
    validate_tar,
    validate_ogg, validate_mp3, validate_flac, validate_webm,
  ]
  for i = 0; i < parsers.length(); i = i + 1 {
    match parsers[i](bytes, off, len) { Some(m) => results.push(m); None => () }
  }
}

///| Filter false positives inside containers
fn filter_false_positives(bytes : Bytes, matches : Array[ScanMatch]) -> Array[ScanMatch] {
  let is_container = bytes.length() >= 4 && (
    (bytes[0].to_int() == 0x42 && bytes[1].to_int() == 0x4D) ||  // BMP
    (bytes[0].to_int() == 0xFF && bytes[1].to_int() == 0xD8) ||  // JPEG
    (bytes[0].to_int() == 0x50 && bytes[1].to_int() == 0x4B) ||  // ZIP
    (bytes[0].to_int() == 0x89 && bytes[1].to_int() == 0x50) ||  // PNG
    (bytes[0].to_int() == 0x1F && bytes[1].to_int() == 0x8B) ||  // GZip
    (bytes[0].to_int() == 0x4D && bytes[1].to_int() == 0x5A) ||  // PE
    (read_str(bytes, 0, 4) == "Rar!") ||                        // RAR
    (bytes[0].to_int() == 0x37 && bytes[1].to_int() == 0x7A) ||     // 7z
    (read_str(bytes, 257, 5) == "ustar") ||                      // TAR
    (read_str(bytes, 0, 4) == "OggS") ||                         // OGG
    (read_str(bytes, 0, 4) == "fLaC") ||                         // FLAC
    (read_str(bytes, 0, 6) == "GIF87a" || read_str(bytes, 0, 6) == "GIF89a") || // GIF
    (read_str(bytes, 0, 3) == "ID3") ||                          // MP3
    (bytes[0].to_int() == 0x1A && bytes[1].to_int() == 0x45) ||     // WebM/EBML
    (read_str(bytes, 0, 4) == "RIFF")                            // WAV/AVI
  )
  // MP4: check ftyp box at offset 4
  let is_mp4 = bytes.length() >= 12 && read_u32_be(bytes, 4) == 0x66747970
  let has_container = is_container || is_mp4
  fn is_fp(m : ScanMatch) -> Bool {
    m.confidence <= 1 || m.name.contains("PE executable (MZ)") ||
    m.name.contains("Zlib") || m.name.contains("GZip") || m.name.contains("BZip2")
  }
  let filtered : Array[ScanMatch] = []
  for i = 0; i < matches.length(); i = i + 1 {
    let m = matches[i]
    if !(has_container && m.offset > 0 && is_fp(m)) { filtered.push(m) }
  }
  filtered
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
