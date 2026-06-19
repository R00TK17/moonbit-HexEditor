// Hex Editor — Search Functionality
// Three-tier search strategy:
//   1. Exact match: Boyer-Moore-Horspool O(n/m) average
//   2. Wildcard (??) patterns ≤62 bytes: Shift-Or bit-parallel O(n)
//   3. Multi-segment (*) patterns: greedy segment matching with 4KB gap limit
//
// Supports hex patterns (FF ?? 00 * AB) and text patterns (He?lo, He*ld, \?).

///|
/// Build BMH bad-character skip table. pattern.length() bytes.
fn bmh_skip(pattern : Bytes) -> FixedArray[Int] {
  let m = pattern.length()
  let skip = FixedArray::make(256, m)
  for j = 0; j < m - 1; j = j + 1 {
    skip[pattern[j].to_int()] = m - 1 - j
  }
  skip
}

///|
/// Boyer-Moore-Horspool search — all occurrences.
pub fn find_all_bytes(data : Bytes, pattern : Bytes) -> Array[Int] {
  let n = data.length()
  let m = pattern.length()
  let results = []
  guard m > 0 else { return results }
  guard m <= n else { return results }
  let skip = bmh_skip(pattern)
  let mut i = 0
  while i <= n - m {
    let mut j = m - 1
    while j >= 0 && data[i + j] == pattern[j] { j = j - 1 }
    if j < 0 { results.push(i) }
    i = i + skip[data[i + m - 1].to_int()]
  }
  results
}

///|
/// Parses a hex string like "FF 00 AB" into a Bytes sequence.
pub fn parse_hex_string(hex_str : String) -> Bytes? {
  // Extract only hex digits
  let digits : Array[Char] = []
  for i = 0; i < hex_str.length(); i = i + 1 {
    let ch = hex_str.get_char(i).unwrap()
    if is_hex_digit(ch) {
      digits.push(ch)
    }
  }

  let digit_count = digits.length()
  guard digit_count > 0 && digit_count % 2 == 0 else { None }

  let byte_count = digit_count / 2
  let result = Bytes::makei(byte_count, i => {
    let hi = hex_char_to_int(digits[i * 2])
    let lo = hex_char_to_int(digits[i * 2 + 1])
    ((hi << 4) | lo).to_byte()
  })
  Some(result)
}

///|
/// Checks if a character is a valid hex digit (0-9, a-f, A-F).
fn is_hex_digit(ch : Char) -> Bool {
  let c = ch.to_int()
  (c >= '0'.to_int() && c <= '9'.to_int()) ||
  (c >= 'A'.to_int() && c <= 'F'.to_int()) ||
  (c >= 'a'.to_int() && c <= 'f'.to_int())
}

///|
/// Converts a hex character to its integer value.
fn hex_char_to_int(ch : Char) -> Int {
  let c = ch.to_int()
  if c >= '0'.to_int() && c <= '9'.to_int() {
    c - '0'.to_int()
  } else if c >= 'A'.to_int() && c <= 'F'.to_int() {
    c - 'A'.to_int() + 10
  } else {
    c - 'a'.to_int() + 10
  }
}

// ========== Wildcard Hex Pattern Search ==========

///|
/// Parse a single pattern token: "FF" → byte, "??" → -1, "*" → -2.
fn parse_token(tok : String) -> Int? {
  if tok == "??" || tok == "?" { return Some(-1) }
  if tok == "*" { return Some(-2) }
  if tok.length() == 2 {
    let c0 = tok.get_char(0).unwrap()
    let c1 = tok.get_char(1).unwrap()
    if is_hex_digit(c0) && is_hex_digit(c1) {
      return Some((hex_char_to_int(c0) << 4) | hex_char_to_int(c1))
    }
  }
  None
}

///|
/// Process a token and push results. Handles *N expansion (e.g. *5 → 5 wildcards).
fn push_tok(tokens : Array[Int], tok : String) -> Bool {
  if tok.length() > 1 && tok.get_char(0).unwrap() == '*' {
    let mut all_digits = true
    let mut n = 0
    for i = 1; i < tok.length(); i = i + 1 {
      let c = tok.get_char(i).unwrap().to_int()
      let d = c - 0x30
      if d < 0 || d > 9 { all_digits = false; break }
      n = n * 10 + d
    }
    if all_digits && n > 0 {
      for _j = 0; _j < n; _j = _j + 1 { tokens.push(-1) }
      return true
    }
  }
  match parse_token(tok) { Some(v) => { tokens.push(v); true }; None => false }
}

