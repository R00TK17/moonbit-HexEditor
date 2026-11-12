// Hex Editor — Hash / Checksum
// MD5 / SHA1 / SHA256 / SHA224 / SM3 digests, returned as lowercase hex strings.
// Wraps moonbitlang/x/crypto (pure MoonBit, works on both native and wasm-gc).

///|
const HEX_LOWER = "0123456789abcdef"

///|
/// Format a byte array as a lowercase hex string.
fn to_lower_hex(data : FixedArray[Byte]) -> String {
  let sb = StringBuilder()
  for i = 0; i < data.length(); i = i + 1 {
    let b = data[i].to_int()
    sb.write_char(HEX_LOWER.get_char((b >> 4) & 0xF).unwrap())
    sb.write_char(HEX_LOWER.get_char(b & 0xF).unwrap())
  }
  sb.to_string()
}

///|
#derive(Debug)
pub struct HashResult {
  name : String
  value : String
}

///|
pub extend HashResult with @debug.Debug::{to_repr}

///|
/// MD5 digest (hex, lowercase). MD5 is cryptographically broken — prefer SHA-256.
pub fn md5_hex(data : Bytes) -> String {
  to_lower_hex(@crypto.md5(data))
}

///|
/// SHA-1 digest (hex, lowercase). SHA-1 is cryptographically broken — prefer SHA-256.
pub fn sha1_hex(data : Bytes) -> String {
  to_lower_hex(@crypto.sha1(data))
}

///|
/// SHA-256 digest (hex, lowercase).
pub fn sha256_hex(data : Bytes) -> String {
  to_lower_hex(@crypto.sha256(data))
}

///|
/// SHA-224 digest (hex, lowercase).
pub fn sha224_hex(data : Bytes) -> String {
  to_lower_hex(@crypto.sha224(data))
}

///|
/// SM3 digest (Chinese national standard, hex, lowercase).
pub fn sm3_hex(data : Bytes) -> String {
  to_lower_hex(@crypto.sm3(data))
}

///|
/// Compute all supported digests at once.
pub fn hash_all(data : Bytes) -> Array[HashResult] {
  [
    { name: "MD5", value: md5_hex(data), },
    { name: "SHA1", value: sha1_hex(data), },
    { name: "SHA256", value: sha256_hex(data), },
    { name: "SHA224", value: sha224_hex(data), },
    { name: "SM3", value: sm3_hex(data), },
  ]
}

///|
test "hash vectors" {
  assert_eq(md5_hex(b"abc"), "900150983cd24fb0d6963f7d28e17f72")
  assert_eq(md5_hex(b""), "d41d8cd98f00b204e9800998ecf8427e")
  assert_eq(sha1_hex(b"abc"), "a9993e364706816aba3e25717850c26c9cd0d89d")
  assert_eq(
    sha256_hex(b"abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  assert_eq(
    sha256_hex(b""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_eq(
    sha224_hex(b"abc"),
    "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7",
  )
  assert_eq(
    sm3_hex(b"abc"),
    "66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0",
  )
  let all = hash_all(b"abc")
  assert_eq(all.length(), 5)
  assert_eq(all[0].name, "MD5")
  assert_eq(all[0].value, "900150983cd24fb0d6963f7d28e17f72")
}