///|
/// Parse "A0 ?? B2 * FF" → [0xA0, -1, 0xB2, -2, 0xFF]. *N expands to N wildcards.
fn parse_pattern_tokens(pattern : String) -> Array[Int]? {
  let tokens : Array[Int] = []
  let len = pattern.length()
  let mut sb = StringBuilder()
  for i = 0; i < len; i = i + 1 {
    let ch = pattern.get_char(i).unwrap()
    if ch == ' ' || ch == '\t' {
      let tok = sb.to_string()
      if tok.length() > 0 {
        if !push_tok(tokens, tok) { return None }
        sb = StringBuilder()
      }
    } else {
      sb.write_char(ch)
    }
  }
  let last = sb.to_string()
  if last.length() > 0 {
    if !push_tok(tokens, last) { return None }
  }
  if tokens.length() == 0 { return None }
  // Merge consecutive * tokens
  let merged : Array[Int] = []
  for i = 0; i < tokens.length(); i = i + 1 {
    if tokens[i] == -2 && merged.length() > 0 && merged[merged.length() - 1] == -2 {
      continue
    }
    merged.push(tokens[i])
  }
  if merged.length() == 1 && merged[0] == -2 { return None }
  Some(merged)
}

///|
/// Match a segment (no * tokens, may have ?? = -1) against data at offset.
fn match_seg(data : Bytes, offset : Int, seg : Array[Int]) -> Bool {
  let seg_len = seg.length()
  if offset + seg_len > data.length() { return false }
  for i = 0; i < seg_len; i = i + 1 {
    if seg[i] != -1 && data[offset + i].to_int() != seg[i] { return false }
  }
  true
}

///|
/// Split tokens by * (-2) into segments. Empty segments removed.
fn split_by_star(tokens : Array[Int]) -> Array[Array[Int]] {
  let segments : Array[Array[Int]] = []
  let cur : Array[Int] = []
  for i = 0; i < tokens.length(); i = i + 1 {
    if tokens[i] == -2 {
      if cur.length() > 0 { segments.push(cur.copy()); cur.clear() }
    } else {
      cur.push(tokens[i])
    }
  }
  if cur.length() > 0 { segments.push(cur) }
  segments
}

///|
/// Core search: find all matches of token pattern in data.
/// Tokens: 0-255 = byte, -1 = single wildcard, -2 = multi wildcard (*).
fn search_with_tokens(data : Bytes, tokens : Array[Int]) -> (Array[Int], Array[Int]) {
  let has_star = tokens.contains(-2)
  let has_wild = tokens.contains(-1)

  if !has_star && !has_wild {
    let bytes = Bytes::makei(tokens.length(), fn(i) { tokens[i].to_byte() })
    let offsets = find_all_bytes(data, bytes)
    let lens : Array[Int] = []
    for _i = 0; _i < offsets.length(); _i = _i + 1 { lens.push(bytes.length()) }
    return (offsets, lens)
  }

  // Patterns with ?? wildcards only (no *): Shift-Or bit-parallel O(n)
  //
  // Shift-Or algorithm:
  //   - mask[byte]: bit i is 0 if pattern[i] matches this byte value
  //   - state register: bit i is 0 if first i+1 chars of pattern match
  //   - Per byte: state = (state << 1) | mask[byte]
  //   - Match when bit (m-1) is 0
  //
  // For ?? wildcards: mask[c] has bit i cleared for ALL 256 byte values
  // For concrete bytes: mask[c] has bit i cleared only for that byte
  //
  // Complexity: O(n) for patterns ≤ 62 bytes, fallback to O(n×m) sliding window
  if !has_star {
    let pat_len = tokens.length()
    let offsets : Array[Int] = []
    let dlen = data.length()
    if pat_len <= 62 {
      // Shift-Or bit-parallel: O(n) for wildcard patterns
      let mask = FixedArray::make(256, -1) // all bits 1 = no match
      for i = 0; i < pat_len; i = i + 1 {
        let clear = (-1) ^ (1 << i)
        if tokens[i] == -1 {
          // ?? wildcard: accept all byte values at this position
          for c = 0; c < 256; c = c + 1 { mask[c] = mask[c] & clear }
        } else {
          mask[tokens[i]] = mask[tokens[i]] & clear
        }
      }
      let accept = 1 << (pat_len - 1)
      let mut state = -1
      for i = 0; i < dlen; i = i + 1 {
        state = (state << 1) | mask[data[i].to_int()]
        if (state & accept) == 0 {
          offsets.push(i - pat_len + 1)
          if offsets.length() >= 2000 { break }
        }
      }
    } else {
      // Fallback: sliding window for patterns > 62 bytes
      for i = 0; i <= dlen - pat_len; i = i + 1 {
        if match_seg(data, i, tokens) { offsets.push(i) }
        if offsets.length() >= 2000 { break }
      }
    }
    let lens : Array[Int] = []
    for _i = 0; _i < offsets.length(); _i = _i + 1 { lens.push(pat_len) }
    return (offsets, lens)
  }

  let segments = split_by_star(tokens)
  if segments.length() == 0 { return ([], []) }
  let offsets : Array[Int] = []
  let lens : Array[Int] = []
  let seg0 = segments[0]
  let seg0_len = seg0.length()
  let max_gap = 4096
  let dlen = data.length()

  for i = 0; i <= dlen - seg0_len; i = i + 1 {
    if !match_seg(data, i, seg0) { continue }
    let mut pos = i + seg0_len
    let mut all_ok = true
    for s = 1; s < segments.length(); s = s + 1 {
      let seg = segments[s]
      let slen = seg.length()
      let limit = if pos + max_gap < dlen { pos + max_gap } else { dlen }
      let mut found = false
      for j = pos; j <= limit - slen; j = j + 1 {
        if match_seg(data, j, seg) { pos = j + slen; found = true; break }
      }
      if !found { all_ok = false; break }
    }
    if all_ok { offsets.push(i); lens.push(pos - i) }
    if offsets.length() >= 2000 { break }
  }
  (offsets, lens)
}

///|
/// Search data for a hex pattern with ?? and * wildcards.
/// Returns Some((offsets, match_lengths)) or None if pattern is invalid.
pub fn find_hex_pattern(
  data : Bytes,
  pattern : String,
) -> (Array[Int], Array[Int])? {
  let tokens = match parse_pattern_tokens(pattern) {
    Some(t) => t
    None => {
      match parse_hex_string(pattern) {
        Some(bytes) => {
          let offsets = find_all_bytes(data, bytes)
          let lens : Array[Int] = []
          for _i = 0; _i < offsets.length(); _i = _i + 1 { lens.push(bytes.length()) }
          return Some((offsets, lens))
        }
        None => return None
      }
    }
  }
  Some(search_with_tokens(data, tokens))
}

///|
/// Parse text pattern with wildcards: ? = any char, * = any length, *N = N chars, \ = escape.
fn parse_text_tokens(pattern : String) -> Array[Int]? {
  let tokens : Array[Int] = []
  let len = pattern.length()
  let mut i = 0
  while i < len {
    let ch = pattern.get_char(i).unwrap()
    if ch == '\\' && i + 1 < len {
      let next = pattern.get_char(i + 1).unwrap()
      let code = next.to_int()
      if code <= 127 { tokens.push(code) } else { return None }
      i = i + 2
    } else if ch == '?' {
      tokens.push(-1)
      i = i + 1
    } else if ch == '*' {
      let mut n = 0
      let mut j = i + 1
      while j < len {
        let d = pattern.get_char(j).unwrap().to_int() - 0x30
        if d < 0 || d > 9 { break }
        n = n * 10 + d
        j = j + 1
      }
      if j > i + 1 && n > 0 {
        for _k = 0; _k < n; _k = _k + 1 { tokens.push(-1) }
        i = j
      } else {
        tokens.push(-2)
        i = i + 1
      }
    } else {
      let code = ch.to_int()
      if code <= 127 { tokens.push(code) } else { return None }
      i = i + 1
    }
  }
  if tokens.length() == 0 { return None }
  let merged : Array[Int] = []
  for k = 0; k < tokens.length(); k = k + 1 {
    if tokens[k] == -2 && merged.length() > 0 && merged[merged.length() - 1] == -2 {
      continue
    }
    merged.push(tokens[k])
  }
  if merged.length() == 1 && merged[0] == -2 { return None }
  Some(merged)
}

///|
/// Search data for a text pattern with ?, *, *N wildcards and \ escape.
/// Returns Some((offsets, match_lengths)) or None if pattern is invalid.
pub fn find_text_pattern(
  data : Bytes,
  pattern : String,
) -> (Array[Int], Array[Int])? {
  match parse_text_tokens(pattern) {
    Some(tokens) => Some(search_with_tokens(data, tokens))
    None => None
  }
}

